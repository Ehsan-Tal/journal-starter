#!/usr/bin/env bash
# Loads a SQL schema into the private RDS instance by running a throwaway psql
# pod inside the cluster, and creates a Kubernetes Secret for your app.
# Usage: scripts/load_schema.sh path/to/schema.sql
set -euo pipefail

SCHEMA_FILE="$(realpath "${1:?Usage: $0 path/to/schema.sql}")"
NAMESPACE="${NAMESPACE:-default}"

# Find the Terraform folder: $TF_DIR if set, else this script's own folder or its parent.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${TF_DIR:-}" ]; then
  :
elif [ -f "$SCRIPT_DIR/main.tf" ]; then
  TF_DIR="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/../main.tf" ]; then
  TF_DIR="$SCRIPT_DIR/.."
else
  echo "ERROR: cannot find main.tf next to or above this script." >&2
  echo "Run again with: TF_DIR=/path/to/terraform-folder $0 $*" >&2
  exit 1
fi
cd "$TF_DIR"
echo "Using Terraform folder: $(pwd)"

tf() { terraform output -raw "$1" 2>/dev/null || true; }
REGION=$(tf region);  CLUSTER=$(tf cluster_name)
DB_HOST=$(tf db_host); DB_PORT=$(tf db_port)
DB_NAME=$(tf db_name); DB_USER=$(tf db_username)

# Fail early with a clear message if Terraform has no outputs (apply not finished, or wrong folder)
for v in REGION CLUSTER DB_HOST DB_PORT DB_NAME DB_USER; do
  if [ -z "${!v}" ]; then
    echo "ERROR: terraform output for $v is empty in $(pwd)." >&2
    echo "Run 'terraform apply' to completion in this folder (check with: terraform output)." >&2
    exit 1
  fi
done

# Use a throwaway kubeconfig that contains ONLY this EKS cluster. Your own ~/.kube/config
# (minikube, other clusters, odd contexts) is never read or modified, so nothing in it can
# redirect these kubectl calls to the wrong cluster.
KUBE_TMP=$(mktemp -d)
trap 'rm -rf "$KUBE_TMP"' EXIT
export KUBECONFIG="$KUBE_TMP/config"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
KUBECTL=(kubectl -n "$NAMESPACE")
echo "Target: EKS cluster $CLUSTER (context $(kubectl config current-context)), namespace $NAMESPACE"

DB_PASS=$(tf db_password)   # fixed test password from var.db_password
[ -n "$DB_PASS" ] || { echo "ERROR: terraform output db_password is empty." >&2; exit 1; }

# Percent-encode the password in case you change it to one with URL-special characters.
# sslmode=require: RDS Postgres 15+ rejects unencrypted connections.
# (If your app uses asyncpg directly, change the query string to ?ssl=require.)
DB_URL=$(DB_USER="$DB_USER" DB_PASS="$DB_PASS" DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" python3 - <<'PY'
import os
from urllib.parse import quote
e = os.environ
print(f"postgresql://{quote(e['DB_USER'], safe='')}:{quote(e['DB_PASS'], safe='')}@{e['DB_HOST']}:{e['DB_PORT']}/{e['DB_NAME']}?sslmode=require")
PY
)

# Kubernetes Secret your app can consume (idempotent).
"${KUBECTL[@]}" create secret generic db-credentials \
  --from-literal=host="$DB_HOST" --from-literal=port="$DB_PORT" \
  --from-literal=dbname="$DB_NAME" --from-literal=username="$DB_USER" \
  --from-literal=password="$DB_PASS" \
  --from-literal=database_url="$DB_URL" \
  --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
unset DB_PASS

OVERRIDES=$(cat <<JSON
{"spec":{"containers":[{"name":"psql-loader","image":"postgres:16","stdin":true,"stdinOnce":true,
"env":[{"name":"PGPASSWORD","valueFrom":{"secretKeyRef":{"name":"db-credentials","key":"password"}}},
       {"name":"PGSSLMODE","value":"require"}],
"command":["psql","-h","$DB_HOST","-p","$DB_PORT","-U","$DB_USER","-d","$DB_NAME","-v","ON_ERROR_STOP=1"]}]}}
JSON
)

"${KUBECTL[@]}" run psql-loader --rm -i --restart=Never --quiet \
  --image=postgres:16 --overrides="$OVERRIDES" < "$SCHEMA_FILE"

echo "Schema loaded into $DB_NAME."
