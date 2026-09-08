#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Parses the weekly `.txt` tracklist exports in this directory into a JSON
# manifest that chillonrails' `weekly_catch:import` rake task turns into real
# Post records on chillfiltr.com. This script only reads local files and
# writes JSON — it never touches a database, so it's safe to run against
# whichever machine happens to have the source .txt files (this one).
#
# Usage:
#   ./export_weekly_catch_to_chillfiltr.rb
#
# Writes db/data/weekly_catch_episodes.json in the sibling chillonrails repo.
# Review the JSON (and the git diff once committed) before deploying and
# running the rake task against production.

require 'json'
require 'date'
require 'fileutils'
require_relative 'fish_thumbnail'

SOURCE_DIR = __dir__
CHILLONRAILS_DIR = File.expand_path('../chillonrails', SOURCE_DIR)
OUT_PATH = File.join(CHILLONRAILS_DIR, 'db/data/weekly_catch_episodes.json')
FISH_DIR = File.join(CHILLONRAILS_DIR, 'public/weekly-catch-fish')

# A line looks like an elapsed-time cue if, once a trailing "~" is stripped,
# it's built only from digits/colons/h/m/s (e.g. "1:55", "1:00:00", "1h09m05s").
# Per memory, these cues are frequently wrong to the *second* — not reliable
# enough to display as fact — but they're exactly what weeklycatch.org's own
# card pages already use to jump the Mixcloud player to a track, where being
# off by a few seconds is a minor, acceptable inconvenience rather than a
# factual error. Used only for that; never shown as text.
TIMESTAMP_RE = /\A~?\d[\dhms:]*\z/

def timestamp?(str)
  TIMESTAMP_RE.match?(str.strip)
end

# "1:55" / "1:00:00" (M:SS or H:MM:SS) / "1h09m05s" -> total seconds, or nil
# if it doesn't match either shape. Ignores a leading "~".
def seconds_from_timestamp(str)
  s = str.strip.sub(/\A~/, '')
  if s.include?(':')
    s.split(':').map(&:to_i).inject(0) { |total, part| total * 60 + part }
  elsif s =~ /\A(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?\z/ && s.match?(/\d/)
    Regexp.last_match(1).to_i * 3600 + Regexp.last_match(2).to_i * 60 + Regexp.last_match(3).to_i
  end
end

# "12. Artist - Song - 1:23:45" / "   Artist - Song - 1:23:45" (no number,
# a manually-inserted line) -> {artist:, song:, seek_seconds:}. Splits on the
# FIRST " - " only, so a song title that itself contains " - " stays intact;
# the cue (if present as the last " - "-delimited part and timestamp-shaped)
# is captured for seeking only, never trusted as displayable text.
def parse_track_line(line)
  text = line.strip.sub(/\A\d+[.\t]\s*/, '')
  return nil if text.empty?

  parts = text.split(' - ')
  seek_seconds = nil
  if parts.size > 1 && timestamp?(parts.last)
    seek_seconds = seconds_from_timestamp(parts.pop)
  end
  return nil if parts.size < 2

  artist = parts.first.strip
  song = parts[1..].join(' - ').strip
  # Catches a rarer source typo: a cue glued directly onto the song with no
  # " - " before it at all (e.g. "Rose and Thorn 38:28"), which the split
  # above can't see since there's no delimiter to split on.
  if (m = song.match(/\s+(~?\d{1,2}:\d{2}(?::\d{2})?)\s*\z/))
    seek_seconds ||= seconds_from_timestamp(m[1])
    song = song.sub(m[0], '').strip
  end
  return nil if artist.empty? || song.empty?

  { artist: artist, song: song, seek_seconds: seek_seconds }
end

# Every Weekly Catch broadcast is uploaded to Mixcloud under the same
# deterministic slug: chillfiltr/weekly-catch-<YYYY-MM-DD>-kskq. Older episode
# .txt files were written before the Mixcloud link was tracked inline, so when
# the source file doesn't carry one we reconstruct the canonical URL from the
# date. (Spot-checked against Mixcloud for every 2026-05 .. 2026-08 episode
# that was missing the inline link — all resolve.)
def canonical_mixcloud_url(date_str)
  "https://www.mixcloud.com/chillfiltr/weekly-catch-#{date_str}-kskq/"
end

def parse_episode(base_txt_path)
  lines = File.readlines(base_txt_path, encoding: 'UTF-8').map(&:chomp)

  date_line = lines.find { |l| l.start_with?('Date:') }
  url_line = lines.find { |l| l.start_with?('URL:') }
  date = Date.parse(date_line.sub('Date:', '').strip)
  urls = url_line.to_s.sub('URL:', '').split(',').map(&:strip)

  date_str = date.strftime('%Y-%m-%d')
  inline_mixcloud_url = urls.find { |u| u.include?('mixcloud.com') }
  mixcloud_url = inline_mixcloud_url || canonical_mixcloud_url(date_str)

  # Prefer the dedicated *-tracklist.txt export when one exists (clean,
  # consistently formatted); fall back to parsing the base .txt's own
  # "Tracks:" section for older episodes that predate it.
  tracklist_path = File.join(SOURCE_DIR, "#{date_str}-tracklist.txt")

  track_lines =
    if File.exist?(tracklist_path)
      File.readlines(tracklist_path, encoding: 'UTF-8')
    else
      idx = lines.index { |l| l.start_with?('====') }
      idx ? lines[(idx + 1)..] : []
    end

  tracks = track_lines.filter_map { |l| parse_track_line(l) }

  # Same deterministic pixel-fish used on weeklycatch.org's own episode
  # ledger — one distinct fish per date, not the same static logo for every
  # post. Written as a static file so Post#image can be a plain URL, same
  # as any other post's image.
  FileUtils.mkdir_p(FISH_DIR)
  fish_path = File.join(FISH_DIR, "#{date_str}.svg")
  File.write(fish_path, FishThumbnail.svg(date_str.delete('-').to_i))

  { date: date_str, mixcloud_url: mixcloud_url, mixcloud_url_derived: inline_mixcloud_url.nil?,
    image_path: "/weekly-catch-fish/#{date_str}.svg", tracks: tracks }
end

base_files = Dir.glob(File.join(SOURCE_DIR, '[0-9]' * 4 + '-' + '[0-9]' * 2 + '-' + '[0-9]' * 2 + '.txt')).sort

episodes = base_files.map { |path| parse_episode(path) }
episodes.reject! { |e| e[:tracks].empty? }

derived = episodes.select { |e| e.delete(:mixcloud_url_derived) }.map { |e| e[:date] }

FileUtils.mkdir_p(File.dirname(OUT_PATH))
File.write(OUT_PATH, JSON.pretty_generate(episodes))

puts "Wrote #{OUT_PATH}"
puts "#{episodes.size} episodes, #{episodes.sum { |e| e[:tracks].size }} tracks total"
puts "All #{episodes.size} episodes have a Mixcloud link."
unless derived.empty?
  puts "#{derived.size} link(s) reconstructed from the canonical slug (no inline URL in the .txt): #{derived.join(', ')}"
  puts "Confirm these resolve on Mixcloud before deploying."
end
