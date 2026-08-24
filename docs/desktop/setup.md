# Setup and the first-use journey

How does a fresh install become a machine whose setup Tama calls complete?
There is no separate setup gate: since the change titled *Keep Tama
navigation available during setup*, an authorized operator gets the full
window immediately, and guided first use runs alongside as a quiet journey.
The end-to-end operator path is [quick-start](../quick-start.md); every
prerequisite and failure is in [onboarding](../onboarding.md).

## The completion evidence

Setup is a judgment over live evidence, not a wizard's last button. Tama
calls setup complete only while *all* of the following hold:

- the bundled catalog's structural validation passes;
- a hook release is installed (`installed.json` records its id);
- hooks are not globally disabled;
- the privileged backend reports exactly `Enabled`;
- at least one live session is **setup-ready**.

A setup-ready session is one whose record proves the policy is really
running: installed and loaded release ids both equal the recorded installed
release, no registry load error, no required or pending reload, a nonzero
registered hook count equal to the loaded count, no unknown hook ids, not
globally disabled, no per-session disables, and a system policy that is
ready, error-free, and in `kernel-gated` mode. This is the same judgment
[Posture](posture.md) renders field by field
([concepts/posture](../concepts/posture.md)).

The actions that produce the evidence live on their own screens:
[Settings](settings.md) installs the runtime and registers the privileged
backend; [Session](session.md) shows the live session that completes the
picture, with `Refresh sessions` on demand.

## The signed journey

First use is driven by a signed journey definition, `first-use` version
`2026-08-04.2`, bundled as `tama-first-use.json` and fetched through the
Stado integration transport (token from the `TAMA_STADO_INTEGRATION_TOKEN`
environment key; the bundled copy is the fallback). Progress persists in
user defaults under the `tama.onboarding.v1` namespace. Four screens, in
order:

| Screen | Kind | Completion |
|---|---|---|
| `promise` — `Know what every agent is allowed to do` | promise | continue |
| `control_model` — `Policy first, mutations explicit` | explanation | continue |
| `setup_handoff` — `Reach one matching supervised session` | setup handoff | fact `visible_matching_setup = true` |
| `first_success` — `Observe one supervised session` | first success | fact `supervised_session_observed = true` |

While the journey loads, the window shows `Loading Tama…`. While the
journey waits at `first_success`, a quiet strip at the foot of the window —
not an alert, because waiting for the first supervised session is not a
fault — shows the screen's own words: `Observe one supervised session` /
`Open a real agent session. Tama completes this guide only after the
control plane reports that session under the installed policy.` The journey
completes only when a live session actually appears.

## What gets recorded, and how to reset it

`tama.hasCompletedSetup` is recorded in the app's defaults when the journey
records the verified setup handoff; on a machine that already completed
setup, the journey is reconciled forward instead of replayed. Failures are
explicit, never silent: `Tama could not load its signed first-use journey.
<error>` (surfaced under `Onboarding is unavailable`), `Tama could not
reconcile the existing setup. <error>`, and `Tama could not record the
verified setup handoff. <error>`.

To repeat guided first use without changing any enforcement state:

```bash
defaults delete ai.wisent.tama.desktop tama.hasCompletedSetup
```

Deleting the defaults key replays the journey; it does not uninstall,
disable, or reinstall anything ([onboarding](../onboarding.md#reset)).
