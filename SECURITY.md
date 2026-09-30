# Security Policy

## Supported Versions

Security fixes are provided for the current version of Spotlight and, where relevant, the current `main` branch.

| Version        | Supported                                                     |
| -------------- | ------------------------------------------------------------- |
| Latest release | Yes                                                           |
| `main`         | Yes, for issues present in current development code           |
| Older releases | No; please reproduce against the latest release when possible |

Users should update with:

```bash
omarchy plugin update io.github.maajix.spotlight
```

## Reporting a Vulnerability

Please **do not open a public GitHub issue, discussion, or pull request for an undisclosed security vulnerability**.

Use GitHub's private vulnerability reporting for this repository:

https://github.com/maajix/omarchy-spotlight/security/advisories/new

If private vulnerability reporting is unavailable, open a public issue titled **Security contact request** without including vulnerability details, proof-of-concept code, logs, screenshots, or other sensitive information. A private reporting channel can then be arranged.

A useful report should include as much of the following as possible:

* A clear description of the vulnerability and its security impact.
* The affected Spotlight version or commit SHA.
* Your Omarchy version and any relevant environment details.
* Reproduction steps or a minimal proof of concept.
* Whether user interaction or non-default configuration is required.
* Relevant paths, inputs, commands, or configuration values.
* Logs or screenshots with secrets and personal data removed.
* Suggested mitigations or fixes, if you have them.

Please include enough information to reliably reproduce and assess the issue.

## Disclosure Process

After receiving a report, the maintainer will try to:

1. Acknowledge the report within 7 days.
2. Reproduce and assess the vulnerability and its severity.
3. Keep the reporter informed when there is a meaningful change in status.
4. Prepare a fix and, when appropriate, a GitHub Security Advisory and release.
5. Coordinate public disclosure with the reporter.

Please avoid public disclosure until a fix has been released or a disclosure date has been mutually agreed upon.

Complex issues may require additional time, particularly when a fix depends on an upstream project.

Credit will be given in an advisory or release notes when requested and appropriate. Anonymous reporting is also welcome.

## Safe Harbor

Good-faith security research is welcome.

When testing Spotlight:

* Test only on systems and data you own or are explicitly authorized to use.
* Avoid accessing, modifying, retaining, or publishing other people's data.
* Avoid destructive actions and unnecessary disruption.
* Collect only the information needed to demonstrate the vulnerability.
* Stop testing and report the issue if you encounter sensitive data or unexpected impact outside your test environment.

Research consistent with this policy will be treated as authorized security testing for this project. The maintainer will not pursue action against researchers for accidental, good-faith violations of this policy.

## Security Design Notes

Spotlight is designed to keep most processing local.

Optional web suggestions may send the current search query to a third-party suggestion endpoint when that feature is enabled. Currency conversions may contact `api.frankfurter.dev` while typing when `currencyRates` is enabled (the default); only the currency codes are sent, never the amount. Set `"currencyRates": false` to disable those network requests while retaining local conversions and cached rates. Normal web-search and calendar URLs are opened only after explicit user activation.

AI is disabled by default. Submitting an `ai:` query after enabling it sends the request to the selected Claude or Codex CLI provider. Spotlight restricts those calls to answers and proposed commands. Commands are displayed and can be copied; the user chooses whether to run one.
AI web search is separately disabled by default and can be enabled in Spotlight Settings.
An explicitly submitted AI request may finish while Spotlight is closed; hiding the overlay does not cancel it. Cancel, disabling Ask AI, submitting a replacement request, or unloading/restarting the shell terminates it. Only the latest request/progress/result is retained in shell memory. Background completion notifications use fixed text without the prompt or answer; their fixed action summons Spotlight.
When a location artifact appears, Spotlight requests a static preview from `mapmap.ai` using its coordinates and zoom. If the preview fails, the coordinates and link remain visible. Clicking **Open in OpenStreetMap** sends the location to the browser.
Weather cards require AI web search and are built from the selected provider's answer; Spotlight makes no direct weather request. An optional saved weather location is sent to the provider only for recognized weather questions. Clicking a weather card's source opens that AI-provided HTTPS URL in the browser. Spotlight validates its shape but cannot prove the provider read it.

Diff previews never open their display-labelled paths or read/write configuration files. Before/after text is bounded and rendered as plain code. Both copy actions are explicit; the user reviews and applies any proposed edits manually.

Image galleries download AI-selected or user-supplied direct HTTPS PNG/JPEG URLs for previews. The broker rejects credentials, non-443 ports, private/mixed DNS answers and redirects, disables curl configuration/proxies, and pins a public IP with hostname TLS verification. Downloads remain capped at 8 MiB; input dimensions at 32 megapixels / 12,000 pixels per edge. Native JPEG downsampling and bounded image decoding reduce inputs to metadata-stripped local previews up to 2,560 × 1,440 before Quickshell loads them. The private cache keeps at most 16 images. Preview fetching sends a request to the image host; Source opens the attribution page only after a click.

Gallery Save and Apply accept only a helper-generated content hash and verify cached bytes/ownership. Save creates a fixed private file in `~/Pictures/Spotlight` without overwriting changed files. Apply performs that save and invokes only `omarchy theme bg set` with the verified saved path. These actions require separate explicit user clicks; AI output cannot apply wallpaper or choose a destination path.

Place cards make no automatic map requests. Clicking View map opens an OpenStreetMap search for the validated venue name/address; Source opens the provider-supplied HTTPS URL. Opening hours and ratings come from the provider, with provenance and unknown states shown; URL validation does not prove that the provider checked the page.

System dashboards are collected locally after the AI requests a validated card. The provider cannot supply measurements and is not given the collected data. Reads of `/proc`, filesystem statistics, the existing bounded service listing, and a three-second home-folder `du` scan are read-only. Directory scans do not follow symlinks or cross filesystems. Partial and unavailable data are labelled; only an explicit Copy snapshot action exports the values to the clipboard.

Checklist checkmarks are held in the shell's memory, separately from AI output, for up to 32 checklists. They survive closing Spotlight but reset on shell restart. Progress is not written to disk or sent to the provider; only explicit user actions check or reset tasks.

`bin/spotlight-helper` acts as the primary boundary for file access and subprocess execution. Security issues involving this boundary, especially those involving command execution, file validation, paths, permissions, or untrusted input, are particularly important.

Spotlight does not intentionally include telemetry, analytics, or a background network service.

## Non-Security Bugs

For bugs that do not have a security impact, please use the repository's normal GitHub issue tracker.
