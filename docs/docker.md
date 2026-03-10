# Docker

Archsight is available as a Docker image from the GitHub Container Registry.

## Image

```
ghcr.io/ionos-cloud/archsight
```

The image is based on `ruby:4.0-alpine3.23`, exposes port **4567**, and includes a healthcheck.

## Quick Start

```bash
# Run web server (default)
docker run -p 4567:4567 -v "/path/to/resources:/resources" ghcr.io/ionos-cloud/archsight

# Run in production mode with logging
docker run -p 4567:4567 -v "/path/to/resources:/resources" ghcr.io/ionos-cloud/archsight web --production

# Run lint
docker run -v "/path/to/resources:/resources" ghcr.io/ionos-cloud/archsight lint -r /resources

# Run any command
docker run ghcr.io/ionos-cloud/archsight version
```

Access web interface at: <http://localhost:4567>

## Notes

- Volume mount `-v "/path/to/resources:/resources"` mounts your resources directory
- Default command starts the web server on port 4567
- Pass subcommands directly (lint, version, console, template)

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ARCHSIGHT_RESOURCES_DIR` | Path to resources directory inside the container | `/resources` |
| `APP_ENV` | Application environment | `production` |

## Building Locally

```bash
docker build -t archsight .
docker run -p 4567:4567 -v "/path/to/resources:/resources" archsight
```
