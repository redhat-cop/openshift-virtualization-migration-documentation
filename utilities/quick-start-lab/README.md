# Quick Start lab helpers (bastion + Gate 0 + seed)

Accelerate the appendix Quick Start on a **BYO lab reached through an SSH bastion**. Helpers do **not** replace the run sheet and do **not** auto-migrate VMs.

## Proven path

| Piece | Result |
| --- | --- |
| Bastion | SSH → OCP / AAP / ESXi |
| Gate 0 | PASS |
| Standalone ESXi | MTV provider Ready (`sdkEndpoint: esxi`) |
| Quay EE | Pull credentials are required and are not published in this documentation |
| Seed | PASS — MF templates created (Provider, Maps, Plans, Migrate, …) |
| AAP auth | Gateway token via `POST /api/gateway/v1/tokens/` |
| Seed playbook | Mount **v2** git checkout into EE (`vmf_seed_aap.yml`) |

Secrets live in `lab.env` (gitignored). Commit only `lab.env.example`.

## Files

| File | Purpose |
| --- | --- |
| `lab.env.example` | Variable template |
| `bootstrap.sh` | Mac → bastion: sync, `oc login`, Gate 0, inventory |
| `seed-aap.sh` | Bastion: mint gateway token, render inventory, seed AAP |
| `gate0-check.sh` | Platform (+ optional inventory) Gate 0 |
| `render-inventory.sh` | Build `inventory.yml` (prefers `AAP_TOKEN`) |

## Usage

```bash
cp utilities/quick-start-lab/lab.env.example utilities/quick-start-lab/lab.env
# edit lab.env — set QUAY_* ; pull credentials are required and are not published in this documentation

chmod +x utilities/quick-start-lab/*.sh

# Gate 0 + inventory only
./utilities/quick-start-lab/bootstrap.sh

# Gate 0 + inventory + seed
SEED_AAP=1 ./utilities/quick-start-lab/bootstrap.sh
```

On the bastion:

```bash
cd /root/migration-factory-lab
./seed-aap.sh
```

## Seed notes (doc friction)

1. **AAP 2.5+:** username/password seed often fails with `Failed to get token` / 404. Mint `aap_token` from `/api/gateway/v1/tokens/`.
2. **EE:latest** may ship collection **1.21.x** without `vmf_seed_aap`. Mount the v2 repo over the collection path (see `seed-aap.sh`).
3. **Quay** pull credentials are required for EE pull and are not published in this documentation.

## Next after seed

**Consultant path (Quick Start):** AAP *Templates* — Provider → Maps → Plans → console **Start**.

**Verified in lab:**

| Path | How | Example |
| --- | --- | --- |
| AAP JTs | Provider / Maps / Plans (+ optional Migrate) then Start | `rhel-92` → `verify-aap-cold-01` |
| ansible-navigator | Mount v2 collection into EE; `vmf_mtv_plans.yml` then Migration CR | `rhel-10` → `verify-nav-cold-01` |

Helpers: `aap-maps-plans-migrate.sh`, `dual-migrate-verify.sh`, `build-v2-lab-ee.sh` (when `EE:latest` lacks v2 `mtv_*` roles). Never commit `lab.env`.
