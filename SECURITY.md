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

Optional web suggestions may send the current search query to a third-party suggestion endpoint when that feature is enabled. Currency conversions may contact `api.frankfurter.dev` while typing when `currencyRates` is enabled (the default); only the currency codes are sent, never the amount. Set `"currencyRates": false` to disable those lookups. Normal web-search and calendar URLs are opened only after explicit user activation.

`bin/spotlight-helper` acts as the primary boundary for file access and subprocess execution. Security issues involving this boundary, especially those involving command execution, file validation, paths, permissions, or untrusted input, are particularly important.

Spotlight does not intentionally include telemetry, analytics, or a background network service.

## Non-Security Bugs

For bugs that do not have a security impact, please use the repository's normal GitHub issue tracker.
