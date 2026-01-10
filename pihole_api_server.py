#!/usr/bin/env python3
"""
Pi-hole TRMNL API Server
Lightweight Flask server that exposes Pi-hole stats for TRMNL polling
Optimized for Pi Zero 2 W - minimal memory footprint
"""

from flask import Flask, jsonify, request, abort
import requests
import logging
import os
import json
from datetime import datetime, timedelta
from functools import lru_cache
import urllib3
import psutil

# Suppress SSL warnings for local Pi-hole
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

app = Flask(__name__)

# Configuration from environment variables
PIHOLE_URL = os.environ.get('PIHOLE_URL', 'http://localhost').rstrip('/')
PIHOLE_PASSWORD = os.environ.get('PIHOLE_PASSWORD', '')
API_TOKEN = os.environ.get('API_TOKEN', 'your-secret-token-here')
CACHE_DURATION = int(os.environ.get('CACHE_DURATION', '60'))  # seconds
SERVER_PORT = int(os.environ.get('SERVER_PORT', '8080'))

# Simple logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('pihole-trmnl-server')

# Session cache to avoid re-authenticating on every request
session_cache = {
    'sid': None,
    'csrf': None,
    'expires': None
}


def authenticate_pihole():
    """Authenticate with Pi-hole v6 API and return session data"""
    global session_cache

    # Check if we have a valid cached session
    if (session_cache['sid'] and session_cache['expires'] and
        datetime.now() < session_cache['expires']):
        logger.debug("Using cached session")
        return session_cache

    logger.info("Authenticating with Pi-hole...")
    auth_url = f"{PIHOLE_URL}/api/auth"

    try:
        response = requests.post(
            auth_url,
            json={"password": PIHOLE_PASSWORD},
            timeout=5,
            verify=False
        )

        if response.status_code == 200:
            data = response.json()
            sid = data.get('session', {}).get('sid')
            csrf = data.get('session', {}).get('csrf')
            validity = data.get('session', {}).get('validity', 1800)  # default 30 min

            if sid and csrf:
                # Cache session (expire 5 minutes before actual expiry for safety)
                session_cache['sid'] = sid
                session_cache['csrf'] = csrf
                session_cache['expires'] = datetime.now() + timedelta(seconds=validity - 300)

                logger.info("✓ Authentication successful")
                return session_cache

        logger.error(f"Authentication failed: {response.status_code}")
        return None

    except Exception as e:
        logger.error(f"Authentication error: {e}")
        return None


def get_pihole_stats(session_data):
    """Fetch statistics from Pi-hole API"""
    stats_url = f"{PIHOLE_URL}/api/stats/summary"

    try:
        headers = {
            'X-FTL-SID': session_data['sid'],
            'X-FTL-CSRF': session_data['csrf']
        }

        response = requests.get(
            stats_url,
            headers=headers,
            timeout=5,
            verify=False
        )

        if response.status_code == 200:
            logger.debug("✓ Stats fetched successfully")
            return response.json()
        elif response.status_code == 401:
            # Session expired, clear cache
            logger.warning("Session expired, clearing cache")
            session_cache['sid'] = None
            session_cache['expires'] = None
            return None
        else:
            logger.error(f"Failed to fetch stats: {response.status_code}")
            return None

    except Exception as e:
        logger.error(f"Error fetching stats: {e}")
        return None


def format_pihole_data(raw_data):
    """Format Pi-hole data for TRMNL display"""
    if not raw_data:
        return {
            "error": "Failed to fetch Pi-hole data",
            "pihole_enabled": False,
            "last_update": datetime.now().isoformat()
        }

    queries = raw_data.get('queries', {})
    clients = raw_data.get('clients', {})
    gravity = raw_data.get('gravity', {})

    return {
        # Main metrics
        "total_queries": queries.get('total', 0),
        "blocked_queries": queries.get('blocked', 0),
        "percent_blocked": round(queries.get('percent_blocked', 0.0), 1),
        "unique_domains": queries.get('unique_domains', 0),
        "active_clients": clients.get('active', 0),

        # Secondary metrics
        "queries_forwarded": queries.get('forwarded', 0),
        "queries_cached": queries.get('cached', 0),
        "domains_blocked": gravity.get('domains_being_blocked', 0),
        "total_clients": clients.get('total', 0),

        # Status
        "pihole_enabled": True,
        "last_update": datetime.now().isoformat(),

        # Additional stats
        "query_frequency": round(queries.get('frequency', 0.0), 2),

        # Top query types (simplified)
        "query_types": {
            "A": queries.get('types', {}).get('A', 0),
            "AAAA": queries.get('types', {}).get('AAAA', 0),
            "HTTPS": queries.get('types', {}).get('HTTPS', 0),
            "PTR": queries.get('types', {}).get('PTR', 0)
        }
    }


def get_system_info():
    """Get system resource information (CPU, RAM, disk usage)"""
    try:
        # CPU information
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_count = psutil.cpu_count()
        cpu_freq = psutil.cpu_freq()

        # Memory information
        memory = psutil.virtual_memory()

        # Disk information for root partition
        disk = psutil.disk_usage('/')

        # System uptime
        boot_time = psutil.boot_time()
        uptime_seconds = int(datetime.now().timestamp() - boot_time)

        # Load average (Unix systems only)
        try:
            load_avg = os.getloadavg()
            load_average = {
                "1min": round(load_avg[0], 2),
                "5min": round(load_avg[1], 2),
                "15min": round(load_avg[2], 2)
            }
        except (AttributeError, OSError):
            load_average = None

        return {
            "cpu": {
                "percent": round(cpu_percent, 1),
                "count": cpu_count,
                "frequency_mhz": round(cpu_freq.current, 0) if cpu_freq else None
            },
            "memory": {
                "total_mb": round(memory.total / (1024 * 1024), 1),
                "used_mb": round(memory.used / (1024 * 1024), 1),
                "available_mb": round(memory.available / (1024 * 1024), 1),
                "percent": round(memory.percent, 1)
            },
            "disk": {
                "total_gb": round(disk.total / (1024 * 1024 * 1024), 2),
                "used_gb": round(disk.used / (1024 * 1024 * 1024), 2),
                "available_gb": round(disk.free / (1024 * 1024 * 1024), 2),
                "percent": round(disk.percent, 1)
            },
            "load_average": load_average,
            "uptime_seconds": uptime_seconds,
            "uptime_hours": round(uptime_seconds / 3600, 1),
            "timestamp": datetime.now().isoformat()
        }

    except Exception as e:
        logger.error(f"Error getting system info: {e}")
        return {
            "error": f"Failed to retrieve system information: {str(e)}",
            "timestamp": datetime.now().isoformat()
        }


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint - no auth required"""
    return jsonify({
        "status": "healthy",
        "service": "pihole-trmnl-api",
        "timestamp": datetime.now().isoformat()
    })


@app.route('/stats', methods=['GET'])
def get_stats():
    """
    Main endpoint for TRMNL to poll
    Requires token authentication via query parameter

    Usage: http://your-pihole-ip:8080/stats?token=YOUR_SECRET_TOKEN
    """
    # Check token authentication
    token = request.args.get('token')
    if not token or token != API_TOKEN:
        logger.warning(f"Unauthorized access attempt from {request.remote_addr}")
        abort(401, description="Unauthorized: Invalid or missing token")

    logger.info(f"Stats request from {request.remote_addr}")

    # Authenticate with Pi-hole (uses cache if available)
    session_data = authenticate_pihole()
    if not session_data or not session_data.get('sid'):
        logger.error("Failed to authenticate with Pi-hole")
        return jsonify({
            "error": "Pi-hole authentication failed",
            "pihole_enabled": False,
            "last_update": datetime.now().isoformat()
        }), 500

    # Fetch stats from Pi-hole
    raw_data = get_pihole_stats(session_data)

    # If session expired, try one more time with fresh auth
    if not raw_data:
        logger.info("Retrying with fresh authentication...")
        session_data = authenticate_pihole()
        if session_data and session_data.get('sid'):
            raw_data = get_pihole_stats(session_data)

    # Format and return data
    formatted_data = format_pihole_data(raw_data)

    logger.info(f"Returning stats: {formatted_data.get('total_queries', 0)} queries, "
                f"{formatted_data.get('blocked_queries', 0)} blocked "
                f"({formatted_data.get('percent_blocked', 0)}%)")

    return jsonify(formatted_data)


@app.route('/stats/raw', methods=['GET'])
def get_stats_raw():
    """
    Debug endpoint - returns raw Pi-hole API response
    Requires token authentication
    """
    token = request.args.get('token')
    if not token or token != API_TOKEN:
        abort(401, description="Unauthorized: Invalid or missing token")

    session_data = authenticate_pihole()
    if not session_data or not session_data.get('sid'):
        return jsonify({"error": "Authentication failed"}), 500

    raw_data = get_pihole_stats(session_data)
    if not raw_data:
        return jsonify({"error": "Failed to fetch stats"}), 500

    return jsonify(raw_data)


@app.route('/info/system', methods=['GET'])
def get_system_info_endpoint():
    """
    System information endpoint - returns CPU, RAM, disk usage
    Requires token authentication

    Usage: http://your-pihole-ip:8080/info/system?token=YOUR_SECRET_TOKEN
    """
    token = request.args.get('token')
    if not token or token != API_TOKEN:
        logger.warning(f"Unauthorized access attempt to /info/system from {request.remote_addr}")
        abort(401, description="Unauthorized: Invalid or missing token")

    logger.info(f"System info request from {request.remote_addr}")

    system_info = get_system_info()

    logger.debug(f"System info: CPU {system_info.get('cpu', {}).get('percent', 0)}%, "
                 f"RAM {system_info.get('memory', {}).get('percent', 0)}%")

    return jsonify(system_info)


@app.route('/', methods=['GET'])
def index():
    """Root endpoint with API documentation"""
    return jsonify({
        "service": "Pi-hole TRMNL API Server",
        "version": "1.0.0",
        "endpoints": {
            "/health": "Health check (no auth)",
            "/stats?token=YOUR_TOKEN": "Formatted Pi-hole stats for TRMNL",
            "/stats/raw?token=YOUR_TOKEN": "Raw Pi-hole API response (debug)",
            "/info/system?token=YOUR_TOKEN": "System info (CPU, RAM, disk usage)"
        },
        "documentation": "https://github.com/jetsharklambo/TRMNL-Pihole-Monitor"
    })


@app.errorhandler(401)
def unauthorized(error):
    """Custom 401 error handler"""
    return jsonify({
        "error": "Unauthorized",
        "message": str(error.description)
    }), 401


@app.errorhandler(500)
def internal_error(error):
    """Custom 500 error handler"""
    return jsonify({
        "error": "Internal Server Error",
        "message": "An error occurred while processing your request"
    }), 500


if __name__ == '__main__':
    logger.info("=" * 60)
    logger.info("Pi-hole TRMNL API Server Starting")
    logger.info("=" * 60)
    logger.info(f"Pi-hole URL: {PIHOLE_URL}")
    logger.info(f"Server Port: {SERVER_PORT}")
    logger.info(f"API Token: {'Configured' if API_TOKEN != 'your-secret-token-here' else 'NOT SET (INSECURE!)'}")
    logger.info(f"Cache Duration: {CACHE_DURATION} seconds")
    logger.info("=" * 60)

    if API_TOKEN == 'your-secret-token-here':
        logger.warning("⚠️  WARNING: Using default API token! Set API_TOKEN environment variable!")

    # Run Flask server
    # For production, use Waitress or Gunicorn instead of Flask's dev server
    app.run(
        host='0.0.0.0',  # Listen on all interfaces (accessible via Tailscale)
        port=SERVER_PORT,
        debug=False,  # Disable debug mode for security
        threaded=True   # Handle multiple requests (Pi Zero 2 W can handle this)
    )
