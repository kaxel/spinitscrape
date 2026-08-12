#!/usr/bin/env python3
"""
Generate a weekly picks infographic HTML from a suggestions text file.

Usage:
    python3 generate_infographic.py weekly-suggest---2026-04-09.txt
    python3 generate_infographic.py weekly-suggest---2026-04-09.txt -o my-output.html

Input format (one track per line):
    {number}. {Artist} - {Song} * {Genre} ({Similar Artist})
    {number}. {Artist} - {Song} * {Genre}
"""

import sys
import re
import argparse
from pathlib import Path
from datetime import datetime

# --------------------------------------------------------------------------- #
# Genre → CSS class mapping. Keys are lowercased substrings to match against. #
# --------------------------------------------------------------------------- #
GENRE_COLORS = {
    "lofi":         ("#6c8ebf", "g-lofi"),
    "pop country":  ("#d4a435", "g-country"),
    "country":      ("#d4a435", "g-country"),
    "americana":    ("#c46b3a", "g-americana"),
    "slow funk":    ("#9b59b6", "g-funk"),
    "rock / funk":  ("#e0534a", "g-rockfunk"),
    "rock/funk":    ("#e0534a", "g-rockfunk"),
    "edm":          ("#00bcd4", "g-edm"),
    "experimental": ("#00bcd4", "g-edm"),
    "indie pop":    ("#48b9a0", "g-indiepop"),
    "jazz":         ("#2e8b57", "g-jazzfunk"),
    "heavy rock":   ("#c0392b", "g-heavy"),
    "punk":         ("#f39c12", "g-punk"),
    "folk rock":    ("#6aaa64", "g-folkrock"),
    "indie rock":   ("#5b8dd9", "g-indie"),
    "indie":        ("#5b8dd9", "g-indie"),
    "classic":      ("#8e8ea0", "g-classic"),
}

FALLBACK_PALETTE = [
    "#e74c3c", "#3498db", "#2ecc71", "#9b59b6",
    "#e67e22", "#1abc9c", "#e91e63", "#00bcd4",
]


def genre_color(genre: str, fallback_index: int) -> tuple[str, str]:
    low = genre.lower()
    for key, (color, cls) in GENRE_COLORS.items():
        if key in low:
            return color, cls
    color = FALLBACK_PALETTE[fallback_index % len(FALLBACK_PALETTE)]
    safe_cls = "g-custom-" + re.sub(r"[^a-z0-9]", "", low)[:16]
    return color, safe_cls


def parse_line(line: str) -> dict | None:
    """
    Parse a line like:
        1. Skinny Dippers - Please Be Kind, Rewind * Lofi Rock (War on Drugs)
        6. Growth pAInz - Naturally healing * Experimental Pop / EDM
    Returns a dict or None if the line doesn't match.
    """
    line = line.strip()
    if not line:
        return None

    # Strip leading number + dot
    m = re.match(r"^\d+\.\s+(.+)$", line)
    if not m:
        return None
    rest = m.group(1)

    # Split on " * " to get "Artist - Song" and "Genre (Similar)"
    if " * " not in rest:
        return None
    artist_song, genre_similar = rest.split(" * ", 1)

    # Split artist and song on " - "
    if " - " not in artist_song:
        return None
    artist, song = artist_song.split(" - ", 1)

    # Extract similar artist from parentheses at end of genre_similar
    similar = None
    m2 = re.match(r"^(.+?)\s*\((.+)\)\s*$", genre_similar)
    if m2:
        genre = m2.group(1).strip()
        similar = m2.group(2).strip()
    else:
        genre = genre_similar.strip()

    return {
        "artist": artist.strip(),
        "song": song.strip(),
        "genre": genre,
        "similar": similar,
    }


def extract_date(filepath: Path) -> str:
    """Try to pull a date from the filename, e.g. weekly-suggest---2026-04-09.txt"""
    m = re.search(r"(\d{4}-\d{2}-\d{2})", filepath.name)
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%Y-%m-%d")
            return dt.strftime("%B %-d, %Y")  # e.g. April 9, 2026
        except ValueError:
            pass
    return ""


def card_html(track: dict, index: int, color: str, css_class: str) -> str:
    num_label = f"TRACK {index:02d}"
    similar_html = (
        f'<span class="similar">{track["similar"]}</span>'
        if track["similar"] else ""
    )
    song_escaped = track["song"].replace('"', "&quot;").replace("'", "&#39;")
    artist_escaped = track["artist"].replace("&", "&amp;")
    genre_escaped = track["genre"].replace("&", "&amp;")

    return f"""
  <div class="card {css_class}" style="--genre-color:{color}">
    <div class="card-num">{num_label}</div>
    <div class="card-artist">{artist_escaped}</div>
    <div class="card-song">&#8220;{song_escaped}&#8221;</div>
    <div class="card-meta">
      <span class="badge">{genre_escaped}</span>
      {similar_html}
    </div>
  </div>"""


HTML_TEMPLATE = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>The Weekly Catch — {date}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700;900&display=swap');

  *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}

  :root {{
    --bg: #0f0f13;
    --surface: #17171e;
    --border: #2a2a38;
    --text: #e8e8f0;
    --muted: #7a7a96;
    --accent: #ff5c5c;
  }}

  body {{
    font-family: 'Inter', system-ui, sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
    padding: 20px 16px;
  }}

  header {{
    text-align: center;
    margin-bottom: 20px;
  }}

  header .label {{
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--muted);
    margin-bottom: 8px;
  }}

  header h1 {{
    font-size: clamp(28px, 5vw, 48px);
    font-weight: 900;
    letter-spacing: -0.03em;
    line-height: 1;
    color: #fff;
  }}

  header h1 span {{ color: var(--accent); }}

  header .subtitle {{
    margin-top: 10px;
    font-size: 13px;
    color: var(--muted);
    letter-spacing: 0.06em;
  }}

  .divider {{
    width: 48px;
    height: 3px;
    background: var(--accent);
    margin: 10px auto;
    border-radius: 2px;
  }}

  .grid {{
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
    gap: 10px;
    max-width: 1100px;
    margin: 0 auto;
  }}

  .card {{
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 12px 14px;
    position: relative;
    overflow: hidden;
  }}

  .card::before {{
    content: '';
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 3px;
    background: var(--genre-color, #555);
  }}

  .card-num {{
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.12em;
    color: var(--muted);
    margin-bottom: 3px;
  }}

  .card-artist {{
    font-size: 20px;
    font-weight: 700;
    color: #fff;
    line-height: 1.2;
    margin-bottom: 2px;
  }}

  .card-song {{
    font-size: 18px;
    font-weight: 400;
    color: #b0b0cc;
    font-style: italic;
    margin-bottom: 8px;
    line-height: 1.3;
  }}

  .card-meta {{
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }}

  .badge {{
    display: inline-flex;
    align-items: center;
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    background: transparent;
    border: 1px solid var(--genre-color, #555);
    color: var(--genre-color, #555);
  }}

  .similar {{
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 13px;
    color: var(--muted);
    font-weight: 500;
  }}

  .similar::before {{
    content: '≈';
    font-size: 13px;
    color: var(--genre-color, #555);
  }}

  footer {{
    text-align: center;
    margin-top: 20px;
    font-size: 11px;
    color: var(--muted);
    letter-spacing: 0.08em;
  }}

  @media print {{
    body {{ background: #fff; color: #111; padding: 16px; }}
    .card {{ background: #f8f8f8; border-color: #ddd; break-inside: avoid; }}
    .card-artist {{ color: #111; }}
    .card-song {{ color: #444; }}
  }}
</style>
</head>
<body>

<header>
  <div class="label">Weekly Music Picks</div>
  <h1>The <span>Weekly</span> Catch</h1>
  <div class="divider"></div>
  <div class="subtitle">{date} &nbsp;·&nbsp; KSKQ</div>
</header>

<div class="grid">
{cards}
</div>

<footer>{count} tracks &nbsp;·&nbsp; The Weekly Catch &nbsp;·&nbsp; KSKQ &nbsp;·&nbsp; {date}</footer>

</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser(description="Generate weekly picks infographic")
    parser.add_argument("input", help="Path to the weekly suggestions .txt file")
    parser.add_argument("-o", "--output", help="Output HTML file (default: auto-named)")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: {input_path} not found", file=sys.stderr)
        sys.exit(1)

    date_str = extract_date(input_path)
    lines = input_path.read_text(encoding="utf-8").splitlines()

    tracks = []
    for line in lines:
        parsed = parse_line(line)
        if parsed:
            tracks.append(parsed)

    if not tracks:
        print("No tracks parsed. Check that the file matches the expected format.", file=sys.stderr)
        sys.exit(1)

    cards = ""
    for i, track in enumerate(tracks, start=1):
        color, css_class = genre_color(track["genre"], i)
        cards += card_html(track, i, color, css_class)

    html = HTML_TEMPLATE.format(
        date=date_str or "Weekly Picks",
        cards=cards,
        count=len(tracks),
    )

    if args.output:
        out_path = Path(args.output)
    else:
        # e.g. weekly-picks-2026-04-09.html
        stem = re.sub(r"weekly-suggest-*", "weekly-picks", input_path.stem)
        out_path = input_path.parent / f"{stem}.html"

    out_path.write_text(html, encoding="utf-8")
    print(f"Generated: {out_path}  ({len(tracks)} tracks)")


if __name__ == "__main__":
    main()
