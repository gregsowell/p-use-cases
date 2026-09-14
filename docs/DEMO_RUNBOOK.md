# Demo runbook

Target length is **about 25 minutes**. The lab target host is `node01`.

## Before the demo
- [ ] Config as code has run successfully since the last Git push.
- [ ] `UC2 - Storage Alert Enrichment` activation is **Running** (Automation Decisions → Rulebook Activations).
- [ ] Run **Use Cases - Reset Lab** with its defaults. It clears UC1 demo directories so UC1 shows `CREATED`, stages a 2 GB file for the UC2 deep dive, denies stale approvals and restarts the activation so throttling starts fresh.
- [ ] After the demo, run **Use Cases - Reset Lab** again with *Stage a 2 GB file* set to `no` to leave the host clean.
- [ ] Browser tabs open: UC1 workflow, UC2 workflow, UC2 - Simulate Monitoring Alert, Jobs, Rulebook activation → History.

## Act 1: self-service directories (UC1), about 8 min
1. Launch **UC1 - Self-Service Directory Provisioning**.
2. **Show a guardrail first.** Enter `/etc/app, /var` as the directories. The validate job fails with plain-English reasons.
   Talking point: *bad requests never reach an approver or a server.*
3. Relaunch and keep the survey defaults, which are a valid request:
   - Targets: `node01`
   - Directories: `/app/demo/data, /app/demo/logs`
   - Owner / group: `nobody` / `nobody`
   - Permissions: `2775`
4. The workflow pauses at **Approve directory request**. Open the approval and approve it.
5. Open the **UC1 - Create Directories** job and show the summary table.
6. Relaunch the same request. Rows now show `EXISTS: left unchanged`.
   Talking point: *idempotent; never re-owns existing data.*

## Act 2: storage report (UC2), about 5 min
1. Launch **UC2 - Storage Utilization Report**. The defaults (`node01`, `/var, /tmp`, INC0010042, deep dive `yes`) work as-is; add `, /nope` to the paths to show error handling:
   - Targets: `node01`
   - Paths: `/var, /tmp, /nope`
   - Troubleshooting detail: `yes`
2. The table shows `/nope` as `NOT FOUND` instead of failing the job.
3. Show the deep dive: largest directories, the 2 GB file, volume group headroom and the suggested extend command.

## Act 3: EDA incident enrichment, about 10 min
1. Show `rulebooks/storage_alert_enrichment.yml` and the activation's event stream mapping.
2. Launch **UC2 - Simulate Monitoring Alert** with alert type `netcool`, server `node01`, path `/var`, incident `INC0010042`. This stands in for Netcool posting to the event stream. The job output ends with the workflow job EDA launched.
3. Activation History shows the rule fired, and Jobs shows the UC2 workflow launched with `alert_source=netcool`.
4. Open **UC2 - Update ServiceNow Incident**: the work note for INC0010042 (mock), or the real incident in live mode.
5. **Relaunch the simulator with the same values.** No workflow launches (the job output says so) because the rulebook throttles the same host and mount for 15 minutes. To replay the act, run **Use Cases - Reset Lab**, which restarts the activation.
6. Relaunch the simulator with alert type `dynatrace`, server `node01.lab.example.com`, path `/tmp`. The FQDN maps to `node01`. There's no incident number, so live mode looks it up by CI.
7. Relaunch with alert type `netcool-clear`. It's printed in the activation log and no job runs.

The command-line equivalents (`eda/send_test_event.sh`, `eda/Send-TestEvent.ps1`) do the same thing if you prefer a terminal.

---

## Troubleshooting
| Symptom | Likely cause and fix |
|---|---|
| Config as code fails: couldn't resolve module/role | The execution environment lacks `infra.aap_configuration` or the certified `ansible.*` collections. |
| Activation creation fails: rulebook not found | The EDA project has not finished importing. Re-run config as code, or sync the EDA project. |
| Event stream returns 401/403 | Wrong secret. Netcool uses header `X-Event-Token`; Dynatrace uses basic auth. |
| Event accepted but no job launches | Check the activation is Running and *Forward events* is on. Check History for the matched rule, and confirm the EDA controller credential is valid. |
| Activation log: `variables_needed_to_start` | API launches must answer required survey questions; the rulebook passes placeholders. Keep **Prompt on launch: variables** enabled on the UC2 workflow. |
| Rulebook edits have no effect | Activations keep the rulebook they were created with. Re-run config as code with `uc_recreate_activations: true`. |
| UC2 row `UNREACHABLE` | SSH or credential problem for that host; the collect job output shows the connection error. |
| UC1 `user X not found` | Owner and group must already exist on every target host. |
| Dynatrace alert: "Could not determine a directory" | Include `{ProblemDetailsJSON}` in the webhook template (`eda/payloads/dynatrace_webhook_template.json`). |
