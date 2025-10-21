# app.py
from flask import Flask, request, render_template
import db

app = Flask(__name__)

@app.route('/')
def index():
    # Get filters
    filters = {
        'ip_address': request.args.get('ip_address', '').strip(),
        'os_type': request.args.get('os_type', '').strip(),
        'log_level': request.args.get('log_level', '').strip(),
        'source': request.args.get('source', '').strip()
    }
    
    page = int(request.args.get('page', 1))
    limit = 1000
    offset = (page - 1) * limit

    logs = db.get_unified_logs(limit=limit, offset=offset, filters=filters)
    stats = db.get_statistics()
    unique = db.get_unique_values()

    total_logs = stats['total']
    total_pages = (total_logs // limit) + (1 if total_logs % limit else 0)

    return render_template(
        'index.html',
        logs=logs,
        stats=stats,
        filters=filters,
        unique=unique,
        page=page,
        total_pages=total_pages,
        limit=limit
    )

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=True)