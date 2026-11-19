#!/bin/bash
# Build EE:latest + v2 collection checkout, push to Quay, point AAP EE at the tag.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
set -a; source ./lab.env; set +a

EE_BASE="${EE_IMAGE:-quay.io/redhat-cop/openshift-virtualization-migration-ee:latest}"
EE_LAB="${EE_LAB_IMAGE:-quay.io/redhat-cop/openshift-virtualization-migration-ee:v2-lab-shebi}"
COL="${COLLECTION_PATH:-/root/openshift_virtualization_migration}"
API="${AAP_URL}${AAP_API_PREFIX:-/api/controller/v2}"

echo "$QUAY_PASSWORD" | podman login quay.io -u "$QUAY_USER" --password-stdin

podman rm -f ee-v2-build 2>/dev/null || true
podman create --name ee-v2-build "$EE_BASE" sleep 1
podman cp "${COL}/." "ee-v2-build:/usr/share/ansible/collections/ansible_collections/infra/openshift_virtualization_migration/"
podman commit ee-v2-build "$EE_LAB"
podman rm -f ee-v2-build

podman run --rm "$EE_LAB" \
  ls /usr/share/ansible/collections/ansible_collections/infra/openshift_virtualization_migration/roles \
  | grep -E 'mtv_provider|mtv_maps|mtv_plans'

echo "Pushing ${EE_LAB} ..."
podman push "$EE_LAB"

TOK=$(curl -sk -u "$AAP_USER:$AAP_PASSWORD" -H "Content-Type: application/json" \
  -d '{"description":"ee-lab","scope":"write","application":null}' \
  "${AAP_URL}/api/gateway/v1/tokens/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')
echo "$TOK" > /tmp/aap.tok

curl -sk -H "Authorization: Bearer ${TOK}" -H "Content-Type: application/json" \
  -X PATCH "${API}/execution_environments/4/" \
  -d "{\"image\":\"${EE_LAB}\",\"pull\":\"always\",\"credential\":5}" \
  | python3 -c 'import sys,json; r=json.load(sys.stdin); print("ee", r["id"], r["image"], "cred", r.get("credential"), "pull", r.get("pull"))'

echo EE_READY
