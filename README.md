# AAP use cases: self-service storage and event-driven incident enrichment

Working examples for **Ansible Automation Platform 2.6**, covering controller, Event-Driven Ansible (EDA) and the platform gateway.

| # | Use case | What it shows |
|---|----------|---------------|
| 1 | **Self-service directory and mount point management** (RHEL and AIX) | Survey → guardrail validation → approval → idempotent creation → summary report |
| 2 | **Storage utilization reporting and incident enrichment** (AIX and RHEL) | Survey- or alert-driven utilization table. EDA turns a Netcool or Dynatrace alert into a ServiceNow work note with the storage facts. |

Step-by-step demo: [`docs/DEMO_RUNBOOK.md`](docs/DEMO_RUNBOOK.md).

---

## Repository layout

```
aap_config/                   Config as code for every AAP object (infra.aap_configuration format)
playbooks/
  aap_configure.yml           Applies aap_config/ to AAP
  lab_reset.yml               Returns the demo lab to a known starting point
  uc1_validate_request.yml    UC1: guardrail checks (runs before approval)
  uc1_create_directories.yml  UC1: create directories, print a summary table
  uc2_storage_report.yml      UC2: normalize survey or alert, collect df, build report
  uc2_update_incident.yml     UC2: add the report to a ServiceNow incident (mock or live)
  uc2_simulate_alert.yml      UC2: post a simulated Netcool/Dynatrace alert to its event stream
roles/
  directory_provision/        UC1 logic: validate, create, report
  storage_report/             UC2 logic: normalize, collect, deep_dive, report, work-note template
rulebooks/
  storage_alert_enrichment.yml  EDA: Netcool and Dynatrace sources, filtering, throttling, workflow launch
eda/
  payloads/                   Representative Netcool and Dynatrace JSON, plus the Dynatrace webhook template
  send_test_event.sh          Simulate an alert (bash/curl)
  Send-TestEvent.ps1          Simulate an alert (PowerShell)
inventory/hosts.example.yml   Example layout, including AIX connection variables
execution-environment/        EE definition for config as code (and servicenow.itsm for live mode)
```

## AAP objects

| Type | Name | Notes |
|------|------|-------|
| Project (controller and EDA) | AAP Use Cases | This repository |
| Credential type and credential | ServiceNow ITSM (use cases) / UC2 - ServiceNow | Injects `SN_HOST`, `SN_USERNAME`, `SN_PASSWORD` |
| Credential type and credential | Event Stream Secrets (use cases) / Use Cases - Event Stream Secrets | Injects the event stream token and password as extra vars |
| Job template | Use Cases - Reset Lab | Cleans demo directories, stages a demo file, denies stale approvals, restarts the activation |
| Job template | UC1 - Validate Directory Request | Runs on localhost only |
| Job template | UC1 - Create Directories | Machine credential, `become` |
| Job template | UC2 - Collect Storage Utilization | Read-only |
| Job template | UC2 - Update ServiceNow Incident | `snow_mode`: mock or live |
| Job template | UC2 - Simulate Monitoring Alert | Sends a Netcool, Netcool clear or Dynatrace alert through EDA and reports the workflow it launched |
| Workflow | **UC1 - Self-Service Directory Provisioning** | Survey → validate → **approval** → create |
| Workflow | **UC2 - Storage Utilization Report** | Survey or EDA → collect → (always) update incident |
| EDA credentials | UC2 - Netcool Event Stream Token, UC2 - Dynatrace Event Stream | Header token and basic auth |
| Event streams | UC2 - Netcool Alerts, UC2 - Dynatrace Problems | Mapped to rulebook sources `netcool_alerts` and `dynatrace_problems` |
| Rulebook activation | UC2 - Storage Alert Enrichment | Uses an existing EDA "Red Hat Ansible Automation Platform" credential |

Some existing objects are referenced by name rather than created. Set them in [`aap_config/00_settings.yml`](aap_config/00_settings.yml):
- inventory
- machine credential
- execution environment
- decision environment
- EDA controller credential

---

## Deploying with config as code

1. **Build or pick an execution environment** containing `infra.aap_configuration`, `ansible.platform`, `ansible.controller` and `ansible.eda` (see [`execution-environment/`](execution-environment/)). The certified collections come from Automation Hub, not public Galaxy, so they can't be installed by project sync.
2. **Create a project** for this repository in Automation Execution.
3. **Create a job template:**
   - Playbook: `playbooks/aap_configure.yml`
   - Execution environment: the one from step 1
   - Credential: a *Red Hat Ansible Automation Platform* credential
   - Inventory: any inventory
4. **Override settings** as extra vars. Pass real event-stream secrets here instead of committing them:
   ```yaml
   uc_inventory: my-inventory
   uc_machine_credential: my-ssh-credential
   uc_uc2_default_targets: aix_servers
   uc_netcool_stream_token: <random string>
   uc_dynatrace_stream_password: <random string>
   ```
5. **Attach the secrets credential.** After the first run, add **Use Cases - Event Stream Secrets** to this job template and remove the secret extra vars. Re-runs then reuse the stored values instead of resetting the event stream credentials to the placeholders.
6. **Launch it.** Re-run it after any change to `aap_config/`. The playbook syncs the EDA project, waits for the import, then creates the rulebook activation. Existing activations are left running on re-runs. An activation keeps the rulebook it was created with, so after editing a rulebook, re-run with `uc_recreate_activations: true`.
7. **Collect the URLs** (only needed for the command-line simulators): Automation Decisions → Event Streams → copy the URL of each stream.

To run from a workstation instead, export `AAP_HOSTNAME` and `AAP_TOKEN` and run `ansible-playbook playbooks/aap_configure.yml` with the collections installed.

---

## Running the use cases

The surveys come pre-filled with lab defaults (`uc_uc1_default_*` and `uc_uc2_default_*` in `aap_config/00_settings.yml`), so each workflow runs as-is.

### Resetting the lab
Run **Use Cases - Reset Lab** before a demo (and after, to clean up):
- removes `/app/demo` and `/tmp/uc-demo`, plus `/app` if it's left empty; nothing outside those paths is touched
- re-creates a 2 GB `/tmp/uc-demo-bigfile` so the UC2 deep dive finds a recent large file (skipped if free space is under 3× that size)
- denies UC1 approvals left pending by earlier runs
- restarts the EDA activation, clearing the 15-minute throttle so alerts can be replayed

The last two steps use the job template's *Red Hat Ansible Automation Platform* credential (`uc_aap_credential`) and are skipped without one.

### UC1: directories
Launch **UC1 - Self-Service Directory Provisioning**. Defaults:

| Survey field | Default |
|---|---|
| Target servers | `node01` |
| Directories | `/app/demo/data, /app/demo/logs` |
| Owner / Group | `nobody` / `nobody` |
| Permissions | `2775` (optional) |

Validation rejects the following before anyone is asked to approve:
- relative paths or `..` segments
- system locations (`/etc`, `/usr`, ...) and protected paths (`/`, `/var`, `/opt`, ...)
- `all`, `localhost` or wildcard host patterns
- malformed owner, group or mode values
- more than 25 paths

Existing directories are reported and **left unchanged** by default. Tune the guardrails in [`roles/directory_provision/defaults/main.yml`](roles/directory_provision/defaults/main.yml).

### UC2: storage report
Launch **UC2 - Storage Utilization Report**. Defaults:
- Targets: `node01`
- Paths: `/var, /tmp`
- Incident: `INC0010042`
- Troubleshooting detail: `yes`, which adds the largest directories, recent large files, volume group headroom and a suggested extend command. The command is advisory only.
- Incident number: if you enter one, the second workflow node shows the work note (mock) or adds it (live).

### UC2 + EDA: alert to enriched incident
Launch **UC2 - Simulate Monitoring Alert** and pick an alert type:
- `netcool`: filesystem alert for the server and path; launches the UC2 workflow
- `netcool-clear`: resolution event; the rulebook logs it and does nothing
- `dynatrace`: low disk space problem; use an FQDN such as `node01.lab.example.com` to show inventory name mapping

The job looks up the event stream, authenticates like the real tool (header token or basic auth), posts the alert, then prints the workflow job that EDA launched. Sending the same host and path again within 15 minutes is throttled; run **Use Cases - Reset Lab** to clear it.

From a terminal instead:
```bash
./eda/send_test_event.sh netcool   "<netcool stream url>"   "<token>"               node01 /var INC0010042
./eda/send_test_event.sh dynatrace "<dynatrace stream url>" "dynatrace:<password>"  node01.lab.example.com /tmp
./eda/send_test_event.sh netcool-clear "<netcool stream url>" "<token>"             # ignored: resolution event
```
- The same Netcool alert within 15 minutes is throttled.
- Dynatrace FQDNs are mapped to short inventory names automatically.

### ServiceNow live mode (optional)
1. Put real values in the `UC2 - ServiceNow` credential. A free developer instance works.
2. Set `snow_mode: live` on **UC2 - Update ServiceNow Incident**, or re-run config as code with `uc_snow_mode: live`.
3. Netcool alerts carry the incident number (`TTNumber`). Dynatrace alerts fall back to the newest active incident whose CI matches the host.

---

## AIX notes
- **Python:** Ansible modules need Python on the LPAR. That's AIX Toolbox `/opt/freeware/bin/python3`, or `/usr/bin/python3` on AIX 7.3.
- **Privilege escalation:** `sudo` is not installed by default; set `ansible_become_method: su` if needed.
- **UC1:** owner and group checks use `lsuser` and `lsgroup` on AIX (there is no `getent`). Creation uses `ansible.builtin.file` on both platforms.
- **UC2:** `df -P -k` is POSIX on both. The parser reads the block size from the header, so `512-blocks` output also works.
- **Headroom and suggested fixes:** headroom uses `lslv` and `lsvg` ("FREE PPs"). The suggested fix is `chfs -a size=+NM /mount`.
- **Status:** the AIX-specific commands were written from AIX 7.x documentation and tested against sample AIX output, not a live LPAR. Validate on a nonprod AIX host first.

## Testing
- **End to end on an AAP 2.6 lab (RHEL 9 target):**
  - config as code applied and re-applied cleanly
  - UC1 rejects a bad request before approval; a valid one runs validate → approve → create
  - UC2 survey run with deep dive and the mock ServiceNow update
  - EDA via both event streams: Netcool alert launches the workflow, the duplicate is throttled, the clear is ignored, and the Dynatrace FQDN maps to the inventory host
- **Templating:** the role logic and work-note template were also run through ansible-core's templating engine with AIX `df`/`lsvg` output and edge cases. The AIX commands themselves have not been run on a live LPAR.
- **Files:** every YAML and JSON file parses, and the rulebook validates against the ansible-rulebook JSON schema.
