# xngTool — SearXNG Web Search & Extract for Hermes Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/Python-3.7+-blue.svg)](https://www.python.org/)

A standalone skill for **Hermes Agent** that provides web search and web extraction via a local SearXNG instance. Zero API keys, zero external dependencies — everything runs locally.

## Features

- **Web Search** — Query SearXNG and receive compact, structured results
- **Web Extract** — Fetch and clean web page content (HTML → plain text)
- **No API Keys** — Uses your local SearXNG instance
- **Token-Optimized** — Compact outputs designed for LLM consumption
- **No External Deps** — Python stdlib only (`urllib`, `re`, `json`, `html`)
- **JSON Output** — Machine-parseable results for tool integration
- **Independent** — Does not depend on any other installed skill

## Installation

### Step 1: Ensure SearXNG is Running

Make sure you have a SearXNG instance running with the JSON format enabled. In your SearXNG `settings.yml`:

```yaml
search:
  formats:
    - html
    - json
```

SearXNG is available at: https://github.com/searxng/searxng

### Step 2: Run the Installer

```bash
bash ~/.hermes/skills/xngTool/scripts/install.sh
```

The installer will:

1. Check for an existing Hermes installation
2. Verify Python 3 and PyYAML are available (installs PyYAML if missing)
3. Copy skill files to `~/.hermes/skills/xngTool/`
4. Generate a `skill.json` manifest
5. Configure `web.searxng_url` in `~/.hermes/config.yaml`
6. Probe your SearXNG instance for connectivity
7. Verify checksums of all copied files

### Installation Options

```bash
# Standard install (prompts for confirmation)
bash ~/.hermes/skills/xngTool/scripts/install.sh

# Override SearXNG URL
SEARXNG_URL="http://sx.local:8080" bash ~/.hermes/skills/xngTool/scripts/install.sh

# Force overwrite (no prompts)
bash ~/.hermes/skills/xngTool/scripts/install.sh --force

# Dry run (preview only, no changes)
bash ~/.hermes/skills/xngTool/scripts/install.sh --dry-run

# Verbose (mirror all output to log file)
bash ~/.hermes/skills/xngTool/scripts/install.sh --verbose

# Install with custom Python binary
PYTHON_CMD=/usr/bin/python3.11 bash ~/.hermes/skills/xngTool/scripts/install.sh

# Show help
bash ~/.hermes/skills/xngTool/scripts/install.sh --help
```

#### Flags

| Flag | Description |
|------|-------------|
| `-h, --help` | Show help and exit |
| `-u, --uninstall` | Remove the skill and clean config.yaml |
| `-f, --force` | Overwrite existing files / answer yes to every prompt |
| `-d, --dry-run` | Show what would be done without changing anything |
| `-v, --verbose` | Mirror all output into the log file |
| `-V, --version` | Print version and exit |

#### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_HOME` | `~/.hermes` | Hermes home directory |
| `SEARXNG_URL` | `http://127.0.0.1:8888` | SearXNG instance URL |
| `PYTHON_CMD` | `python3` | Python 3 binary to use |
| `LOG_FILE` | `~/.hermes/xngtool_install.log` | Log file path |
| `HTTP_PROXY` | — | Proxy for connectivity checks |
| `HTTPS_PROXY` | — | Proxy for connectivity checks |

### Manual Installation

If you prefer not to use the installer, copy the files manually:

```bash
mkdir -p ~/.hermes/skills/xngTool/scripts
cp ~/.hermes/skills/xngTool/SKILL.md ~/.hermes/skills/xngTool/
cp ~/.hermes/skills/xngTool/README.md ~/.hermes/skills/xngTool/
cp ~/.hermes/skills/xngTool/xngTool.py ~/.hermes/skills/xngTool/scripts/
chmod +x ~/.hermes/skills/xngTool/scripts/xngTool.py
```

Then ensure `~/.hermes/config.yaml` has:

```yaml
web:
  backend: searxng
  searxng_url: http://127.0.0.1:8888
```

## Uninstall

```bash
# Remove skill and clean config.yaml
bash ~/.hermes/skills/xngTool/scripts/install.sh --uninstall
```

This removes:
- `~/.hermes/skills/xngTool/` directory
- `web.searxng_url` and `web.backend` from `~/.hermes/config.yaml`

## Usage

### Command Line

#### Search

```bash
# Basic search
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "your query"

# Search with JSON output (for tool integration)
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "your query" --json

# Search with more results
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "your query" --limit 10

# Rich search with metadata
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "your query" --format rich
```

#### Extract

```bash
# Extract a single page
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py extract "https://example.com"

# Extract multiple pages
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py extract "https://example.com" "https://example.org" --json

# Extract with custom max length
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py extract "https://example.com" --max-length 10000
```

### From Python (inside a skill or script)

```python
import sys
from pathlib import Path

# Add the scripts directory to the path
scripts_dir = Path(__file__).parent / "scripts"
sys.path.insert(0, str(scripts_dir))

from xngTool import xngToolClient

# Create client (reads config automatically)
client = xngToolClient()

# Search — returns compact structured data
results = client.search("your query", limit=5)
# → {"success": True, "data": {"web": [{"title", "url", "description", "position"}]}}

# Extract — returns clean page content
page = client.extract("https://example.com/article")
# → {"success": True, "results": [{"url", "title", "content", "success"}]}
```

### From a Hermes Agent Session

When the skill is loaded, an agent can execute:

```bash
# Search
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "topic" --json

# Extract
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py extract "URL" --json
```

The `--json` flag is recommended for agent sessions as it returns directly parsable JSON.

## Output Format

### Search Results (JSON)

```json
{
  "success": true,
  "data": {
    "web": [
      {
        "title": "Page Title",
        "url": "https://example.com/page",
        "description": "Short description up to 200 characters...",
        "position": 1
      }
    ]
  }
}
```

### Extract Results (JSON)

```json
{
  "success": true,
  "results": [
    {
      "url": "https://example.com/page",
      "title": "Page Title",
      "content": "Cleaned text content...",
      "success": true
    }
  ]
}
```

## Token Optimization

This skill is designed to minimize token usage in LLM contexts:

- **Search**: Returns only title, URL, and a short description (max 200 chars) per result
- **Extract**: Strips scripts, styles, nav, footer, header, aside from HTML before converting to text
- **Truncation**: Smart head+tail truncation for large pages to preserve context
- **Compact format**: Default output avoids verbose metadata
- **5 results max**: By default, limiting search to 5 relevant results

## Configuration Options

All settings can be overridden via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SEARXNG_URL` | (from config) | SearXNG instance URL |
| `SEARXNG_TIMEOUT` | `15` | Request timeout (seconds) |
| `SEARXNG_LANGUAGE` | `auto` | Default language code |
| `SEARXNG_SAFESEARCH` | `0` | Safe search level (0-2) |
| `SEARXNG_MAX_RESULTS` | `5` | Default max search results |
| `SEARXNG_DESC_MAX` | `200` | Max description length |
| `SEARXNG_EXTRACT_MAX` | `5000` | Max extract output chars |
| `SEARXNG_EXTRACT_TIMEOUT` | `20` | Extract request timeout (seconds) |

## Dependencies

- **Python 3.7+** (stdlib only)
- **PyYAML ≥ 5.0** (for reading config.yaml — installed automatically by `install.sh`)
- **SearXNG instance** with JSON format enabled

No pip packages required for the script itself. Uses only:
- `urllib` — HTTP requests
- `re` — HTML parsing
- `json` — structured output
- `html` — HTML entity handling
- `argparse` — CLI parsing

## Troubleshooting

### "SearXNG URL not configured"

Make sure either:
1. `~/.hermes/config.yaml` has `web.searxng_url` set
2. The `SEARXNG_URL` environment variable is set

### "No results found"

Check that your SearXNG instance is running and accessible. Test manually:

```bash
curl "http://127.0.0.1:8888/search?q=test&format=json"
```

### "Invalid JSON response"

Your SearXNG instance may not have the JSON format enabled. Check `settings.yml`:

```yaml
search:
  formats:
    - html
    - json
```

### Connection refused

Your SearXNG instance may not be running. Check:

```bash
curl -I http://127.0.0.1:8888
```

### PEP 668 / Externally Managed Python

If pip fails with "externally-managed-environment", you have three options:

```bash
# Option a: Use a venv
python3 -m venv ~/.hermes/.venv && source ~/.hermes/.venv/bin/activate

# Option b: Use --break-system-packages (not recommended)
pip3 install --break-system-packages pyyaml

# Option c: Install via your distro package manager
apt install python3-yaml
```

### SELinux / AppArmor

If script execution fails on a security-hardened system:

```bash
# SELinux
sudo chcon -R -t bin_t ~/.hermes/skills/xngTool/scripts/

# AppArmor
# Allow read/execute on the skill dir in the Hermes profile
```

## License

MIT License.

## Author

Oscar — Hermes Community
