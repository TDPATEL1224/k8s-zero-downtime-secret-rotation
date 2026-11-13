# CLO835 Project 12 - web tier image (built and pushed by GitHub Actions)
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Only what the app needs. mysql-client and ping from Assignment 1 are gone:
# all MySQL admin work happens inside the MySQL Pod, not in the web image.
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

# gunicorn: 2 worker processes, finishes in-flight requests on SIGTERM.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--graceful-timeout", "20", "app:app"]