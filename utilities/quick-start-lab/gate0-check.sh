#!/usr/bin/env bash
# Gate 0 checker aligned with v2/modules/appendix/pages/quick-start.adoc
# Does not seed AAP or start MTV plans.
set -euo pipefail

INVENTORY="${1:-}"
SKIP_PODMAN_EE="${SKIP_PODMAN_EE:-0}"
EE_IMAGE="${EE_IMAGE:-quay.io/redhat-cop/openshift-virtualization-migration-ee:latest}"
AAP_API_PREFIX="${AAP_API_PREFIX:-/api/controller/v2}"
failures=0

check_aap() {
  local url="$1"
  if curl -kI --connect-timeout 10 "${url%/}/" >/dev/null 2>&1; then
    pass "AAP HTTPS responds at ${url}"
  else
    fail "AAP HTTPS did not respond at ${url}"
    return
  fi
  if [[ -n "${AAP_USER:-}" && -n "${AAP_PASSWORD:-}" ]]; then
    if curl -sk -u "${AAP_USER}:${AAP_PASSWORD}" --connect-timeout 10 "${url%/}${AAP_API_PREFIX}/ping/" | grep -q '"version"'; then
      pass "AAP controller ping ${AAP_API_PREFIX}/ping/"
    else
      fail "AAP controller ping failed (${AAP_API_PREFIX}/ping/) — check user/password or API prefix"
    fi
  else
    info "Set AAP_USER/AAP_PASSWORD to verify ${AAP_API_PREFIX}/ping/"
  fi
}

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }
info() { printf 'INFO  %s\n' "$*"; }

echo "=== Gate 0 — platform ==="

api_ok=0
if ! command -v oc >/dev/null 2>&1; then
  fail "oc not found on PATH"
else
  server="$(oc whoami --show-server 2>/dev/null || true)"
  if [[ -n "${server}" ]]; then
    info "kubeconfig server: ${server}"
  else
    fail "oc whoami --show-server failed"
  fi
  if oc --request-timeout=8s whoami >/dev/null 2>&1; then
    pass "oc whoami: $(oc --request-timeout=8s whoami 2>/dev/null)"
    api_ok=1
  else
    fail "oc cannot authenticate to the API — fix login/context (stale workshop kubeconfig is a common cause)"
  fi
fi

if [[ "${api_ok}" -eq 1 ]]; then
  # Buffer oc output — avoid pipefail+grep -q SIGPIPE false negatives
  csvs="$(oc --request-timeout=30s get csv -A 2>/dev/null || true)"
  apis="$(oc --request-timeout=30s api-resources 2>/dev/null || true)"
  if [[ -z "${csvs}" ]]; then
    fail "Cannot list CSVs — API unreachable or unauthorized"
  else
    if grep -qiE 'kubevirt|hyperconverged|openshift-virtualization|virtualization' <<<"${csvs}"; then
      pass "OpenShift Virtualization-related CSV present"
      grep -iE 'kubevirt|hyperconverged|openshift-virtualization|virtualization' <<<"${csvs}" | head -5 | sed 's/^/      /'
    else
      fail "No Virtualization/KubeVirt CSV matched grep"
    fi
    if grep -qiE 'mtv|forklift|migration-toolkit' <<<"${csvs}"; then
      pass "MTV/Forklift-related CSV present"
      grep -iE 'mtv|forklift|migration-toolkit' <<<"${csvs}" | head -5 | sed 's/^/      /'
    else
      fail "No MTV/Forklift CSV matched grep"
    fi
  fi
  if grep -qi kubevirt <<<"${apis}"; then
    pass "KubeVirt API resources present"
  else
    fail "No kubevirt API resources"
  fi

  forklift="$(oc get forkliftcontrollers.forklift.konveyor.io -A 2>/dev/null || true)"
  if [[ -n "$(echo "${forklift}" | awk 'NR>1{print; exit}')" ]]; then
    pass "Forklift controller found"
    echo "${forklift}" | sed 's/^/      /'
  else
    fail "Cannot get forkliftcontrollers.forklift.konveyor.io (or none present)"
  fi
else
  fail "Skipping Virtualization/MTV checks until oc API works"
fi

info "Confirm *Migration* appears in the OpenShift console (manual)"

if [[ -n "${INVENTORY}" && -f "${INVENTORY}" ]]; then
  aap_host="$(grep -E '^\s*aap_hostname:' "${INVENTORY}" | head -1 | awk '{print $2}' | tr -d '"'"'" || true)"
  if [[ -n "${aap_host}" && "${aap_host}" != "changeme" ]]; then
    check_aap "${aap_host}"
  elif [[ -n "${AAP_URL:-}" ]]; then
    check_aap "${AAP_URL}"
  else
    fail "AAP URL unknown (inventory aap_hostname or AAP_URL)"
  fi
elif [[ -n "${AAP_URL:-}" ]]; then
  check_aap "${AAP_URL}"
else
  info "Skipping AAP curl (pass inventory path or set AAP_URL)"
  fail "AAP reachability not checked"
fi

if [[ "${SKIP_PODMAN_EE}" == "1" ]]; then
  info "SKIP_PODMAN_EE=1 — prove EE pull via AAP registry credential (manual)"
  pass "EE local Podman check skipped by request"
else
  if ! command -v podman >/dev/null 2>&1; then
    fail "podman not found (set SKIP_PODMAN_EE=1 if you only use AAP)"
  else
    if podman pull "${EE_IMAGE}" >/dev/null 2>&1; then
      pass "podman pull ${EE_IMAGE}"
    else
      fail "podman pull failed for ${EE_IMAGE} (start podman machine, or SKIP_PODMAN_EE=1 and use AAP)"
    fi
  fi
fi

if [[ -n "${INVENTORY}" ]]; then
  echo
  echo "=== Gate 0 — inventory ==="
  if [[ ! -f "${INVENTORY}" ]]; then
    fail "Inventory file not found: ${INVENTORY}"
  else
    if grep -n 'changeme' "${INVENTORY}" >/dev/null 2>&1; then
      fail "Inventory still contains 'changeme' placeholders"
      grep -n 'changeme' "${INVENTORY}" | head -20 | sed 's/^/      /'
    else
      pass "No 'changeme' placeholders in ${INVENTORY}"
    fi
    missing_groups=0
    for g in migration_aap migration_clusters vm_sources; do
      if grep -E "^[[:space:]]*${g}:" "${INVENTORY}" >/dev/null 2>&1; then
        pass "Group present: ${g}"
      else
        fail "Missing group: ${g}"
        missing_groups=1
      fi
    done
    if [[ "${missing_groups}" -eq 0 ]]; then
      info "Confirm by eye that each cluster vm_sources list matches vm_sources host names"
    fi
  fi
else
  echo
  info "No inventory path given — platform checks only (expected before Building your inventory)"
fi

echo
if [[ "${failures}" -eq 0 ]]; then
  echo "Gate 0 result: ALL CHECKS PASSED"
  exit 0
fi
echo "Gate 0 result: ${failures} CHECK(S) FAILED — stop, fix, re-run"
exit 1
