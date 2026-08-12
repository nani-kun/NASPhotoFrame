# Security Policy

## Supported Versions

Security fixes apply only to the latest version on the `main` branch. Because the target operating system no longer receives routine security updates, this project cannot make old iOS itself secure.

## Reporting a Vulnerability

Report vulnerabilities privately through **Security → Report a vulnerability** in the GitHub repository. If private vulnerability reporting is not enabled, contact the maintainer directly. Do not publish exploitable details, real IP addresses, account names, passwords, private keys, cookies, or sensitive log content in a public issue.

A useful report includes the affected version, reproduction steps, impact, a suggested fix, and the smallest practical test case.

## Deployment Boundaries

- Keep the iPad, SSH service, and NAS management page on a trusted or isolated local network.
- `nas-manager` uses HTTP Basic Authentication and does not provide TLS. Access from an untrusted network must go through a trusted reverse proxy with HTTPS enabled.
- Use a dedicated read-only NAS account and a separate SSH key, and change the jailbreak environment's default root password.
- The charge and display daemons run as root. When changing command parsing or remote-control interfaces, pay particular attention to command injection, privilege expansion, and unauthorized state changes.
