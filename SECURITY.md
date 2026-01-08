# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in archsight, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Email the maintainers with details of the vulnerability
3. Include steps to reproduce the issue if possible
4. Allow reasonable time for a fix before public disclosure

We will acknowledge receipt within 48 hours and provide an estimated timeline for a fix.

## Security Considerations

Archsight processes YAML files from the local filesystem. When deploying the web interface:

- Run behind a reverse proxy with authentication in production environments
- Limit access to trusted users who should have visibility into architecture data
- The tool does not execute arbitrary code from YAML files
- GraphViz rendering is performed client-side using WebAssembly
