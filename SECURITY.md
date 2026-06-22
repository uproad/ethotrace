# Security Policy

*日本語版は [SECURITY_JP.md](SECURITY_JP.md) を参照してください。*

## Supported versions

Ethotrace is pre-1.0, and fixes are provided only against the **latest commit on `main`**.
When reporting a vulnerability, please confirm the issue against the most recent `main` if you
can.

## Reporting a vulnerability

Please do **not** report security vulnerabilities through public issues. Disclosing them
publicly risks exploitation before a fix is available.

Instead, use GitHub's **Private Vulnerability Reporting**:

1. Open the **Security** tab of this repository.
2. Click **Report a vulnerability** to file a private report.

Including the following helps us confirm and fix the issue faster:

- The affected component (gem name, file / method).
- Reproduction steps, or a proof of concept.
- The expected impact.

We will review the report and respond with a remediation plan as quickly as we can. Until a
fix is ready to disclose, please help us keep the details private.

## Threat model

Ethotrace is a **development and testing tool that observes method calls during test runs**.
It is not intended to run on a production request path. Observation results (JSONL) **can
record the values of arguments and return values** that flow through your tests. Before
publishing or sharing observation data, make sure no secrets (tokens, personal data, etc.)
contained in fixtures have leaked into it.
