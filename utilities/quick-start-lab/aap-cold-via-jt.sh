#!/bin/bash
# Launch MTV Provider → Maps → Plans via AAP job templates, then start Migration CR.
# Run on bastion with lab.env + inventory.yml present. Does not commit secrets.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
set -a; source ./lab.env; set +a
export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
export PATH="/usr/local/bin:/root/bin:$PATH"

API="${AAP_URL}${AAP_API_PREFIX:-/api/controller/v2}"
VDDK_IMG="${VDDK_IMAGE:-quay.io/redhat-cop/openshift-virtualization-migration-vddk:latest}"
PLAN_NAME="${PLAN_NAME:-quickstart-aap-cold-01}"
VM_NAME="${COLD_VM_NAME:-rhel-92}"
INV_SOURCE_HOST="${INV_SOURCE_HOST:-esxi-lab}"
INV_CLUSTER_HOST="${INV_CLUSTER_HOST:-ocp-lab}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-vm-workloads}"
export API PLAN_NAME VM_NAME VDDK_IMAGE="$VDDK_IMG" INV_SOURCE_HOST INV_CLUSTER_HOST TARGET_NAMESPACE

mint_tok() {
  curl -sk -u "$AAP_USER:$AAP_PASSWORD" -H "Content-Type: application/json" \
    -d '{"description":"aap-cold","scope":"write","application":null}' \
    "${AAP_URL}/api/gateway/v1/tokens/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])'
}
TOK=$(mint_tok)
echo "$TOK" > /tmp/aap.tok
export TOK
auth() { curl -sk -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" "$@"; }

echo "== Refresh OCP token =="
oc login -u "$OCP_USER" -p "$OCP_PASSWORD" "$OCP_API" --insecure-skip-tls-verify=true >/dev/null
OCP_TOKEN=$(oc whoami -t)
export OCP_TOKEN

python3 <<'PY'
import os, re, pathlib
p = pathlib.Path("inventory.yml")
text = p.read_text()
token = os.environ["OCP_TOKEN"]
text = re.sub(r"(openshift_api_key:\s*).*", r"\1" + token, text, count=1)
vddk_img = os.environ["VDDK_IMAGE"]
quay_u = os.environ.get("QUAY_USER", "")
quay_p = os.environ.get("QUAY_PASSWORD", "")
parts = text.split("migration_clusters:", 1)
head, tail = parts[0], ("migration_clusters:" + parts[1] if len(parts) > 1 else "")
head = re.sub(r"(?m)^\s{6}vddk:[\s\S]*?(?=^\S|\Z)", "", head)
block = f"      vddk:\n        image: {vddk_img}\n"
if quay_u and quay_p:
    block += f"        username: {quay_u}\n        password: {quay_p}\n"
if "vddk:" not in head:
    head = head.replace("      validate_certs: false\n", "      validate_certs: false\n" + block, 1)
p.write_text(head + tail)
print("inventory.yml updated")
PY

echo "== Sync host variables into AAP =="
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

def upsert(name, group_key):
    vars_dict = inv[group_key]["hosts"][name]
    hid = hosts[name]["id"]
    req("PATCH", f"{api}/hosts/{hid}/", {"variables": yaml.safe_dump(vars_dict, default_flow_style=False)})
    print(f"patched host {name} id={hid}")

upsert(os.environ["INV_SOURCE_HOST"], "vm_sources")
upsert(os.environ["INV_CLUSTER_HOST"], "migration_clusters")
PY

echo "== Power off $VM_NAME on ESXi =="
python3 <<'PY'
import ssl, urllib.request, re, http.cookiejar, os, time
ctx = ssl._create_unverified_context()
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(
    urllib.request.HTTPSHandler(context=ctx),
    urllib.request.HTTPCookieProcessor(cj),
)
host = os.environ["VMWARE_HOST"]
user = os.environ["VMWARE_USER"]
pw = os.environ["VMWARE_PASSWORD"]
vm_name = os.environ["VM_NAME"]

def soap(body: str) -> str:
    req = urllib.request.Request(f"https://{host}/sdk", data=body.encode(), method="POST")
    req.add_header("Content-Type", "text/xml; charset=utf-8")
    req.add_header("SOAPAction", "urn:vim25/8.0.0.1")
    with opener.open(req, timeout=30) as r:
        return r.read().decode()

login = (
    '<?xml version="1.0"?>'
    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:vim25="urn:vim25">'
    "<soapenv:Body><vim25:Login>"
    '<vim25:_this type="SessionManager">ha-sessionmgr</vim25:_this>'
    f"<vim25:userName>{user}</vim25:userName><vim25:password>{pw}</vim25:password>"
    "</vim25:Login></soapenv:Body></soapenv:Envelope>"
)
soap(login)
retrieve = (
    '<?xml version="1.0"?>'
    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:vim25="urn:vim25">'
    "<soapenv:Body><vim25:RetrievePropertiesEx>"
    '<vim25:_this type="PropertyCollector">ha-property-collector</vim25:_this>'
    "<vim25:specSet><vim25:propSet>"
    "<vim25:type>VirtualMachine</vim25:type><vim25:all>false</vim25:all>"
    "<vim25:pathSet>name</vim25:pathSet><vim25:pathSet>runtime.powerState</vim25:pathSet>"
    "</vim25:propSet><vim25:objectSet>"
    '<vim25:obj type="Folder">ha-folder-root</vim25:obj><vim25:skip>false</vim25:skip>'
    '<vim25:selectSet xsi:type="TraversalSpec" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    "<vim25:name>folderTraversal</vim25:name><vim25:type>Folder</vim25:type>"
    "<vim25:path>childEntity</vim25:path><vim25:skip>false</vim25:skip>"
    '<vim25:selectSet xsi:type="SelectionSpec"><vim25:name>folderTraversal</vim25:name></vim25:selectSet>'
    '<vim25:selectSet xsi:type="SelectionSpec"><vim25:name>dcToVmFolder</vim25:name></vim25:selectSet>'
    "</vim25:selectSet>"
    '<vim25:selectSet xsi:type="TraversalSpec" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    "<vim25:name>dcToVmFolder</vim25:name><vim25:type>Datacenter</vim25:type>"
    "<vim25:path>vmFolder</vim25:path><vim25:skip>false</vim25:skip>"
    '<vim25:selectSet xsi:type="SelectionSpec"><vim25:name>folderTraversal</vim25:name></vim25:selectSet>'
    "</vim25:selectSet></vim25:objectSet></vim25:specSet><vim25:options></vim25:options>"
    "</vim25:RetrievePropertiesEx></soapenv:Body></soapenv:Envelope>"
)
resp = soap(retrieve)
for o in re.findall(r"<objects>(.*?)</objects>", resp, re.S):
    typ = re.search(r'<obj type="([^"]+)">([^<]+)</obj>', o)
    if not typ or typ.group(1) != "VirtualMachine":
        continue
    name = re.search(r"<name>name</name><val[^>]*>([^<]*)</val>", o)
    pwr = re.search(r"<name>runtime.powerState</name><val[^>]*>([^<]*)</val>", o)
    if not name:
        continue
    print(name.group(1), pwr.group(1) if pwr else "?")
    if name.group(1) != vm_name:
        continue
    if pwr and pwr.group(1) == "poweredOn":
        poweroff = (
            '<?xml version="1.0"?>'
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:vim25="urn:vim25">'
            "<soapenv:Body><vim25:PowerOffVM_Task>"
            f'<vim25:_this type="VirtualMachine">{typ.group(2)}</vim25:_this>'
            "</vim25:PowerOffVM_Task></soapenv:Body></soapenv:Envelope>"
        )
        soap(poweroff)
        time.sleep(8)
        print("powered_off")
    else:
        print("already_off_or_unknown")
PY

launch_and_wait() {
  local jt_id="$1"
  local label="$2"
  local extra_json="$3"
  echo "== Launch JT $jt_id ($label) =="
  local resp job_id st
  # Attach Migration Factory source + target credentials (ask_credential_on_launch)
  resp=$(auth -X POST "$API/job_templates/${jt_id}/launch/" \
    -d "{\"extra_vars\":${extra_json},\"credentials\":[3,4]}")
  echo "$resp" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("job", d.get("id"), "status", d.get("status"), "msg", d.get("msg") or d.get("detail") or "")'
  job_id=$(echo "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
  for i in $(seq 1 90); do
    st=$(auth "$API/jobs/${job_id}/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
    echo "[$i] $label job=$job_id status=$st"
    case "$st" in
      successful) echo "OK $label"; return 0 ;;
      failed|error|canceled)
        echo "FAIL $label"
        auth "$API/jobs/${job_id}/stdout/?format=txt" | tail -120
        return 1
        ;;
    esac
    sleep 10
  done
  echo "TIMEOUT $label"; return 1
}

resolve_jt() {
  JT_NAME="$1" auth "$API/job_templates/?page_size=50" | python3 -c 'import sys,json,os
name=os.environ["JT_NAME"]
for r in json.load(sys.stdin).get("results",[]):
  if r.get("name")==name:
    print(r["id"]); raise SystemExit
raise SystemExit("missing "+name)'
}
JT_PROVIDER=$(resolve_jt "OpenShift Virtualization Migration - MTV Provider")
JT_MAPS=$(resolve_jt "OpenShift Virtualization Migration - MTV Maps")
JT_PLANS=$(resolve_jt "OpenShift Virtualization Migration - MTV Plans")
JT_MIGRATE=$(resolve_jt "OpenShift Virtualization Migration - MTV Migrate")
echo "JTs provider=$JT_PROVIDER maps=$JT_MAPS plans=$JT_PLANS migrate=$JT_MIGRATE"

echo "== Ensure VDDK pull secret =="
oc delete secret esxi-lab-vddk -n openshift-mtv --ignore-not-found
oc create secret docker-registry esxi-lab-vddk \
  --docker-server=quay.io \
  --docker-username="$QUAY_USER" \
  --docker-password="$QUAY_PASSWORD" \
  -n openshift-mtv
oc delete secret esxi-lab-vddk -n "$TARGET_NAMESPACE" --ignore-not-found
oc create secret docker-registry esxi-lab-vddk \
  --docker-server=quay.io \
  --docker-username="$QUAY_USER" \
  --docker-password="$QUAY_PASSWORD" \
  -n "$TARGET_NAMESPACE"
oc secrets link default esxi-lab-vddk --for=pull -n "$TARGET_NAMESPACE" 2>/dev/null || true

PROVIDER_EXTRA=$(python3 - <<'PY'
import json, os
print(json.dumps({
  "source_name": os.environ["INV_SOURCE_HOST"],
  "target_name": os.environ["INV_CLUSTER_HOST"],
  "mtv_provider_provider_override": {
    "settings": {
      "sdkEndpoint": os.environ.get("VMWARE_SDK_ENDPOINT_TYPE", "esxi"),
      "vddkInitImage": os.environ["VDDK_IMAGE"],
    }
  }
}))
PY
)
MAPS_EXTRA=$(python3 - <<'PY'
import json, os
print(json.dumps({
  "source_name": os.environ["INV_SOURCE_HOST"],
  "target_name": os.environ["INV_CLUSTER_HOST"],
}))
PY
)
PLANS_EXTRA=$(python3 - <<'PY'
import json, os
print(json.dumps({
  "source_name": os.environ["INV_SOURCE_HOST"],
  "target_name": os.environ["INV_CLUSTER_HOST"],
  "mtv_plans_migration_request": {
    "source": os.environ["INV_SOURCE_HOST"],
    "destination": "host",
    "target_namespace": os.environ["TARGET_NAMESPACE"],
    "network_map": f"{os.environ['INV_SOURCE_HOST']}-host",
    "storage_map": f"{os.environ['INV_SOURCE_HOST']}-host",
    "verify_plans_ready": True,
    "plan_name": os.environ["PLAN_NAME"],
    "type": "cold",
    "preserveStaticIPs": False,
    "vms": [{"name": os.environ["VM_NAME"]}],
  }
}))
PY
)
MIGRATE_EXTRA="$MAPS_EXTRA"

launch_and_wait "$JT_PROVIDER" "MTV-Provider" "$PROVIDER_EXTRA"
launch_and_wait "$JT_MAPS" "MTV-Maps" "$MAPS_EXTRA"
launch_and_wait "$JT_PLANS" "MTV-Plans" "$PLANS_EXTRA"

echo "== Start migration (OpenShift console Start ≡ Migration CR; AAP Migrate JT does not copy disks) =="
oc delete migration "$PLAN_NAME" -n openshift-mtv --ignore-not-found
cat <<EOF | oc apply -f -
apiVersion: forklift.konveyor.io/v1beta1
kind: Migration
metadata:
  name: ${PLAN_NAME}
  namespace: openshift-mtv
  labels:
    app.kubernetes.io/part-of: quickstart-aap
spec:
  plan:
    name: ${PLAN_NAME}
    namespace: openshift-mtv
EOF

set +e
launch_and_wait "$JT_MIGRATE" "MTV-Migrate-noop" "$MIGRATE_EXTRA"
set -e

echo "== Poll plan until Succeeded =="
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
    oc get plan "$PLAN_NAME" -n openshift-mtv -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
    exit 1
  fi
  sleep 20
done
echo "$cond" | grep -qE '(^|;)Succeeded=True' || { echo TIMEOUT; exit 2; }

echo "== AAP recent jobs =="
auth "$API/jobs/?order_by=-id&page_size=15" | python3 -c 'import sys,json; d=json.load(sys.stdin);
[print(r["id"], r["status"], r["name"]) for r in d.get("results",[])]'

oc get plan,migration "$PLAN_NAME" -n openshift-mtv -o wide
oc get vm -n "$TARGET_NAMESPACE" -o wide
echo DONE
