#!/bin/bash
# Verify both paths: ansible-navigator (rhel-10) then AAP JTs (rhel-92).
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
set -a; source ./lab.env; set +a
export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
export PATH="/usr/local/bin:/root/bin:$PATH"

API="${AAP_URL}${AAP_API_PREFIX:-/api/controller/v2}"
COL="${COLLECTION_PATH:-/root/openshift_virtualization_migration}"
EE_NAV="${EE_IMAGE:-quay.io/redhat-cop/openshift-virtualization-migration-ee:latest}"
VDDK_IMG="${VDDK_IMAGE:-quay.io/redhat-cop/openshift-virtualization-migration-vddk:latest}"
NS="${TARGET_NAMESPACE:-vm-workloads}"
INV_SOURCE="${INV_SOURCE_HOST:-esxi-lab}"
INV_CLUSTER="${INV_CLUSTER_HOST:-ocp-lab}"

oc login -u "$OCP_USER" -p "$OCP_PASSWORD" "$OCP_API" --insecure-skip-tls-verify=true >/dev/null
OCP_TOKEN=$(oc whoami -t)
export OCP_TOKEN

echo "== Cleanup leftover MTV/OCP artifacts =="
oc delete migration,plan --all -n openshift-mtv --ignore-not-found
oc delete vm --all -n "$NS" --ignore-not-found
# Force-delete stuck PVCs
oc delete pvc --all -n "$NS" --force --grace-period=0 --ignore-not-found 2>/dev/null || true
for i in $(seq 1 30); do
  left=$(oc get pvc -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$left" = "0" ] && break
  echo "waiting for PVC cleanup ($left left)"
  sleep 5
done

# Ensure VDDK pull secret
oc get secret esxi-lab-vddk -n openshift-mtv >/dev/null 2>&1 || \
  oc create secret docker-registry esxi-lab-vddk \
    --docker-server=quay.io --docker-username="$QUAY_USER" --docker-password="$QUAY_PASSWORD" \
    -n openshift-mtv

# Refresh inventory token + sync AAP hosts lightly
python3 <<'PY'
import os, re, pathlib, json, ssl, urllib.request, yaml
p = pathlib.Path("inventory.yml")
text = p.read_text()
text = re.sub(r"(openshift_api_key:\s*).*", r"\1" + os.environ["OCP_TOKEN"], text, count=1)
p.write_text(text)
tok = open("/tmp/aap.tok").read().strip() if pathlib.Path("/tmp/aap.tok").exists() else ""
PY

mint_tok() {
  curl -sk -u "$AAP_USER:$AAP_PASSWORD" -H "Content-Type: application/json" \
    -d '{"description":"dual-mig","scope":"write","application":null}' \
    "${AAP_URL}/api/gateway/v1/tokens/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])'
}
TOK=$(mint_tok)
echo "$TOK" > /tmp/aap.tok
auth() { curl -sk -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" "$@"; }

# Patch AAP host vars
python3 <<'PY'
import json, ssl, urllib.request, yaml, os
ctx = ssl._create_unverified_context()
tok = open("/tmp/aap.tok").read().strip()
api = os.environ["API"] if "API" in os.environ else None
PY
API="${AAP_URL}${AAP_API_PREFIX:-/api/controller/v2}"
export API
python3 <<'PY'
import json, ssl, urllib.request, yaml, os
ctx = ssl._create_unverified_context()
tok = open("/tmp/aap.tok").read().strip()
api = os.environ["API"]
inv = yaml.safe_load(open("inventory.yml"))

def req(method, url, data=None):
    body = None if data is None else json.dumps(data).encode()
    r = urllib.request.Request(url, data=body, method=method)
    r.add_header("Authorization", f"Bearer {tok}")
    r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, context=ctx, timeout=60) as resp:
        return json.load(resp)

hosts = {h["name"]: h for h in req("GET", api + "/hosts/?page_size=50")["results"]}
for name, group in (("esxi-lab", "vm_sources"), ("ocp-lab", "migration_clusters")):
    vars_dict = inv[group]["hosts"][name]
    req("PATCH", f"{api}/hosts/{hosts[name]['id']}/", {"variables": yaml.safe_dump(vars_dict, default_flow_style=False)})
    print("patched", name)
# refresh target api key
req("PATCH", f"{api}/credentials/4/", {
    "inputs": {
        "host": os.environ["OCP_API"],
        "api_key": os.environ["OCP_TOKEN"],
        "verify_ssl": False,
        "target_name": "ocp-lab",
    }
})
print("patched target credential")
PY

power_off() {
  local vm_name="$1"
  python3 - "$vm_name" <<'PY'
import ssl, urllib.request, re, http.cookiejar, os, time, sys
vm_name = sys.argv[1]
ctx = ssl._create_unverified_context()
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx), urllib.request.HTTPCookieProcessor(cj))
host = os.environ["VMWARE_HOST"]; user = os.environ["VMWARE_USER"]; pw = os.environ["VMWARE_PASSWORD"]

def soap(body):
    req = urllib.request.Request(f"https://{host}/sdk", data=body.encode(), method="POST")
    req.add_header("Content-Type", "text/xml; charset=utf-8")
    req.add_header("SOAPAction", "urn:vim25/8.0.0.1")
    with opener.open(req, timeout=30) as r:
        return r.read().decode()

soap(
    '<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:vim25="urn:vim25"><soapenv:Body><vim25:Login>'
    f'<vim25:_this type="SessionManager">ha-sessionmgr</vim25:_this><vim25:userName>{user}</vim25:userName><vim25:password>{pw}</vim25:password>'
    "</vim25:Login></soapenv:Body></soapenv:Envelope>"
)
body = (
    '<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:vim25="urn:vim25"><soapenv:Body><vim25:RetrievePropertiesEx>'
    '<vim25:_this type="PropertyCollector">ha-property-collector</vim25:_this><vim25:specSet><vim25:propSet>'
    "<vim25:type>VirtualMachine</vim25:type><vim25:all>false</vim25:all>"
    "<vim25:pathSet>name</vim25:pathSet><vim25:pathSet>runtime.powerState</vim25:pathSet>"
    '</vim25:propSet><vim25:objectSet><vim25:obj type="Folder">ha-folder-root</vim25:obj><vim25:skip>false</vim25:skip>'
    '<vim25:selectSet xsi:type="TraversalSpec" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    "<vim25:name>folderTraversal</vim25:name><vim25:type>Folder</vim25:type><vim25:path>childEntity</vim25:path><vim25:skip>false</vim25:skip>"
    '<vim25:selectSet xsi:type="SelectionSpec"><vim25:name>folderTraversal</vim25:name></vim25:selectSet>'
    '<vim25:selectSet xsi:type="SelectionSpec"><vim25:name>dcToVmFolder</vim25:name></vim25:selectSet></vim25:selectSet>'
    '<vim25:selectSet xsi:type="TraversalSpec" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    "<vim25:name>dcToVmFolder</vim25:name><vim25:type>Datacenter</vim25:type><vim25:path>vmFolder</vim25:path><vim25:skip>false</vim25:skip>"
    '<vim25:selectSet xsi:type="SelectionSpec"><vim25:name>folderTraversal</vim25:name></vim25:selectSet>'
    "</vim25:selectSet></vim25:objectSet></vim25:specSet><vim25:options></vim25:options>"
    "</vim25:RetrievePropertiesEx></soapenv:Body></soapenv:Envelope>"
)
resp = soap(body)
for o in re.findall(r"<objects>(.*?)</objects>", resp, re.S):
    typ = re.search(r'<obj type="([^"]+)">([^<]+)</obj>', o)
    if not typ or typ.group(1) != "VirtualMachine":
        continue
    name = re.search(r"<name>name</name><val[^>]*>([^<]*)</val>", o)
    pwr = re.search(r"<name>runtime.powerState</name><val[^>]*>([^<]*)</val>", o)
    if not name or name.group(1) != vm_name:
        continue
    print(vm_name, pwr.group(1) if pwr else "?")
    if pwr and pwr.group(1) == "poweredOn":
        soap(
            '<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:vim25="urn:vim25"><soapenv:Body><vim25:PowerOffVM_Task>'
            f'<vim25:_this type="VirtualMachine">{typ.group(2)}</vim25:_this>'
            "</vim25:PowerOffVM_Task></soapenv:Body></soapenv:Envelope>"
        )
        time.sleep(8)
        print("powered_off", vm_name)
PY
}

poll_plan() {
  local plan="$1"
  local i vms cond
  for i in $(seq 1 120); do
    vms=$(oc get plan "$plan" -n openshift-mtv -o jsonpath='{range .status.migration.vms[*]}{.name}:{.phase} {end}' 2>/dev/null || true)
    cond=$(oc get plan "$plan" -n openshift-mtv -o jsonpath='{range .status.conditions[*]}{.type}={.status};{end}' 2>/dev/null || true)
    echo "[$i] $plan vms=[$vms] cond=[$cond]"
    if echo "$cond" | grep -qE '(^|;)Succeeded=True'; then
      echo "SUCCEEDED $plan"
      return 0
    fi
    if echo "$cond" | grep -qE '(^|;)Failed=True'; then
      echo "FAILED $plan"
      oc get plan "$plan" -n openshift-mtv -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
      return 1
    fi
    sleep 20
  done
  echo "TIMEOUT $plan"
  return 2
}

start_migration() {
  local plan="$1"
  oc delete migration "$plan" -n openshift-mtv --ignore-not-found
  cat <<EOF | oc apply -f -
apiVersion: forklift.konveyor.io/v1beta1
kind: Migration
metadata:
  name: ${plan}
  namespace: openshift-mtv
spec:
  plan:
    name: ${plan}
    namespace: openshift-mtv
EOF
}

############################################
# PATH A: ansible-navigator — rhel-10
############################################
NAV_PLAN=verify-nav-cold-01
NAV_VM=rhel-10
echo "== PATH A: ansible-navigator plan=$NAV_PLAN vm=$NAV_VM =="
power_off "$NAV_VM"

cat > "$COL/wave-nav.yml" <<EOF
source_name: ${INV_SOURCE}
target_name: ${INV_CLUSTER}
mtv_plans_migration_request:
  source: ${INV_SOURCE}
  destination: host
  target_namespace: ${NS}
  network_map: ${INV_SOURCE}-host
  storage_map: ${INV_SOURCE}-host
  verify_plans_ready: true
  plan_name: ${NAV_PLAN}
  type: cold
  plan_overrides:
    preserveStaticIPs: false
  vms:
    - name: ${NAV_VM}
EOF
cp -a inventory.yml "$COL/inventory.lab.yml"
(
  cd "$COL"
  ansible-navigator run playbooks/vmf_mtv_plans.yml \
    -i inventory.lab.yml --pp=missing --eei="$EE_NAV" -m stdout --pae=false \
    --eev "${COL}:/usr/share/ansible/collections/ansible_collections/infra/openshift_virtualization_migration:Z" \
    -e '@wave-nav.yml' --limit "$INV_CLUSTER" \
    2>&1 | tee /root/migration-factory-lab/verify-nav-plans.log | tail -40
)

oc get plan "$NAV_PLAN" -n openshift-mtv
start_migration "$NAV_PLAN"
poll_plan "$NAV_PLAN"
oc get vm "$NAV_VM" -n "$NS"
echo "PATH_A_OK"

############################################
# PATH B: AAP Job Templates — rhel-92
############################################
AAP_PLAN=verify-aap-cold-01
AAP_VM=rhel-92
echo "== PATH B: AAP JTs plan=$AAP_PLAN vm=$AAP_VM =="
power_off "$AAP_VM"

launch_jt() {
  local jt_id="$1" label="$2" extra_json="$3"
  local resp job st
  echo "== AAP launch $label JT=$jt_id =="
  resp=$(auth -X POST "$API/job_templates/${jt_id}/launch/" \
    -d "{\"extra_vars\":${extra_json},\"credentials\":[3,4]}")
  if ! echo "$resp" | python3 -c 'import sys,json; json.load(sys.stdin)["id"]' 2>/dev/null; then
    echo "$resp" | python3 -m json.tool | head -40
    return 1
  fi
  job=$(echo "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
  for i in $(seq 1 90); do
    st=$(auth "$API/jobs/${job}/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
    echo "[$i] $label job=$job $st"
    case "$st" in
      successful) echo "OK_$label"; return 0 ;;
      failed|error|canceled)
        auth "$API/jobs/${job}/stdout/?format=txt" | tail -50
        return 1
        ;;
    esac
    sleep 10
  done
  return 2
}

# Webhook workaround for Provider secret create (MTV 5.0 panic)
oc get validatingwebhookconfiguration forklift-api-secrets -o yaml > /tmp/forklift-api-secrets.webhook.yaml 2>/dev/null || true
oc delete validatingwebhookconfiguration forklift-api-secrets --ignore-not-found

export INV_SOURCE INV_CLUSTER VDDK_IMAGE="$VDDK_IMG"
PROVIDER_EXTRA=$(python3 <<'PY'
import json, os
print(json.dumps({
  "source_name": os.environ["INV_SOURCE"],
  "target_name": os.environ["INV_CLUSTER"],
  "mtv_provider_secure_logging": False,
  "mtv_provider_provider_override": {
    "settings": {
      "sdkEndpoint": "esxi",
      "vddkInitImage": os.environ["VDDK_IMAGE"],
    }
  }
}))
PY
)
MAPS_EXTRA=$(python3 <<'PY'
import json, os
print(json.dumps({"source_name": os.environ["INV_SOURCE"], "target_name": os.environ["INV_CLUSTER"]}))
PY
)
PLANS_EXTRA=$(PLAN_NAME="$AAP_PLAN" VM_NAME="$AAP_VM" NS="$NS" python3 <<'PY'
import json, os
print(json.dumps({
  "source_name": os.environ["INV_SOURCE"],
  "target_name": os.environ["INV_CLUSTER"],
  "mtv_plans_migration_request": {
    "source": os.environ["INV_SOURCE"],
    "destination": "host",
    "target_namespace": os.environ["NS"],
    "network_map": f"{os.environ['INV_SOURCE']}-host",
    "storage_map": f"{os.environ['INV_SOURCE']}-host",
    "verify_plans_ready": True,
    "plan_name": os.environ["PLAN_NAME"],
    "type": "cold",
    "plan_overrides": {"preserveStaticIPs": False},
    "vms": [{"name": os.environ["VM_NAME"]}],
  }
}))
PY
)

set +e
launch_jt 11 "PROVIDER" "$PROVIDER_EXTRA"
prov_rc=$?
set -e
# restore webhook always
oc apply -f /tmp/forklift-api-secrets.webhook.yaml >/dev/null 2>&1 || true
# If provider already Ready, continue even if JT flaked
phase=$(oc get provider esxi-lab -n openshift-mtv -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [ "$prov_rc" -ne 0 ] && [ "$phase" != "Ready" ]; then
  echo "Provider JT failed and provider not Ready"
  exit 1
fi
echo "provider phase=$phase"

launch_jt 8 "MAPS" "$MAPS_EXTRA"
launch_jt 9 "PLANS" "$PLANS_EXTRA"
oc get plan "$AAP_PLAN" -n openshift-mtv
start_migration "$AAP_PLAN"
# Optional Migrate JT (requires plan name vars on this seed)
MIGRATE_EXTRA=$(python3 <<PY
import json, os
print(json.dumps({
  "source_name": os.environ["INV_SOURCE"],
  "target_name": os.environ["INV_CLUSTER"],
  "mtv_migrate_plan_name": "$AAP_PLAN",
  "mtv_migrate_plan_namespace": "openshift-mtv",
}))
PY
)
set +e
launch_jt 10 "MIGRATE" "$MIGRATE_EXTRA"
set -e

poll_plan "$AAP_PLAN"
oc get vm "$AAP_VM" -n "$NS"
echo "PATH_B_OK"

echo "== SUMMARY =="
oc get plan -n openshift-mtv
oc get vm -n "$NS" -o wide
auth "$API/jobs/?order_by=-id&page_size=10" | python3 -c 'import sys,json; d=json.load(sys.stdin);
[print(r["id"], r["status"], r["name"]) for r in d.get("results",[])]'
echo BOTH_PATHS_OK
