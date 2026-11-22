#!/usr/bin/env bash
# CLO835 Project 12 - bootstrap.sh (Task 9)
# Builds EVERYTHING from a clean host (Docker, kind, kubectl only):
#   kind cluster -> namespace -> Secrets (v1) -> MySQL -> seed data -> web app -> smoke test
# Passwords are generated here with openssl and written ONLY into the cluster (Task 11).
set -euo pipefail

SID=105823249
CLUSTER="clo835-$SID"
NS="rotation-$SID"
URL="http://localhost:30080/"

cd "$(dirname "$0")"          # always run from the repo root
START=$(date +%s)
say() { echo; echo "[$(date +%T)] $*"; }

say "Checking required tools"
for tool in docker kind kubectl; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool"; exit 1; }
done

say "1/7 Creating kind cluster $CLUSTER (deleting any old one first)"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind delete cluster --name "$CLUSTER"
fi
kind create cluster --config manifests/kind-config.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=300s

say "2/7 Creating namespace $NS"
kubectl apply -f manifests/namespace.yaml

say "3/7 Creating Secrets with freshly generated passwords"
kubectl -n "$NS" create secret generic "mysql-root-$SID" \
  --from-literal=password="$(openssl rand -hex 12)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic "db-cred-$SID" \
  --from-literal=username="appuser_v1_$SID" \
  --from-literal=password="$(openssl rand -hex 12)" \
  --dry-run=client -o yaml | kubectl apply -f -

say "4/7 Deploying MySQL (PVC, Deployment, ClusterIP Service)"
kubectl apply -f manifests/mysql.yaml
kubectl -n "$NS" rollout status "deployment/mysql-$SID" --timeout=600s

say "5/7 Seeding database app_$SID and creating user appuser_v1_$SID"
kubectl apply -f manifests/mysql-seed-job.yaml
kubectl -n "$NS" wait --for=condition=complete "job/mysql-seed-$SID" --timeout=300s
kubectl -n "$NS" logs "job/mysql-seed-$SID" | tail -n 1

say "6/7 Deploying web app (2 replicas) and NodePort 30080"
kubectl apply -f manifests/webapp.yaml
kubectl -n "$NS" rollout status "deployment/webapp-$SID" --timeout=300s

say "7/7 Smoke test: curl $URL"
for i in $(seq 1 30); do
  if out=$(curl -sf --max-time 2 "$URL"); then
    echo "$out"
    say "DONE in $(( $(date +%s) - START )) seconds"
    kubectl -n "$NS" get pods -o wide
    exit 0
  fi
  sleep 2
done
echo "Smoke test FAILED: $URL did not answer"
exit 1