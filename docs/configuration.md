# Configuration

Archsight reads the settings of the person (or the deployment) running it, such as access tokens and the URLs of other systems,
from one file with a section per integration. What the resources describe, the architecture itself, does not belong here: it is
defined in the [resources directory](/doc/tool) you point Archsight to.

## The configuration file

The default location is `~/.config/archsight/archsight.yaml`. Set `ARCHSIGHT_CONFIG` to use another file.

```yaml
confluence:
  token: <personal access token>
  drawio: true
jira:
  issue_url: https://jira.example.com/browse/{issue}
```

The file is optional: a setting that is not in it is taken from the environment, and features that need a setting you have not
given (for example the Jira links) are simply off. Unknown sections and keys are ignored. Keep the file private, it holds tokens
(`chmod 600 ~/.config/archsight/archsight.yaml`). Archsight never prints a token and never writes one to a log or an error
message; an error about the file names the file only.

## Environment variables

Every setting can also be given as an environment variable named `ARCHSIGHT_<SECTION>_<KEY>`. The variable replaces the value in
the file, and with all settings in the environment there is no need for a file at all, which suits containers and CI. A variable
that is set but empty counts as not set.

## Settings

| Setting in the file | Environment variable | Used for |
|---------------------|----------------------|----------|
| `confluence.token` | `ARCHSIGHT_CONFLUENCE_TOKEN` (also `CONFLUENCE_TOKEN`) | Personal access token of the Confluence that `archsight export --to confluence` writes to, see [Exporting to Confluence](/doc/pages#exporting-to-confluence) |
| `confluence.drawio` | `ARCHSIGHT_CONFLUENCE_DRAWIO` (also `CONFLUENCE_DRAWIO`) | `true` if that Confluence has the draw.io app: diagrams are then exported as draw.io macros instead of images. Default `false` (`--drawio` / `--no-drawio` decide per run) |
| `jira.issue_url` | `ARCHSIGHT_JIRA_ISSUE_URL` | Where the issues live, with `{issue}` in place of the key: `{jira:PROJ-123}` in a page becomes a link, see [Macros](/doc/pages#macros). Only `http(s)` URLs are used |
| `jira.token` | `ARCHSIGHT_JIRA_TOKEN` | Reserved, nothing uses it yet |

## Command line

`archsight export --config PATH` reads that file for one run. The CLI options `--drawio` and `--no-drawio` override
`confluence.drawio`.

## Containers

In [Docker](/doc/docker) either pass the settings as variables, which is the simplest way,

```bash
docker run -e ARCHSIGHT_JIRA_ISSUE_URL='https://jira.example.com/browse/{issue}' \
  -p 4567:4567 -v "/path/to/resources:/resources" ghcr.io/ionos-cloud/archsight
```

or mount the file and point `ARCHSIGHT_CONFIG` at it (`-v "$HOME/.config/archsight/archsight.yaml:/config/archsight.yaml:ro" -e
ARCHSIGHT_CONFIG=/config/archsight.yaml`). On [Kubernetes](/doc/kubernetes) put tokens in a Secret and expose them as environment
variables, plain values such as the Jira URL can go into the pod's environment directly.
