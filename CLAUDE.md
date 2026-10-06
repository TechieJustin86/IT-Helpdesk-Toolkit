# Project rules

This repo is PUBLIC on GitHub and is used as a place to store and share scripts. Anything pushed is visible to everyone, and git history is permanent.

## Pre-push sensitive-data check (required)

Before every commit, push, or PR, scan the changes (`git diff` / `git diff master...HEAD`) and stop to tell the user if any of these appear:

- Passwords, API keys, tokens, secrets, connection strings, or certificates/keys (`.pfx`, `.pem`, `.key`)
- Real domain names, server names, internal hostnames, UNC paths to real servers, or internal IP ranges. Generic placeholders such as `fileserver`, `domain.local`, `192.168.1.0/24` are fine.
- Employee or user info: real names, usernames, emails (other than the maintainer's public contact in SECURITY.md), machine names
- Anything from the employer that shouldn't be public: internal tooling names, company names, ticket data, logs, exports, inventories
- Machine-specific or generated files (settings JSON, logs, reports, CSV exports). Prefer `.gitignore`.

If something is found, do NOT commit or push. Report the file and line and ask the user how to proceed. A secret that reaches git history cannot be fully removed by deleting it later, so catch it before the commit.

## Workflow

- `master` is protected: changes go through a PR. The owner is the only admin, so merges need `--admin` (ask the user first).
- Claude may merge PRs only when the owner explicitly says to.
