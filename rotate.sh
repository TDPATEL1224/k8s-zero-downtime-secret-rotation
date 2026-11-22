#!/usr/bin/env bash
# CLO835 Project 12 - rotate.sh (Task 8)
# Usage: ./rotate.sh v2     forward rotation
#        ./rotate.sh v1     roll back to v1 (v1 still exists)
#        ./rotate.sh v3     fresh credential (when v1 was already dropped)
# Order: create NEW user -> update Secret -> rolling restart -> verify -> PAUSE -> drop OLD user.
set -euo pipefail

SID=105823249
NS="rotation-$SID"
SECRET="db-cred-$SID"
DEPLOY="webapp-$SID"
MYSQL="deploy/mysql-$SID"
DB="app_$SID"
URL="http://localhost:30080/"

VERSION="${1:?usage: ./rotate.sh <version>   e.g. ./rotate.sh v2}"
[[ "$VERSION" =~ ^v[0-9]+$ ]] || { echo "Version must look like v1, v2, v3"; exit 1; }
NEW_USER="appuser_${VERSION}_${SID}"

say() { echo; echo "[$(date +%T)] $*"; }

# Run SQL as root INSIDE the MySQL Pod. The root password never leaves the Pod.
mysql_root() {
  kubectl -n "$NS" exec -i "$MYSQL" -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'
}

# Who is live right now? Read it from the Secret itself.
OLD_USER=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.username}' | base64 -d)
if [ "$OLD_USER" = "$NEW_USER" ]; then
  echo "The app is already using $NEW_USER. Nothing to do."; exit 1
fi
NEW_PASS=$(openssl rand -hex 12)
say "Rotating: $OLD_USER  ->  $NEW_USER"

# 1) Create the new user (or reset its password if it already exists) with identical grants.
say "Step 1/5: create DB user $NEW_USER with SELECT on $DB.*"
mysql_root <<SQL
CREATE USER IF NOT EXISTS '$NEW_USER'@'%' IDENTIFIED BY '$NEW_PASS';
ALTER USER '$NEW_USER'@'%' IDENTIFIED BY '$NEW_PASS';
GRANT SELECT ON $DB.* TO '$NEW_USER'@'%';
SQL
kubectl -n "$NS" exec "$MYSQL" -- env MYSQL_PWD="$NEW_PASS" \
  mysql -h 127.0.0.1 -u"$NEW_USER" -N -e "SELECT CONCAT('new credential works: ', CURRENT_USER())" "$DB"

# 2) Point the Secret at the new credential.
say "Step 2/5: update Secret $SECRET"
kubectl -n "$NS" create secret generic "$SECRET" \
  --from-literal=username="$NEW_USER" \
  --from-literal=password="$NEW_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3) Replace every web Pod, one at a time (maxUnavailable 0, maxSurge 1).
say "Step 3/5: rolling restart of deployment/$DEPLOY"
kubectl -n "$NS" rollout restart "deployment/$DEPLOY"
kubectl -n "$NS" rollout status "deployment/$DEPLOY" --timeout=300s
echo "Waiting for old Pods to finish shutting down..."
while [ "$(kubectl -n "$NS" get pods -l app="$DEPLOY" --no-headers | wc -l)" -gt 2 ]; do sleep 1; done

# 4) Verify the app now reports the new user.
say "Step 4/5: verify / reports connected_as=$NEW_USER"
for i in 1 2 3 4 5; do
  out=$(curl -s --max-time 2 "$URL")
  echo "  $out"
  [[ "$out" == *"connected_as=$NEW_USER"* ]] || { echo "VERIFY FAILED - old user NOT dropped"; exit 1; }
  sleep 1
done

# 5) Mandatory pause before revoking the old credential.
say "Step 5/5: the app is fully on $NEW_USER. Old user $OLD_USER still exists."
read -r -p "Drop old user $OLD_USER now? Type 'yes' to drop, anything else to keep it: " answer
if [ "$answer" = "yes" ]; then
  echo "DROP USER IF EXISTS '$OLD_USER'@'%';" | mysql_root
  say "Dropped $OLD_USER. Rotation complete: live user is $NEW_USER."
else
  say "Kept $OLD_USER. Live user is $NEW_USER."
fi