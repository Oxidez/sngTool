---
name: xngTool
description: "SearXNG Web Search & Extract — compact results via local SearXNG instance, zero API keys."
version: 1.0.0
author: Oscar
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Web, Search, Extract, SearXNG]
---

# xngTool

A standalone skill for web search and web extraction using a local SearXNG instance. No external API keys needed — all data stays local.

## Commands

### xngTool-search

Execute a web search using SearXNG.

```bash
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "your query" --json
```

Options:
- `--limit N` — max results (default: 5)
- `--format compact|rich` — output format (default: compact)
- `--language LANG` — language code (default: auto)
- `--time-range day|week|month|year` — filter by time
- `--json` — raw JSON output

### xngTool-extract

Extract content from one or more web pages.

```bash
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py extract "https://example.com" --json
```

Options:
- `--max-length N` — max output chars (default: 5000)
- `--json` — raw JSON output

## Backend

The skill reads the SearXNG URL from `~/.hermes/config.yaml` under `web.searxng_url`, or from the `SEARXNG_URL` environment variable.

## Usage from Python

```python
import sys
sys.path.insert(0, str(Path(__file__).parent / "scripts"))
from xngTool import xngToolClient

client = xngToolClient()

# Search — compact results
results = client.search("dragon ball z villains", limit=5)

# Extract — clean page content
page = client.extract("https://example.com/article")
```

## Output Format

- Search returns: `{"success": true, "data": {"web": [{"title", "url", "description", "position"}]}}`
- Extract returns: `{"success": true, "results": [{"url", "title", "content", "success"}]}`

## Token Optimization

- Search: compact results only (title, URL, 200 chars max description)
- Extract: HTML → plain text, strips nav/footer/scripts, smart truncation
- JSON output: directly parsable, no verbose markdown

## Requirements

- Python 3.6+
- A running SearXNG instance with JSON format enabled (`settings.yml` → `search.formats: [html, json]`)
- SearXNG URL configured in `~/.hermes/config.yaml` or `SEARXNG_URL` env var

## SearXNG Configuration

Your SearXNG instance must have the JSON format enabled. In `settings.yml`:

```yaml
search:
  formats:
    - html
    - json
```
