#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds a self-contained HTML "setlist card" from a single Weekly Catch song list.
#
#   ./setlist_card.rb 2026-07-29.txt
#   ./setlist_card.rb 2026-07-29 -o card.html --label "CHILLFILTR" --note "Great set this week"

require 'cgi'
require 'date'
require 'erb'
require 'optparse'
require 'uri'
require_relative 'setlist'
require_relative 'fish_thumbnail'

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

# Same digit string the episode ledger seeds its fish from, so a card and
# its ledger row always draw the same fish.
def fish_seed(setlist)
  digits = setlist.date.to_s.gsub(/\D/, '')
  digits.empty? ? 0 : digits.to_i
end

def runtime_label(setlist)
  last = setlist.tracks.map(&:cue_seconds).compact.max
  return nil unless last
  hours, minutes = last / 3600, (last % 3600) / 60
  hours.positive? ? "#{hours}h #{minutes}m+" : "#{minutes}m+"
end

# A light-touch tag pulled straight from parenthetical text the curator
# already writes into the title — never a guessed genre.
def stamp_tag(title)
  return 'cover' if title =~ /\(.*\bcover\b.*\)/i
  return 'live' if title =~ /\(.*\blive\b.*\)/i
  nil
end

# --- template ----------------------------------------------------------------

TEMPLATE = <<~'HTML'
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= h(setlist.show) %><%= setlist.date ? " — #{h(pretty_date(setlist.date))}" : '' %></title>
  <link rel="shortcut icon" href="/art/weekly_catch.ico">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --paper: #e4e2d2;
      --paper-2: #d9d6c2;
      --navy: #1f2f3a;
      --rust: #b23a2c;
      --ochre: #d99b2b;
      --charcoal: #211f1c;
      --faint: #a39d84;
      --display: Rockwell, 'Roboto Slab', Georgia, 'Times New Roman', serif;
      --body-font: 'Helvetica Neue', Helvetica, Arial, sans-serif;
      --stamp: 'Courier New', ui-monospace, 'SF Mono', monospace;
    }

    html { -webkit-text-size-adjust: 100%; }

    @media (prefers-reduced-motion: reduce) {
      * { animation: none !important; }
    }

    body {
      font-family: var(--body-font);
      background: var(--paper);
      color: var(--charcoal);
      line-height: 1.45;
      margin: 0;
      padding-bottom: 56px;
      -webkit-font-smoothing: antialiased;
    }

    .signal-strip {
      background: var(--navy);
      color: var(--paper);
      font-family: var(--stamp);
      font-size: 11px;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      padding: 8px 24px;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .signal-strip .dot {
      width: 7px; height: 7px; border-radius: 50%; background: var(--ochre);
      animation: pulse 1.8s ease-in-out infinite;
      flex-shrink: 0;
    }
    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.35; } }

    .breadcrumb {
      max-width: 760px;
      margin: 0 auto;
      padding: 22px 24px 0;
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 12px;
      flex-wrap: wrap;
    }
    .breadcrumb .word {
      font-family: var(--display); font-weight: 900; text-transform: uppercase; font-size: 14px; letter-spacing: 0.01em;
    }
    .breadcrumb a {
      font-family: var(--stamp); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase;
      color: var(--navy); text-decoration: none; border-bottom: 1px solid transparent;
    }
    .breadcrumb a:hover { border-bottom-color: var(--navy); }

    .bill {
      max-width: 760px;
      margin: 20px auto 0;
      border: 3px solid var(--navy);
    }

    .bill-head { position: relative; background: var(--navy); color: var(--paper); padding: 32px 36px 26px; }

    .stamp-mark {
      position: absolute; top: 22px; right: 28px;
      width: 84px; height: 84px;
      border: 1px dashed var(--ochre); border-radius: 3px; overflow: hidden;
      transform: rotate(8deg);
    }
    .stamp-mark svg { display: block; width: 100%; height: 100%; }

    .imprint {
      font-family: var(--stamp); font-size: 10.5px; letter-spacing: 0.14em; text-transform: uppercase;
      color: var(--ochre); display: flex; gap: 8px; flex-wrap: wrap; font-weight: 700;
    }
    .imprint .sep { opacity: 0.55; }

    .bill-head h1 {
      font-family: var(--display); font-weight: 900; text-transform: uppercase;
      font-size: clamp(30px, 6vw, 46px); margin: 12px 0 6px; letter-spacing: 0.005em; line-height: 1.02;
    }

    .bill-head .date { font-family: var(--stamp); font-size: 12px; letter-spacing: 0.05em; color: #cfd4d1; margin: 0 0 18px; }

    .stamp-row { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 18px; }
    .stamp-chip {
      font-family: var(--stamp); font-size: 10.5px; letter-spacing: 0.08em; text-transform: uppercase;
      border: 1px dashed var(--ochre); color: var(--ochre); padding: 5px 12px; border-radius: 2px;
    }
    .stamp-chip b { color: var(--paper); }

    .listen { display: flex; gap: 10px; flex-wrap: wrap; }
    .listen a {
      font-family: var(--stamp); font-weight: 700; font-size: 11px; letter-spacing: 0.06em; text-transform: uppercase;
      color: var(--navy); background: var(--ochre); padding: 8px 14px; text-decoration: none; border-radius: 2px;
      transition: opacity 0.15s ease;
    }
    .listen a:hover { opacity: 0.85; }

    .mixcloud-embed { margin-top: 18px; border-radius: 3px; overflow: hidden; border: 1px solid rgba(217,155,43,0.4); }
    .mixcloud-embed iframe { display: block; width: 100%; height: 60px; border: 0; }

    .dj-note {
      margin: 22px 36px 0; padding: 16px 20px; border-left: 3px solid var(--rust); background: var(--paper-2);
    }
    .dj-note .who { font-family: var(--stamp); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--rust); font-weight: 700; margin-bottom: 6px; }
    .dj-note p { margin: 0; font-family: var(--display); font-style: italic; font-size: 14.5px; line-height: 1.5; }

    /* ---- tracklist ---- */

    .tracklist { list-style: none; margin: 22px 0 0; padding: 0; }

    .track {
      display: grid;
      grid-template-columns: 34px minmax(0, 1fr) auto;
      align-items: baseline;
      gap: 4px 16px;
      padding: 13px 36px;
      border-top: 1px dashed var(--faint);
    }

    .track:hover { background: var(--paper-2); }

    .num {
      font-family: var(--stamp); font-weight: 700; font-size: 13px; color: var(--rust);
      font-variant-numeric: tabular-nums;
    }

    .meta { min-width: 0; }
    .meta-top { display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }

    .artist {
      font-family: var(--display); font-weight: 900; text-transform: uppercase;
      font-size: 13px; letter-spacing: 0.01em;
    }

    .stamp-tag {
      font-family: var(--stamp); font-size: 9.5px; letter-spacing: 0.08em; text-transform: uppercase;
      color: var(--navy); border: 1px solid var(--navy); padding: 1px 7px; border-radius: 2px;
    }

    .title {
      display: block;
      font-size: 15px;
      color: #3a362c;
      text-decoration: none;
      margin-top: 2px;
    }

    a.title:hover { text-decoration: underline; text-underline-offset: 3px; cursor: pointer; color: var(--rust); }

    .cue {
      font-family: var(--stamp);
      font-size: 12px;
      color: #55503f;
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
      text-align: right;
    }

    .cue .len { display: block; font-size: 10.5px; color: var(--faint); margin-top: 3px; }

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
      font-family: var(--stamp);
      font-size: 10px;
      letter-spacing: 0.1em;
      text-transform: uppercase;
      color: var(--faint);
      text-decoration: none;
      border-bottom: 1px solid transparent;
      transition: color 0.15s ease, border-color 0.15s ease;
    }

    .find a:hover { color: var(--rust); border-bottom-color: var(--rust); }

    a:focus-visible, .title:focus-visible {
      outline: 2px solid var(--rust);
      outline-offset: 3px;
      border-radius: 2px;
    }

    .bill-foot {
      position: relative;
      margin-top: 6px;
      padding: 20px 36px 18px;
      font-family: var(--stamp); font-size: 10.5px; letter-spacing: 0.06em; text-transform: uppercase;
      color: #55503f; display: flex; justify-content: space-between; flex-wrap: wrap; gap: 8px;
    }
    .bill-foot::before {
      content: "";
      position: absolute; top: 0; left: 0; right: 0; height: 12px;
      background-image: radial-gradient(circle at 10px 0, transparent 6px, var(--paper) 6.5px);
      background-size: 20px 12px;
      background-repeat: repeat-x;
      background-color: var(--navy);
    }

    .bill-foot a { color: inherit; text-decoration: none; }
    .bill-foot a:hover { color: var(--rust); }

    @media (max-width: 560px) {
      .breadcrumb { padding: 18px 20px 0; }
      .bill { margin-top: 14px; }
      .bill-head { padding: 24px 20px 20px; }
      .stamp-mark { width: 64px; height: 64px; top: 18px; right: 18px; }
      .dj-note { margin: 18px 20px 0; }
      .track { padding: 12px 20px; grid-template-columns: 24px minmax(0, 1fr) auto; gap: 4px 10px; }
      .bill-foot { padding: 18px 20px 16px; }
      .title { font-size: 14px; }
    }

    @media print {
      body { background: #fff; padding: 0; }
      .signal-strip, .breadcrumb, .find, .mixcloud-embed { display: none; }
      .bill { border-width: 1px; max-width: none; margin: 0; }
      .track:hover { background: none; }
      .track { break-inside: avoid; padding: 8px 0; }
      .bill-head, .dj-note, .bill-foot { padding-left: 0; padding-right: 0; }
    }
  </style>
  </head>
  <body>
  <div class="signal-strip"><span class="dot"></span> on air &middot; kskq 89.5 fm &middot; ashland, or</div>

  <div class="breadcrumb">
    <span class="word">The Weekly Catch</span>
    <a href="/episodes.html">&larr; All Episodes</a>
  </div>

  <main class="bill">
    <div class="bill-head">
      <div class="stamp-mark"><%= FishThumbnail.svg(fish_seed(setlist)) %></div>
      <div class="imprint">
        <span class="name"><%= h(label) %></span>
        <span class="sep">/</span>
        <span><%= h(catalog_number(setlist)) %></span>
        <span class="sep">/</span>
        <span>Compilation</span>
      </div>
      <h1><%= h(headline) %></h1>
      <% if setlist.date %>
      <p class="date"><%= h(pretty_date(setlist.date)) %><%= curator ? " &middot; curated by #{h(curator)}" : '' %></p>
      <% end %>
      <div class="stamp-row">
        <span class="stamp-chip"><b><%= setlist.tracks.size %></b> tracks</span>
        <% if (rt = runtime_label(setlist)) %>
        <span class="stamp-chip"><b><%= h(rt) %></b> runtime</span>
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
          src="https://www.mixcloud.com/widget/iframe/?hide_cover=1&hide_artwork=1&mini=1&light=1&feed=<%= mc_feed %>"></iframe>
      </div>
      <% end %>
    </div>

    <% if note %>
    <div class="dj-note">
      <div class="who">Krister Says</div>
      <p>&ldquo;<%= h(note) %>&rdquo;</p>
    </div>
    <% end %>

    <ol class="tracklist">
      <% setlist.tracks.each do |track| %>
      <li class="track">
        <span class="num"><%= format('%02d', track.num) %></span>
        <div class="meta">
          <div class="meta-top">
            <% if track.artist %><span class="artist"><%= h(track.artist) %></span><% end %>
            <% if (tag = stamp_tag(track.title)) %><span class="stamp-tag"><%= h(tag) %></span><% end %>
          </div>
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

    <div class="bill-foot">
      <span><%= h(label) %> &middot; <%= h(setlist.show) %></span>
      <% if setlist.tracks.any?(&:approx) %>
      <span class="legend">~ approximate cue</span>
      <% end %>
      <span>Support the artists &mdash; buy the record</span>
    </div>
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

options = { label: 'CHILLFILTR®', curator: nil, headline: nil, note: nil }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} <setlist.txt> [options]"
  opts.on('-o', '--out FILE', 'Output path (default: <input>-card.html)') { |v| options[:out] = v }
  opts.on('-l', '--label NAME', 'Imprint name in the masthead') { |v| options[:label] = v }
  opts.on('-t', '--title TEXT', 'Override the headline') { |v| options[:headline] = v }
  opts.on('-c', '--curator NAME', 'Curator credit under the date') { |v| options[:curator] = v }
  opts.on('-n', '--note TEXT', "\"Krister Says\" pull-quote above the tracklist") { |v| options[:note] = v }
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
note = options[:note]
curator = options[:curator] || setlist.show.to_s[/with\s+(.+)\z/i, 1]
headline = options[:headline] || setlist.show.to_s.sub(/\s*with\s+.+\z/i, '')
mc_url = mixcloud_url(setlist)
mc_feed = mc_url && mixcloud_feed(mc_url)

html = ERB.new(TEMPLATE, trim_mode: '<>').result(binding)
out = options[:out] || "#{File.basename(path, '.*')}-card.html"
File.write(out, html)

puts "Wrote #{out} — #{setlist.tracks.size} tracks#{runtime_label(setlist) ? ", #{runtime_label(setlist)}" : ''}"
