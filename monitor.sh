#!/usr/bin/env bash
# CLO835 Project 12 - monitor.sh (Task 7)
# One request per second to the web app. Prints a running line:
#   total=<requests> failed=<failures> last=<last good response>
# Any non-200 answer or connection error counts as a failure.
# Stop with Ctrl+C; the final line is printed again.

URL="${1:-http://localhost:30080/}"
total=0
failed=0
last="(none yet)"

trap 'echo; echo "FINAL: total=$total failed=$failed"; exit 0' INT

while true; do
  # -s silent, --max-time 2: a hang counts as a failure, -w appends the HTTP code
  response=$(curl -s --max-time 2 -w $'\n%{http_code}' "$URL")
  code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  body="${body//$'\n'/}"
  total=$((total + 1))
  if [ "$code" = "200" ]; then
    last="$body"
  else
    failed=$((failed + 1))
    last="FAILED (http=$code)"
  fi
  echo "$(date +%T) total=$total failed=$failed last=$last"
  sleep 1
done