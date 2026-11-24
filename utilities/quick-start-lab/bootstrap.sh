#!/usr/bin/env bash
# Bootstrap BYO lab via SSH bastion → Gate 0 → inventory.
# Optional: SEED_AAP=1 also runs seed-aap.sh on the bastion.
# Does NOT start MTV migrations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${LAB_ENV_FILE:-${ROOT_DIR}/lab.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy lab.env.example → lab.env and fill values." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

: "${BASTION_HOST:?}"
: "${BASTION_USER:?}"
: "${BASTION_SSH_KEY:?}"
: "${OCP_API:?}"
: "${AAP_URL:?}"
: "${VMWARE_HOST:?}"

BASTION_SSH_PORT="${BASTION_SSH_PORT:-22}"
BASTION_WORKDIR="${BASTION_WORKDIR:-/root/migration-factory-lab}"
SKIP_PODMAN_EE="${SKIP_PODMAN_EE:-1}"
AAP_API_PREFIX="${AAP_API_PREFIX:-/api/controller/v2}"
SEED_AAP="${SEED_AAP:-0}"

SSH=(ssh -i "${BASTION_SSH_KEY}" -p "${BASTION_SSH_PORT}" -o StrictHostKeyChecking=accept-new "${BASTION_USER}@${BASTION_HOST}")
SCP=(scp -i "${BASTION_SSH_KEY}" -P "${BASTION_SSH_PORT}" -o StrictHostKeyChecking=accept-new)

echo "==> Sync helpers to bastion ${BASTION_USER}@${BASTION_HOST}:${BASTION_WORKDIR}"
"${SSH[@]}" "mkdir -p '${BASTION_WORKDIR}' && chmod 700 '${BASTION_WORKDIR}'"
"${SCP[@]}" \
  "${ROOT_DIR}/gate0-check.sh" \
  "${ROOT_DIR}/render-inventory.sh" \
  "${ROOT_DIR}/seed-aap.sh" \
  "${ROOT_DIR}/lab.env" \
  "${BASTION_USER}@${BASTION_HOST}:${BASTION_WORKDIR}/"
"${SSH[@]}" "chmod 700 '${BASTION_WORKDIR}' && chmod 600 '${BASTION_WORKDIR}/lab.env' && chmod 755 '${BASTION_WORKDIR}/'*.sh"

echo "==> Login to OpenShift + Gate 0 + render inventory on bastion"
"${SSH[@]}" bash -s <<REMOTE
set -euo pipefail
export PATH="/usr/local/bin:/root/bin:\$PATH"
cd '${BASTION_WORKDIR}'
set -a
source ./lab.env
set +a

OC_BIN=\$(command -v oc || true)
if [[ -z "\${OC_BIN}" ]]; then
  echo "oc not found on bastion PATH" >&2
  exit 1
fi

INSECURE_FLAG=()
if [[ "\${OCP_INSECURE:-true}" == "true" ]]; then
  INSECURE_FLAG+=(--insecure-skip-tls-verify=true)
fi

echo '--- oc login ---'
\${OC_BIN} login -u "\${OCP_USER}" -p "\${OCP_PASSWORD}" "\${OCP_API}" "\${INSECURE_FLAG[@]}"
export OCP_TOKEN=\$(\${OC_BIN} whoami -t)

# Mint AAP gateway token when possible (AAP 2.5+)
if [[ -n "\${AAP_USER:-}" && -n "\${AAP_PASSWORD:-}" ]]; then
  python3 - <<'PY'
import os, json, urllib.request, ssl, base64
ctx=ssl._create_unverified_context()
base=os.environ["AAP_URL"].rstrip("/")
auth=base64.b64encode(f"{os.environ['AAP_USER']}:{os.environ['AAP_PASSWORD']}".encode()).decode()
req=urllib.request.Request(base+"/api/gateway/v1/tokens/", data=json.dumps({"description":"mf-bootstrap","application":None,"scope":"write"}).encode(), method="POST")
req.add_header("Authorization","Basic "+auth)
req.add_header("Content-Type","application/json")
with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
    open("aap.token","w").write(json.loads(r.read().decode())["token"])
print("Minted AAP gateway token")
PY
  chmod 600 aap.token
  export AAP_TOKEN=\$(cat aap.token)
fi

grep -vE '^(OCP_TOKEN|AAP_TOKEN)=' lab.env > lab.env.tmp || true
echo "OCP_TOKEN=\${OCP_TOKEN}" >> lab.env.tmp
if [[ -n "\${AAP_TOKEN:-}" ]]; then
  echo "AAP_TOKEN=\${AAP_TOKEN}" >> lab.env.tmp
fi
mv lab.env.tmp lab.env
chmod 600 lab.env

echo '--- Gate 0 ---'
export AAP_URL SKIP_PODMAN_EE EE_IMAGE AAP_USER AAP_PASSWORD AAP_API_PREFIX
if curl -sk -u "\${AAP_USER}:\${AAP_PASSWORD}" --connect-timeout 10 "\${AAP_URL%/}\${AAP_API_PREFIX}/ping/" | grep -q version; then
  echo "PASS  AAP controller ping via \${AAP_API_PREFIX}/ping/"
else
  echo "FAIL  AAP controller ping" >&2
fi

SKIP_PODMAN_EE=\${SKIP_PODMAN_EE} AAP_URL=\${AAP_URL} AAP_USER=\${AAP_USER} AAP_PASSWORD=\${AAP_PASSWORD} ./gate0-check.sh || true

echo '--- render inventory ---'
set -a
source ./lab.env
set +a
./render-inventory.sh ./inventory.yml

echo '--- inventory Gate 0 ---'
./gate0-check.sh ./inventory.yml || true

echo '--- AAP seeded? ---'
auth_hdr=()
if [[ -n "\${AAP_TOKEN:-}" ]]; then
  auth_hdr=(-H "Authorization: Bearer \${AAP_TOKEN}")
else
  auth_hdr=(-u "\${AAP_USER}:\${AAP_PASSWORD}")
fi
count=\$(curl -sk "\${auth_hdr[@]}" "\${AAP_URL%/}\${AAP_API_PREFIX}/job_templates/?page_size=200" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(sum(1 for r in d.get("results",[]) if "Migration" in r.get("name","") or "MTV" in r.get("name","")))' 2>/dev/null || echo 0)
echo "Migration/MTV job templates found: \${count}"

echo '--- ESXi / MTV providers ---'
\${OC_BIN} get providers.forklift.konveyor.io -n openshift-mtv 2>/dev/null || true

cat > wave-request.example.yml <<EOF
mtv_plans_migration_request:
  source: esxi-lab
  destination: host
  target_namespace: \${TARGET_NAMESPACE}
  network_map: esxi-lab-host
  storage_map: esxi-lab-host
  verify_plans_ready: true
  plan_name: \${PLAN_NAME}
  vms:
    - name: \${COLD_VM_NAME}
EOF

echo
echo "Bastion workdir: ${BASTION_WORKDIR}"
echo "Artifacts: lab.env inventory.yml wave-request.example.yml"
REMOTE

if [[ "${SEED_AAP}" == "1" ]]; then
  echo "==> SEED_AAP=1 — running seed-aap.sh on bastion"
  "${SSH[@]}" "cd '${BASTION_WORKDIR}' && ./seed-aap.sh"
else
  echo "==> Bootstrap finished (inventory ready)."
  echo "    To seed: SEED_AAP=1 ./utilities/quick-start-lab/bootstrap.sh"
  echo "    Or on bastion: cd ${BASTION_WORKDIR} && ./seed-aap.sh"
fi
