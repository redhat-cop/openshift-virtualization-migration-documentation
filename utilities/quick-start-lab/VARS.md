# Minimal variables (mapped from lab access)

| Env var | Shebi example | Used for |
| --- | --- | --- |
| `BASTION_HOST` / `BASTION_USER` / `BASTION_SSH_KEY` | `23.88.73.30` / `root` / `~/.ssh/id_rsa_open` | SSH jump |
| `OCP_API` / `OCP_USER` / `OCP_PASSWORD` | `https://api.ocp4.shebi.eu:6443` / `kubeadmin` | Destination login |
| `OCP_TOKEN` | minted by bootstrap via `oc whoami -t` | Inventory `openshift_api_key` |
| `AAP_URL` / `AAP_USER` / `AAP_PASSWORD` | `https://shebi-aap.apps.ocp4.shebi.eu` / `admin` | Controller + Gate 0 |
| `AAP_API_PREFIX` | `/api/controller/v2` | AAP 2.5+ REST |
| `VMWARE_SDK_ENDPOINT_TYPE` | `esxi` | MTV `settings.sdkEndpoint` |
| `VMWARE_HOST` / user / password | `192.168.50.145` / `root` | Source provider |
| `VDDK_IMAGE` | customer-built registry image | Provider `vddkInitImage` (required on ESXi cold) |
| `COLD_VM_NAME` | `rhel-10` | First cold plan |
| `TARGET_NAMESPACE` | `vm-workloads` | Migrated VMs project |
| `EE_IMAGE` / `QUAY_*` | quay.io/redhat-cop/... | Seed EE pull |

## VMs discovered on ESXi

| Name | Power | Guest (ESXi) | Notes |
| --- | --- | --- | --- |
| `rhel-10` | poweredOff | RHEL 9 (reported) | Good first cold candidate |
| `rhel-92` | poweredOn | RHEL 9 / IP 192.168.50.206 | Path A if you power off |
| `win11` | poweredOn | Windows 11 | Path B after first RHEL sitting |
