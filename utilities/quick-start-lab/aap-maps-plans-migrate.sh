#!/bin/bash
# After Provider is Ready: launch Maps + Plans via AAP, Start migration, poll.
set -euo pipefail
cd "$(dirname "$0")"
# Optional overrides must be set *before* sourcing lab.env (lab.env may define COLD_VM_NAME/PLAN_NAME).
QS_PLAN_NAME="${QS_PLAN_NAME:-}"
QS_VM_NAME="${QS_VM_NAME:-}"
# shellcheck disable=SC1091
set -a; source ./lab.env; set +a
export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
API="${AAP_URL}${AAP_API_PREFIX:-/api/controller/v2}"
PLAN_NAME="${QS_PLAN_NAME:-${PLAN_NAME:-quickstart-aap-cold-01}}"
VM_NAME="${QS_VM_NAME:-${COLD_VM_NAME:-rhel-92}}"
export API PLAN_NAME VM_NAME

TOK=$(curl -sk -u "$AAP_USER:$AAP_PASSWORD" -H "Content-Type: application/json" \
  -d '{"description":"maps-plans","scope":"write","application":null}' \
  "${AAP_URL}/api/gateway/v1/tokens/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')
echo "$TOK" > /tmp/aap.tok
auth() { curl -sk -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" "$@"; }

launch() {
  local jt_id="$1" label="$2" extra_json="$3"
  local resp job st
  echo "== Launch $label (JT $jt_id) =="
  resp=$(auth -X POST "$API/job_templates/${jt_id}/launch/" \
    -d "{\"extra_vars\":${extra_json},\"credentials\":[3,4]}")
  job=$(echo "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
  for i in $(seq 1 90); do
    st=$(auth "$API/jobs/${job}/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
    echo "[$i] $label job=$job $st"
    case "$st" in
      successful) echo "OK_$label"; return 0 ;;
      failed|error|canceled)
        auth "$API/jobs/${job}/stdout/?format=txt" | tail -60
        return 1
        ;;
    esac
    sleep 10
  done
  return 2
}

MAPS_EXTRA=$(python3 -c 'import json; print(json.dumps({"source_name":"esxi-lab","target_name":"ocp-lab"}))')
PLANS_EXTRA=$(python3 - <<'PY'
import json, os
print(json.dumps({
  "source_name": "esxi-lab",
  "target_name": "ocp-lab",
  "mtv_plans_migration_request": {
    "source": "esxi-lab",
    "destination": "host",
    "target_namespace": os.environ.get("TARGET_NAMESPACE", "vm-workloads"),
    "network_map": "esxi-lab-host",
    "storage_map": "esxi-lab-host",
    "verify_plans_ready": True,
    "plan_name": os.environ["PLAN_NAME"],
    "type": "cold",
    "plan_overrides": {"preserveStaticIPs": False},
    "vms": [{"name": os.environ["VM_NAME"]}],
  }
}))
PY
)

launch 8 "MAPS" "$MAPS_EXTRA"
launch 9 "PLANS" "$PLANS_EXTRA"
oc get plan "$PLAN_NAME" -n openshift-mtv

oc delete migration "$PLAN_NAME" -n openshift-mtv --ignore-not-found
cat <<EOF | oc apply -f -
apiVersion: forklift.konveyor.io/v1beta1
kind: Migration
metadata:
  name: ${PLAN_NAME}
  namespace: openshift-mtv
spec:
  plan:
    name: ${PLAN_NAME}
    namespace: openshift-mtv
EOF

launch 10 "MIGRATE_NOOP" "$MAPS_EXTRA" || true

for i in $(seq 1 120); do
  vms=$(oc get plan "$PLAN_NAME" -n openshift-mtv -o jsonpath='{range .status.migration.vms[*]}{.name}:{.phase} {end}' 2>/dev/null || true)
  cond=$(oc get plan "$PLAN_NAME" -n openshift-mtv -o jsonpath='{range .status.conditions[*]}{.type}={.status};{end}' 2>/dev/null || true)
  echo "[$i] vms=[$vms] cond=[$cond]"
  if echo "$cond" | grep -qE '(^|;)Succeeded=True'; then
    echo SUCCEEDED
    break
  fi
  if echo "$cond" | grep -qE '(^|;)Failed=True'; then
    echo FAILED
    exit 1
  fi
  sleep 20
done
echo "$cond" | grep -qE '(^|;)Succeeded=True' || { echo TIMEOUT; exit 2; }

auth "$API/jobs/?order_by=-id&page_size=15" | python3 -c 'import sys,json; d=json.load(sys.stdin);
[print(r["id"], r["status"], r["name"]) for r in d.get("results",[])]'
oc get plan,migration "$PLAN_NAME" -n openshift-mtv
oc get vm -n "${TARGET_NAMESPACE:-vm-workloads}"
echo DONE
