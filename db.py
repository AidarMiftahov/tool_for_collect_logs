# db.py
import sqlite3
import os

DB_PATH = r"C:\LogVisualizer\system_logs.db"

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row  # позволяет обращаться по имени столбца
    return conn

def get_unified_logs(limit=1000, offset=0, filters=None):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    query = "SELECT * FROM system_logs WHERE 1=1"
    params = []

    if filters:
        if filters.get('ip_address'):
            query += " AND ip_address LIKE ?"
            params.append('%' + filters['ip_address'] + '%')
        if filters.get('os_type'):
            query += " AND os_type = ?"
            params.append(filters['os_type'])
        if filters.get('log_level'):
            query += " AND log_level = ?"
            params.append(filters['log_level'])
        if filters.get('source'):
            query += " AND source LIKE ?"
            params.append('%' + filters['source'] + '%')

    query += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])

    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()
    return [dict(row) for row in rows]

def get_statistics():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    stats = {}
    cursor.execute("SELECT COUNT(*) FROM system_logs")
    stats['total'] = cursor.fetchone()[0]
    
    cursor.execute("SELECT os_type, COUNT(*) FROM system_logs GROUP BY os_type")
    stats['by_os'] = dict(cursor.fetchall())
    
    cursor.execute("SELECT log_level, COUNT(*) FROM system_logs GROUP BY log_level")
    stats['by_level'] = dict(cursor.fetchall())
    
    cursor.execute("SELECT COUNT(DISTINCT ip_address) FROM system_logs")
    stats['unique_hosts'] = cursor.fetchone()[0]
    
    conn.close()
    return stats

def get_unique_values():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT DISTINCT ip_address FROM system_logs WHERE ip_address IS NOT NULL ORDER BY ip_address")
    ips = [row[0] for row in cursor.fetchall()]
    
    cursor.execute("SELECT DISTINCT os_type FROM system_logs WHERE os_type IS NOT NULL ORDER BY os_type")
    os_types = [row[0] for row in cursor.fetchall()]
    
    cursor.execute("SELECT DISTINCT log_level FROM system_logs WHERE log_level IS NOT NULL ORDER BY log_level")
    levels = [row[0] for row in cursor.fetchall()]
    
    cursor.execute("SELECT DISTINCT source FROM system_logs WHERE source IS NOT NULL ORDER BY source")
    sources = [row[0] for row in cursor.fetchall()]
    
    conn.close()
    return {
        'ips': ips,
        'os_types': os_types,
        'levels': levels,
        'sources': sources
    }