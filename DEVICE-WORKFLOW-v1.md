# Device workflow (development)

Open Enterprise > Server, select a device, then double-click it or use the
context menu (Shift+F10) > Selected device workflow.

1. Scan risks and review the assessment, its freshness and inventory time.
2. Select Windows/Office and enter a product key, then confirm the change.
   Changes require a current assessment and the agent's remote-change permission.
3. Wait for the job result and fresh inventory; run Verify scan.
4. Export the selected device's report (HTML/JSON/CSV).

The window refreshes every five seconds and displays last agent contact, queued
or running state, completion, exit code and failure reason. Last agent contact
does not make inventory fresh. A disconnected running job remains pending;
elapsed time alone never authorizes another execution.

One pending job per device is enforced across UI/CLI submissions. Agent receipts
survive result-delivery failures; repeated delivery returns the stored result.
Interrupted execution is marked ActionRequired, not executed again. Retry is
limited to finished read-only jobs. License changes require a new key and explicit
confirmation; verify the device first after any uncertain result.

Deploy matching updated server and agent source together. Existing released EXE,
signed release metadata and downloadable release assets are unchanged. This
development change has not undergone artifact-bound VM release QA.
