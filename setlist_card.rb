#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds a self-contained HTML "setlist card" from a single Weekly Catch song list.
#
#   ./setlist_card.rb 2026-07-29.txt
#   ./setlist_card.rb 2026-07-29 -o card.html --light --label "CHILLFILTR"

require 'cgi'
require 'date'
require 'erb'
require 'optparse'
require 'uri'
require_relative 'setlist'

# --- presentation helpers ----------------------------------------------------

def h(str) = CGI.escapeHTML(str.to_s)

def search_url(service, query)
  q = URI.encode_www_form_component(query)
  case service
  when :youtube   then "https://www.youtube.com/results?search_query=#{q}"
  when :spotify   then "https://open.spotify.com/search/#{q}"
  when :bandcamp  then "https://bandcamp.com/search?q=#{q}"
  end
end

def link_kind(url)
  host = begin
    URI.parse(url).host.to_s.sub(/\Awww\./, '')
  rescue URI::InvalidURIError
    ''
  end
  case host
  when /spinitron/ then 'Spinitron playlist'
  when /mixcloud/  then 'Listen on Mixcloud'
  when /youtube|youtu\.be/ then 'Watch on YouTube'
  else host.empty? ? 'Link' : host
  end
end

def mixcloud_url(setlist)
  setlist.links.find { |url| url =~ /mixcloud/ }
end

# The widget iframe wants the show's path, URL-encoded, as its "feed" param.
def mixcloud_feed(url)
  path = URI.parse(url).path
  URI.encode_www_form_component(path)
rescue URI::InvalidURIError
  nil
end

def pretty_date(str)
  Date.parse(str).strftime('%B %-d, %Y')
rescue ArgumentError, TypeError
  str
end

def catalog_number(setlist)
  digits = setlist.date.to_s.gsub(/\D/, '')
  digits.empty? ? 'WC-000' : "WC-#{digits}"
end

def runtime_label(setlist)
  last = setlist.tracks.map(&:cue_seconds).compact.max
  return nil unless last
  hours, minutes = last / 3600, (last % 3600) / 60
  hours.positive? ? "#{hours}h #{minutes}m+" : "#{minutes}m+"
end

# --- template ----------------------------------------------------------------

TEMPLATE = <<~'HTML'
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= h(setlist.show) %><%= setlist.date ? " — #{h(pretty_date(setlist.date))}" : '' %></title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;900&family=JetBrains+Mono:wght@400;500&display=swap');

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
  <% if light %>
      --bg: #f6f5f2;
      --surface: #ffffff;
      --surface-2: #efeeea;
      --border: #e0ded7;
      --text: #16161a;
      --muted: #6d6d78;
      --faint: #a3a3ad;
      --accent: #d63a2f;
  <% else %>
      --bg: #0f0f13;
      --surface: #17171e;
      --surface-2: #1d1d26;
      --border: #2a2a38;
      --text: #e8e8f0;
      --muted: #8b8ba6;
      --faint: #5f5f78;
      --accent: #ff5c5c;
  <% end %>
      --radius: 14px;
    }

    html { -webkit-text-size-adjust: 100%; }

    body {
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.45;
      padding: 32px 16px 64px;
      -webkit-font-smoothing: antialiased;
    }

    .card {
      max-width: 820px;
      margin: 0 auto;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      overflow: hidden;
    }

    /* ---- masthead ---- */

    header { padding: 34px 32px 26px; border-bottom: 1px solid var(--border); }

    .imprint {
      display: flex;
      flex-wrap: wrap;
      align-items: baseline;
      gap: 10px;
      font-family: 'JetBrains Mono', ui-monospace, monospace;
      font-size: 11px;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      color: var(--faint);
    }

    .imprint .name { color: var(--accent); font-weight: 500; }
    .imprint .sep { opacity: 0.5; }

    header h1 {
      margin-top: 14px;
      font-size: clamp(30px, 6vw, 52px);
      font-weight: 900;
      letter-spacing: -0.035em;
      line-height: 1.02;
    }

    header .date {
      margin-top: 10px;
      font-size: 15px;
      color: var(--muted);
      letter-spacing: 0.01em;
    }

    .stats {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 20px;
    }

    .stat {
      font-family: 'JetBrains Mono', ui-monospace, monospace;
      font-size: 11px;
      letter-spacing: 0.1em;
      text-transform: uppercase;
      color: var(--muted);
      background: var(--surface-2);
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 5px 12px;
    }

    .stat b { color: var(--text); font-weight: 600; }

    .listen {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 16px;
    }

    .listen a {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      font-size: 13px;
      font-weight: 600;
      text-decoration: none;
      color: var(--text);
      background: var(--surface-2);
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 8px 15px;
      transition: border-color 0.15s ease, color 0.15s ease;
    }

    .listen a::before {
      content: '';
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: var(--accent);
    }

    .listen a:hover { border-color: var(--accent); color: var(--accent); }

    .mixcloud-embed { margin-top: 16px; border-radius: 8px; overflow: hidden; }
    .mixcloud-embed iframe { display: block; width: 100%; height: 60px; border: 0; }

    /* ---- tracklist ---- */

    .tracklist { list-style: none; }

    .track {
      display: grid;
      grid-template-columns: 40px minmax(0, 1fr) auto;
      align-items: baseline;
      gap: 4px 14px;
      padding: 14px 32px;
      border-bottom: 1px solid var(--border);
    }

    .track:last-child { border-bottom: 0; }
    .track:hover { background: var(--surface-2); }

    .num {
      font-family: 'JetBrains Mono', ui-monospace, monospace;
      font-size: 12px;
      font-weight: 500;
      color: var(--faint);
      font-variant-numeric: tabular-nums;
    }

    .meta { min-width: 0; }

    .artist {
      font-size: 12px;
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--accent);
    }

    .title {
      display: block;
      font-size: 17px;
      font-weight: 600;
      letter-spacing: -0.012em;
      color: var(--text);
      text-decoration: none;
      margin-top: 2px;
    }

    a.title:hover { text-decoration: underline; text-underline-offset: 3px; cursor: pointer; }

    .cue {
      font-family: 'JetBrains Mono', ui-monospace, monospace;
      font-size: 12px;
      color: var(--muted);
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
      text-align: right;
    }

    .cue .len { display: block; font-size: 11px; color: var(--faint); margin-top: 3px; }

    /* Unverified cues read as provisional rather than authoritative. */
    .cue.approx { color: var(--faint); font-style: italic; }

    .find {
      grid-column: 2;
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 6px;
    }

    .find a {
      font-family: 'JetBrains Mono', ui-monospace, monospace;
      font-size: 10px;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--faint);
      text-decoration: none;
      border-bottom: 1px solid transparent;
      transition: color 0.15s ease, border-color 0.15s ease;
    }

    .find a:hover { color: var(--accent); border-bottom-color: var(--accent); }

    a:focus-visible, .title:focus-visible {
      outline: 2px solid var(--accent);
      outline-offset: 3px;
      border-radius: 3px;
    }

    footer {
      padding: 22px 32px 26px;
      border-top: 1px solid var(--border);
      font-family: 'JetBrains Mono', ui-monospace, monospace;
      font-size: 11px;
      letter-spacing: 0.1em;
      text-transform: uppercase;
      color: var(--faint);
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      gap: 8px;
    }

    footer a { color: var(--muted); text-decoration: none; }
    footer a:hover { color: var(--accent); }

    @media (max-width: 560px) {
      body { padding: 16px 10px 40px; }
      header { padding: 26px 20px 22px; }
      .track { padding: 13px 20px; grid-template-columns: 30px minmax(0, 1fr) auto; gap: 4px 10px; }
      footer { padding: 18px 20px 22px; }
      .title { font-size: 16px; }
    }

    @media print {
      body { background: #fff; color: #000; padding: 0; }
      .card { border: 0; max-width: none; }
      .track:hover { background: none; }
      .find { display: none; }
      .mixcloud-embed { display: none; }
      .track { break-inside: avoid; padding: 8px 0; }
      header, footer { padding-left: 0; padding-right: 0; }
    }
  </style>
  </head>
  <body>
  <main class="card">
    <header>
      <div class="imprint">
        <span class="name"><%= h(label) %></span>
        <span class="sep">/</span>
        <span><%= h(catalog_number(setlist)) %></span>
        <span class="sep">/</span>
        <span>Compilation</span>
      </div>
      <h1><%= h(headline) %></h1>
      <% if setlist.date %>
      <p class="date"><%= h(pretty_date(setlist.date)) %><%= curator ? " · curated by #{h(curator)}" : '' %></p>
      <% end %>
      <div class="stats">
        <span class="stat"><b><%= setlist.tracks.size %></b> tracks</span>
        <% if (rt = runtime_label(setlist)) %>
        <span class="stat"><b><%= h(rt) %></b> runtime</span>
        <% end %>
      </div>
      <% unless setlist.links.empty? %>
      <nav class="listen">
        <% setlist.links.each do |url| %>
        <a href="<%= h(url) %>" target="_blank" rel="noopener"><%= h(link_kind(url)) %></a>
        <% end %>
      </nav>
      <% end %>
      <% if mc_feed %>
      <div class="mixcloud-embed">
        <iframe id="mixcloud-widget" title="Mixcloud player" allow="autoplay"
          src="https://www.mixcloud.com/widget/iframe/?hide_cover=1&hide_artwork=1&mini=1&light=<%= light ? 1 : 0 %>&feed=<%= mc_feed %>"></iframe>
      </div>
      <% end %>
    </header>

    <ol class="tracklist">
      <% setlist.tracks.each do |track| %>
      <li class="track">
        <span class="num"><%= format('%02d', track.num) %></span>
        <div class="meta">
          <% if track.artist %><span class="artist"><%= h(track.artist) %></span><% end %>
          <% if mc_feed && track.cue_seconds %>
          <a class="title" href="<%= h(mc_url) %>" data-seek="<%= track.cue_seconds.round %>" target="_blank" rel="noopener"><%= h(track.title) %></a>
          <% else %>
          <span class="title"><%= h(track.title) %></span>
          <% end %>
        </div>
        <span class="cue<%= track.approx ? ' approx' : '' %>"<%= track.approx ? ' title="Approximate — not verified against the audio"' : '' %>>
          <%= track.approx ? '~' : '' %><%= h(track.cue || '—') %>
          <% if track.duration_label && !track.duration_approx %><span class="len"><%= h(track.duration_label) %></span><% end %>
        </span>
        <div class="find">
          <a href="<%= h(search_url(:youtube, track.query)) %>" target="_blank" rel="noopener">YouTube</a>
          <a href="<%= h(search_url(:spotify, track.query)) %>" target="_blank" rel="noopener">Spotify</a>
          <a href="<%= h(search_url(:bandcamp, track.query)) %>" target="_blank" rel="noopener">Bandcamp</a>
        </div>
      </li>
      <% end %>
    </ol>

    <footer>
      <span><%= h(label) %> · <%= h(setlist.show) %></span>
      <% if setlist.tracks.any?(&:approx) %>
      <span class="legend">~ approximate cue</span>
      <% end %>
      <span>Support the artists — buy the record</span>
    </footer>
  </main>
  <% if mc_feed %>
  <script src="https://widget.mixcloud.com/media/js/widgetApi.js"></script>
  <script>
    (function () {
      var iframe = document.getElementById('mixcloud-widget');
      if (!iframe || typeof Mixcloud === 'undefined') return;
      var widget = Mixcloud.PlayerWidget(iframe);
      document.querySelectorAll('.title[data-seek]').forEach(function (link) {
        link.addEventListener('click', function (event) {
          event.preventDefault();
          var seconds = parseInt(link.getAttribute('data-seek'), 10);
          widget.ready.then(function () {
            widget.seek(seconds);
            widget.play();
          });
        });
      });
    })();
  </script>
  <% end %>
  </body>
  </html>
HTML

# --- cli ---------------------------------------------------------------------

options = { label: 'CHILLFILTR®', light: false, curator: nil, headline: nil }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} <setlist.txt> [options]"
  opts.on('-o', '--out FILE', 'Output path (default: <input>-card.html)') { |v| options[:out] = v }
  opts.on('-l', '--label NAME', 'Imprint name in the masthead') { |v| options[:label] = v }
  opts.on('-t', '--title TEXT', 'Override the headline') { |v| options[:headline] = v }
  opts.on('-c', '--curator NAME', 'Curator credit under the date') { |v| options[:curator] = v }
  opts.on('--light', 'Light palette instead of dark') { options[:light] = true }
  opts.on('-h', '--help', 'Show this message') { puts opts; exit }
end
parser.parse!

if ARGV.empty?
  warn parser.banner
  exit 1
end

input = ARGV[0]
path = File.exist?(input) ? input : "#{input}.txt"

unless File.exist?(path)
  warn "File not found: #{input}"
  exit 1
end

setlist = SetlistFormat.parse_file(path)

if setlist.tracks.empty?
  warn "No tracks found in #{path}"
  exit 1
end

# Bindings the template reads.
label = options[:label]
light = options[:light]
curator = options[:curator] || setlist.show.to_s[/with\s+(.+)\z/i, 1]
headline = options[:headline] || setlist.show.to_s.sub(/\s*with\s+.+\z/i, '')
mc_url = mixcloud_url(setlist)
mc_feed = mc_url && mixcloud_feed(mc_url)

html = ERB.new(TEMPLATE, trim_mode: '<>').result(binding)
out = options[:out] || "#{File.basename(path, '.*')}-card.html"
File.write(out, html)

puts "Wrote #{out} — #{setlist.tracks.size} tracks#{runtime_label(setlist) ? ", #{runtime_label(setlist)}" : ''}"
