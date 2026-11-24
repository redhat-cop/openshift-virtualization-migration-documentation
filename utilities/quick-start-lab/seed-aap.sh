#!/usr/bin/env bash
# Seed Migration Factory into AAP from the bastion workdir.
# Expects lab.env + inventory already prepared (see bootstrap.sh).
set -euo pipefail

WORKDIR="${BASTION_WORKDIR:-/root/migration-factory-lab}"
COL_DIR="${COLLECTION_DIR:-/root/openshift_virtualization_migration}"
EE_IMAGE="${EE_IMAGE:-quay.io/redhat-cop/openshift-virtualization-migration-ee:latest}"
SCM_URL="${AAP_PROJECT_SCM_URL:-https://github.com/redhat-cop/openshift_virtualization_migration.git}"
SCM_BRANCH="${AAP_PROJECT_SCM_BRANCH:-v2}"

cd "${WORKDIR}"
# shellcheck disable=SC1091
set -a
source ./lab.env
set +a

export PATH="/usr/local/bin:/root/bin:${PATH}"

mint_aap_gateway_token() {
  python3 - <<'PY'
import os, json, urllib.request, ssl, base64
ctx = ssl._create_unverified_context()
base = os.environ["AAP_URL"].rstrip("/")
auth = base64.b64encode(f"{os.environ['AAP_USER']}:{os.environ['AAP_PASSWORD']}".encode()).decode()
req = urllib.request.Request(
    base + "/api/gateway/v1/tokens/",
    data=json.dumps({"description": "mf-seed", "application": None, "scope": "write"}).encode(),
    method="POST",
)
req.add_header("Authorization", "Basic " + auth)
req.add_header("Content-Type", "application/json")
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    tok = json.loads(r.read().decode())["token"]
open("aap.token", "w").write(tok)
print("Minted AAP gateway token → aap.token")
PY
  chmod 600 aap.token
}

echo "==> Ensure collection checkout ${SCM_BRANCH}"
if [[ ! -d "${COL_DIR}/.git" ]]; then
  git clone --branch "${SCM_BRANCH}" --depth 1 "${SCM_URL}" "${COL_DIR}"
else
  git -C "${COL_DIR}" fetch --depth 1 origin "${SCM_BRANCH}" || true
  git -C "${COL_DIR}" checkout "${SCM_BRANCH}" || true
fi

echo "==> Mint AAP gateway token (AAP 2.5+ — /api/v2/tokens is 404)"
mint_aap_gateway_token
AAP_TOKEN="$(cat aap.token)"
export AAP_TOKEN

echo "==> Refresh OpenShift token + render inventory (token auth)"
oc login -u "${OCP_USER}" -p "${OCP_PASSWORD}" "${OCP_API}" --insecure-skip-tls-verify=true >/dev/null
OCP_TOKEN="$(oc whoami -t)"
export OCP_TOKEN
grep -vE '^(OCP_TOKEN|AAP_TOKEN)=' lab.env > lab.env.tmp || true
{
  echo "OCP_TOKEN=${OCP_TOKEN}"
  echo "AAP_TOKEN=${AAP_TOKEN}"
} >> lab.env.tmp
mv lab.env.tmp lab.env
chmod 600 lab.env
set -a
source ./lab.env
set +a
./render-inventory.sh ./inventory.yml
cp -a ./inventory.yml "${COL_DIR}/inventory.lab.yml"
chmod 600 "${COL_DIR}/inventory.lab.yml"

if [[ -n "${QUAY_USER:-}" && -n "${QUAY_PASSWORD:-}" ]]; then
  echo "${QUAY_PASSWORD}" | podman login quay.io -u "${QUAY_USER}" --password-stdin >/dev/null
fi

echo "==> Seed AAP (mount v2 collection over EE — EE:latest may ship older playbooks)"
LOG="${WORKDIR}/seed-aap.log"
cd "${COL_DIR}"
ansible-navigator run \
  playbooks/vmf_seed_aap.yml \
  -i inventory.lab.yml \
  --pp=missing \
  --eei="${EE_IMAGE}" \
  -m stdout \
  --pae=false \
  --eev "${COL_DIR}:/usr/share/ansible/collections/ansible_collections/infra/openshift_virtualization_migration:Z" \
  2>&1 | tee "${LOG}"

echo "==> Verify Migration Factory templates"
curl -sk -H "Authorization: Bearer ${AAP_TOKEN}" \
  "${AAP_URL%/}/api/controller/v2/job_templates/?page_size=200" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);names=[r["name"] for r in d.get("results",[]) if "Virtualization Migration" in r.get("name","")];
print("\n".join(f"- {n}" for n in names) or "NONE");
raise SystemExit(0 if names else 1)'

echo "Seed complete. Log: ${LOG}"
