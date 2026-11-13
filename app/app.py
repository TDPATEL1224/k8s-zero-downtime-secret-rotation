"""
CLO835 Project 12 - Secrets rotation with zero downtime
Web tier: serves "/" and "/healthz". Student: 105823249
"""
import os

import pymysql
from flask import Flask

app = Flask(__name__)

# NON-secret settings: come from env vars set in the Deployment YAML.
DBHOST = os.environ.get("DBHOST", "mysql-105823249")
DBPORT = int(os.environ.get("DBPORT", "3306"))
DATABASE = os.environ.get("DATABASE", "app_105823249")

# SECRET settings: come from files that Kubernetes mounts from the Secret.
CRED_DIR = os.environ.get("CRED_DIR", "/etc/dbcred")


def read_cred(name):
    """Read one credential file fresh every time (Task 4: never cache)."""
    with open(os.path.join(CRED_DIR, name)) as f:
        return f.read().strip()


def get_connection():
    """Open a brand-new MySQL connection using whatever the files say NOW."""
    return pymysql.connect(
        host=DBHOST,
        port=DBPORT,
        database=DATABASE,
        user=read_cred("username"),
        password=read_cred("password"),
        connect_timeout=3,
        read_timeout=3,
        write_timeout=3,
    )


@app.route("/")
def home():
    """Task 2: return a seeded row with my ID + the DB user I logged in as."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT owner, SUBSTRING_INDEX(CURRENT_USER(), '@', 1) "
                "FROM records ORDER BY id LIMIT 1"
            )
            owner, user = cur.fetchone()
    finally:
        conn.close()
    return f"owner={owner} connected_as={user}\n", 200, {"Content-Type": "text/plain"}


@app.route("/healthz")
def healthz():
    """Task 1: readiness probe. 200 only if this Pod can really run SELECT 1."""
    try:
        conn = get_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        finally:
            conn.close()
        return "ok\n", 200, {"Content-Type": "text/plain"}
    except Exception as e:
        return f"db error: {e}\n", 503, {"Content-Type": "text/plain"}