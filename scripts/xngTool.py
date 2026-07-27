#!/usr/bin/env python3
"""
xngTool — SearXNG Web Search & Extract for Hermes Agent

A standalone skill that reads the SearXNG URL from Hermes config.yaml
and provides compact web search and web extract functionality.

Usage:
    python3 xngTool.py search "your query" [options]
    python3 xngTool.py extract URL1 [URL2 ...] [options]

Options:
    --limit N          Max results for search (default: 5)
    --format FMT       Output format: compact|rich (default: compact)
    --language LANG    Language code (default: auto)
    --max-length N     Max chars for extract output (default: 5000)
    --json             Raw JSON output (for tool integration)
    --help             Show this help message

Author: Oscar
License: MIT
"""

import os
import sys
import re
import json
import html as html_mod
import urllib.request
import urllib.parse
from urllib.error import URLError, HTTPError

# ─── Config Loading ──────────────────────────────────────────────────────────

def _load_config():
    """Load config.yaml and return parsed dict (no secrets)."""
    try:
        import yaml
        config_path = os.path.join(os.path.expanduser("~"), ".hermes", "config.yaml")
        if os.path.exists(config_path):
            with open(config_path, "r", encoding="utf-8") as f:
                return yaml.safe_load(f) or {}
    except Exception:
        pass
    return {}

def _get_searxng_url():
    """Read SearXNG URL from config.yaml web.searxng_url or env var."""
    env_url = os.environ.get("SEARXNG_URL", "").rstrip("/")
    if env_url:
        return env_url
    config = _load_config()
    web = config.get("web", {}) or {}
    url = web.get("searxng_url", "")
    if not url:
        raise ValueError(
            "SearXNG URL not configured. Set SEARXNG_URL env var or "
            "web.searxng_url in ~/.hermes/config.yaml"
        )
    return url.rstrip("/")


# ─── Configuration ────────────────────────────────────────────────────────────

SEARXNG_URL = _get_searxng_url()
SEARXNG_TIMEOUT = int(os.environ.get("SEARXNG_TIMEOUT", "15"))
SEARXNG_LANGUAGE = os.environ.get("SEARXNG_LANGUAGE", "auto")
SEARXNG_SAFESEARCH = int(os.environ.get("SEARXNG_SAFESEARCH", "0"))
SEARXNG_MAX_RESULTS = int(os.environ.get("SEARXNG_MAX_RESULTS", "5"))
SEARXNG_DESC_MAX = int(os.environ.get("SEARXNG_DESC_MAX", "200"))
SEARXNG_EXTRACT_MAX = int(os.environ.get("SEARXNG_EXTRACT_MAX", "5000"))
SEARXNG_EXTRACT_TIMEOUT = int(os.environ.get("SEARXNG_EXTRACT_TIMEOUT", "20"))


class xngToolClient:
    """SearXNG client optimized for Hermes Agent — compact outputs."""

    def __init__(self, url=None, language=None, timeout=None):
        self.url = (url or SEARXNG_URL).rstrip("/")
        self.language = language or SEARXNG_LANGUAGE
        self.timeout = timeout or SEARXNG_TIMEOUT
        if not self.url:
            raise ValueError("SearXNG URL not configured.")

    # ─── Search ───────────────────────────────────────────────────────────
    def search(self, query, limit=None, language=None, time_range=None,
               categories="general", fmt="compact"):
        """
        Search SearXNG — returns compact dict for LLM consumption.

        Returns:
            {
                "success": True,
                "data": {
                    "web": [
                        {"title": "...", "url": "...", "description": "...",
                         "position": 1},
                        ...
                    ]
                }
            }
        """
        limit = limit or SEARXNG_MAX_RESULTS
        language = language or self.language

        params = {
            "q": query,
            "format": "json",
            "language": language,
            "safesearch": SEARXNG_SAFESEARCH,
            "categories": categories,
        }
        if time_range:
            params["time_range"] = time_range

        url = f"{self.url}/search?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url)
        req.add_header("User-Agent", "xngTool/1.0")
        req.add_header("Accept", "application/json")

        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except HTTPError as e:
            return {"success": False, "error": f"SearXNG HTTP {e.code}: {e.reason}"}
        except URLError as e:
            return {"success": False, "error": f"SearXNG connection: {e.reason}"}
        except json.JSONDecodeError:
            return {"success": False, "error": "SearXNG: invalid JSON response"}

        web_results = []
        for i, r in enumerate(data.get("results", [])[:limit]):
            desc = html_mod.unescape(r.get("content", "").strip())
            if len(desc) > SEARXNG_DESC_MAX:
                desc = desc[:SEARXNG_DESC_MAX] + "…"

            entry = {
                "title": r.get("title", "").strip(),
                "url": r.get("url", ""),
                "description": desc,
                "position": i + 1,
            }

            if fmt == "rich":
                if r.get("publishedDate"):
                    entry["publishedDate"] = r["publishedDate"]
                if r.get("engine"):
                    entry["engine"] = r["engine"]
                if r.get("score"):
                    entry["score"] = r["score"]
                if r.get("thumbnail"):
                    entry["thumbnail"] = r["thumbnail"]

            if entry["url"]:
                web_results.append(entry)

        return {"success": True, "data": {"web": web_results}}

    # ─── Extract ──────────────────────────────────────────────────────────
    def extract(self, urls, max_length=None):
        """
        Extract web page content — clean HTML → compact text.

        No external dependencies (stdlib only).
        Strips scripts, styles, nav, footer, header, aside.

        Returns:
            {
                "success": True/False,
                "results": [
                    {"url": "...", "title": "...", "content": "...", "success": True},
                    ...
                ]
            }
        """
        max_length = max_length or SEARXNG_EXTRACT_MAX
        if isinstance(urls, str):
            urls = [urls]

        results = []
        for target_url in urls:
            try:
                req = urllib.request.Request(target_url)
                req.add_header("User-Agent", "Mozilla/5.0 (compatible; xngTool/1.0)")
                with urllib.request.urlopen(req, timeout=SEARXNG_EXTRACT_TIMEOUT) as resp:
                    raw = resp.read()
                    # Try multiple encodings
                    html_content = None
                    for enc in ("utf-8", "latin-1", "cp1252"):
                        try:
                            html_content = raw.decode(enc)
                            break
                        except (UnicodeDecodeError, ValueError):
                            continue
                    if html_content is None:
                        html_content = raw.decode("utf-8", errors="replace")

                # Extract title
                title_match = re.search(
                    r"<title[^>]*>(.*?)</title>", html_content,
                    re.DOTALL | re.IGNORECASE
                )
                title = html_mod.unescape(title_match.group(1).strip()) if title_match else target_url

                # Strip HTML → text
                text = html_content
                for tag in ("script", "style", "nav", "footer", "header", "aside", "noscript"):
                    text = re.sub(
                        rf"<{tag}[^>]*>.*?</{tag}>", "", text,
                        flags=re.DOTALL | re.IGNORECASE
                    )
                text = re.sub(r"<[^>]+>", " ", text)
                text = html_mod.unescape(text)
                text = re.sub(r"\s+", " ", text).strip()

                # Smart truncation
                if len(text) > max_length:
                    half = max_length // 2
                    truncation_text = "\n\n[...content truncated...]\n\n"
                    text = text[:half] + truncation_text + text[-half:]

                results.append({
                    "url": target_url,
                    "title": title,
                    "content": text,
                    "success": True,
                })
            except Exception as e:
                results.append({
                    "url": target_url,
                    "error": str(e)[:200],
                    "success": False,
                })

        has_success = any(r.get("success") for r in results)
        return {"success": has_success, "results": results}


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main():
    import argparse

    parser = argparse.ArgumentParser(
        prog="xngTool",
        description="SearXNG Web Search & Extract for Hermes Agent"
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # search subcommand
    search_parser = subparsers.add_parser("search", help="Execute a web search")
    search_parser.add_argument("query", help="Search query")
    search_parser.add_argument("--limit", type=int, default=5,
                               help="Max results (default: 5)")
    search_parser.add_argument("--format", choices=["compact", "rich"],
                               default="compact", help="Output format")
    search_parser.add_argument("--language", default="auto",
                               help="Language code (default: auto)")
    search_parser.add_argument("--time-range",
                               choices=["day", "week", "month", "year"],
                               help="Filter by time period")
    search_parser.add_argument("--categories", default="general",
                               help="Search categories (default: general)")
    search_parser.add_argument("--json", action="store_true",
                               help="Raw JSON output")
    search_parser.add_argument("--url", help="Override SearXNG URL")

    # extract subcommand
    extract_parser = subparsers.add_parser("extract", help="Extract web page content")
    extract_parser.add_argument("urls", nargs="+", help="URL(s) to extract")
    extract_parser.add_argument("--max-length", type=int, default=5000,
                                help="Max output chars (default: 5000)")
    extract_parser.add_argument("--json", action="store_true",
                                help="Raw JSON output")
    extract_parser.add_argument("--url", help="Override SearXNG URL")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    try:
        client = xngToolClient(url=args.url)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    if args.command == "search":
        result = client.search(
            args.query,
            limit=args.limit,
            language=args.language,
            time_range=args.time_range,
            categories=args.categories,
            fmt=args.format,
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(format_search(result))

    elif args.command == "extract":
        result = client.extract(args.urls, max_length=args.max_length)
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(format_extract(result))


def format_search(results):
    """Format search results for readable output."""
    if not results.get("success"):
        return f"❌ Error: {results.get('error', 'Unknown')}"
    if not results.get("data", {}).get("web"):
        return "No results found."

    web = results["data"]["web"]
    lines = [f"🔍 {len(web)} result(s)\n"]

    for r in web:
        lines.append(f"{r['position']}. {r['title']}")
        lines.append(f"   🔗 {r['url']}")
        if r.get("description"):
            lines.append(f"   📄 {r['description']}")
        lines.append("")

    return "\n".join(lines)


def format_extract(result):
    """Format extract results for readable output."""
    lines = []
    for page in result.get("results", []):
        if page.get("success"):
            lines.append(f"# {page['title']}")
            lines.append(page["content"])
        else:
            lines.append(f"❌ {page['url']}: {page.get('error', 'Unknown')}")
        lines.append("---\n")
    return "\n".join(lines)


if __name__ == "__main__":
    main()
