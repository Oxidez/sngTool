---
name: xngTool
description: "SearXNG Web Search & Extract — compact results via local SearXNG instance, zero API keys."
version: 1.1.0
author: Oscar
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [Web, Search, Extract, SearXNG]
---

# xngTool

A standalone skill for web search and web extraction using a local SearXNG instance. No external API keys needed — all data stays local.

## When to Use

Use xngTool for:
- **Current information** — events, news, status (things that change over time)
- **Documentation lookup** — finding the latest docs, changelogs, API references
- **Technical research** — libraries, frameworks, packages, version compatibility
- **Web references** — URLs, links, citations to include in responses
- **Verification** — confirming a fact that might have changed since training
- **Discovery** — finding new resources, repos, articles, tutorials

## When to Avoid

Do NOT use xngTool for:
- **Normal reasoning** — logic, math, code generation, analysis
- **Tasks where internal knowledge is sufficient** — definitions, patterns, algorithms, syntax
- **Simple factual recall** — dates you know, well-established facts
- **Quick questions** — if you can answer it confidently, no need to search

**Rule of thumb:** If you can answer it from memory, don't search. Search when you need fresh, external, or uncertain information.

## Search

Execute a web search using SearXNG.

### Command

```bash
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "your query" --json
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--limit N` | Max results to return | `5` |
| `--format compact\|rich` | Output verbosity | `compact` |
| `--language LANG` | ISO 639-1 code (`en`, `de`, `fr`, `es`, ...) | `en` |
| `--time-range day\|week\|month\|year` | Filter results by age | _(none)_ |
| `--timeout N` | Request timeout in seconds | `10` |
| `--json` | Raw JSON output (recommended for agents) | off |

### Examples

```bash
# Basic search
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "python asyncio tutorial" --json

# Limit to 3 results from the past week
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "rust 2026 release" --limit 3 --time-range week --json

# German-language results
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py search "kubernetes deployment" --language de --json
```

### Direct SearXNG API

You can also query SearXNG directly via `curl`:

```bash
curl -G "http://127.0.0.1:8888/search" \
  --data-urlencode "q=python asyncio tutorial" \
  --data-urlencode "format=json" \
  --data-urlencode "language=en"
```

### Success Output

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

### Error Output

```json
{
  "success": false,
  "error": "ConnectionRefused: cannot reach SearXNG at http://127.0.0.1:8888",
  "hint": "Ensure SearXNG is running and search.formats includes json in settings.yml"
}
```

### Output Rules

When using search results:

1. **Prefer compact results** — title, URL, short description (200 chars max)
2. **Limit to 5 results** unless more are specifically required
3. **Avoid returning full HTML pages** unless explicitly needed
4. **Use `--json` flag** for agent sessions — returns directly parsable JSON
5. **Cite sources** — always include the URL when referencing search results
6. **Handle failures gracefully** — if `success` is `false`, report the error; do not retry more than once

## Best Practices

- Search before extracting content from web pages.
- Extract only pages that are relevant to the current task.
- Prefer one targeted search over multiple broad searches.
- Keep search limits low unless comprehensive coverage is required.
- Use the `compact` format whenever possible to minimize token usage.
- Cite the original source URLs when using extracted information.

## Extract

Extract clean text content from one or more web pages.

### Command

```bash
# Single URL
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py extract "https://example.com" --json

# Multiple URLs (space-separated)
python3 ~/.hermes/skills/xngTool/scripts/xngTool.py extract "https://a.com" "https://b.com" --json
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--max-length N` | Max output chars per page | `5000` |
| `--timeout N` | Per-page request timeout in seconds | `15` |
| `--json` | Raw JSON output (recommended for agents) | off |

### Success Output

```json
{
  "success": true,
  "results": [
    {
      "url": "https://example.com/page",
      "title": "Page Title",
      "content": "Cleaned text content...",
      "success": true
    },
    {
      "url": "https://other.com/broken",
      "title": null,
      "content": null,
      "success": false,
      "error": "HTTP 404: Not Found"
    }
  ]
}
```

> **Note:** When extracting multiple URLs, individual pages can fail independently.
> The top-level `success` is `true` as long as the command itself ran — check each
> result's `success` field for per-page status.

### Error Output (command-level failure)

```json
{
  "success": false,
  "error": "No URLs provided",
  "hint": "Pass at least one URL as a positional argument"
}
```

## Configuration

The skill resolves the SearXNG base URL in this order:

1. `SEARXNG_URL` environment variable
2. `~/.hermes/config.yaml` under `web.searxng_url`
3. Fallback: `http://127.0.0.1:8888`

### SearXNG settings.yml Requirement

Your SearXNG instance **must** have the JSON format enabled:

```yaml
search:
  formats:
    - html
    - json
```

Without this, all API calls will return `403 Forbidden`.

## Usage from Python

```python
import sys
from pathlib import Path

# Robust path resolution — works regardless of caller location
SKILL_DIR = Path.home() / ".hermes" / "skills" / "xngTool"
sys.path.insert(0, str(SKILL_DIR / "scripts"))

from xngTool import xngToolClient

client = xngToolClient()  # reads SEARXNG_URL or config.yaml automatically

# Search — returns compact structured data
results = client.search("python asyncio tutorial", limit=5)

# Extract — single page
page = client.extract("https://example.com/article")

# Extract — multiple pages
pages = client.extract(["https://a.com", "https://b.com"], max_length=3000)
```

## Token Optimization

This skill is designed to minimize token usage in LLM contexts:

- **Search**: Returns only title, URL, and a short description (max 200 chars) per result
- **Extract**: Strips `<script>`, `<style>`, `<nav>`, `<footer>`, `<header>`, `<aside>` before text conversion
- **Truncation**: Smart head + tail truncation for large pages to preserve intro and conclusion
- **Compact format**: Default output avoids verbose metadata
- **5 results max**: Default search limit keeps context small

## Rate Limiting & Concurrency

- Avoid more than **3 concurrent requests** to the SearXNG instance.
- If performing multiple searches in a loop, insert a **1-second delay** between calls.
- SearXNG may throttle or block excessive requests — respect `429` responses and back off.

## Requirements

- **Python 3.9+**
- **requests** library (`pip install requests`)
- A running SearXNG instance with JSON format enabled (see Configuration above)
- SearXNG URL configured via env var or `~/.hermes/config.yaml`

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ConnectionRefused` | SearXNG not running | Start the container/service |
| `403 Forbidden` | JSON format disabled | Add `json` to `search.formats` in `settings.yml` |
| Empty results | Query too narrow or time-range too strict | Broaden query or remove `--time-range` |
| Timeout on extract | Target page is slow or huge | Increase `--timeout` or reduce `--max-length` |
| `ModuleNotFoundError: requests` | Missing dependency | `pip install requests` |
