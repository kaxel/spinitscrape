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

SOURCE_DIR = __dir__
OUT_PATH = File.expand_path('../chillonrails/db/data/weekly_catch_episodes.json', SOURCE_DIR)

# A line looks like an elapsed-time cue if, once a trailing "~" is stripped,
# it's built only from digits/colons/h/m/s (e.g. "1:55", "1:00:00", "1h09m05s").
# See memory: these cues are frequently wrong and are NOT needed for a plain
# tracklist post, so they're parsed only to be discarded.
TIMESTAMP_RE = /\A~?\d[\dhms:]*\z/

def timestamp?(str)
  TIMESTAMP_RE.match?(str.strip)
end

# "12. Artist - Song - 1:23:45" / "   Artist - Song - 1:23:45" (no number,
# a manually-inserted line) -> ["Artist", "Song"]. Splits on the FIRST " - "
# only, so a song title that itself contains " - " stays intact; the cue
# (if present as the last " - "-delimited part and timestamp-shaped) is
# dropped rather than trusted.
def parse_track_line(line)
  text = line.strip.sub(/\A\d+[.\t]\s*/, '')
  return nil if text.empty?

  parts = text.split(' - ')
  parts.pop if parts.size > 1 && timestamp?(parts.last)
  return nil if parts.size < 2

  artist = parts.first.strip
  song = parts[1..].join(' - ').strip
  # Catches a rarer source typo: a cue glued directly onto the song with no
  # " - " before it at all (e.g. "Rose and Thorn 38:28"), which the split
  # above can't see since there's no delimiter to split on.
  song = song.sub(/\s+~?\d{1,2}:\d{2}(:\d{2})?\s*\z/, '').strip
  return nil if artist.empty? || song.empty?

  { artist: artist, song: song }
end

def parse_episode(base_txt_path)
  lines = File.readlines(base_txt_path, encoding: 'UTF-8').map(&:chomp)

  date_line = lines.find { |l| l.start_with?('Date:') }
  url_line = lines.find { |l| l.start_with?('URL:') }
  date = Date.parse(date_line.sub('Date:', '').strip)
  urls = url_line.to_s.sub('URL:', '').split(',').map(&:strip)
  mixcloud_url = urls.find { |u| u.include?('mixcloud.com') }

  # Prefer the dedicated *-tracklist.txt export when one exists (clean,
  # consistently formatted); fall back to parsing the base .txt's own
  # "Tracks:" section for older episodes that predate it.
  date_str = date.strftime('%Y-%m-%d')
  tracklist_path = File.join(SOURCE_DIR, "#{date_str}-tracklist.txt")

  track_lines =
    if File.exist?(tracklist_path)
      File.readlines(tracklist_path, encoding: 'UTF-8')
    else
      idx = lines.index { |l| l.start_with?('====') }
      idx ? lines[(idx + 1)..] : []
    end

  tracks = track_lines.filter_map { |l| parse_track_line(l) }

  { date: date_str, mixcloud_url: mixcloud_url, tracks: tracks }
end

base_files = Dir.glob(File.join(SOURCE_DIR, '[0-9]' * 4 + '-' + '[0-9]' * 2 + '-' + '[0-9]' * 2 + '.txt')).sort

episodes = base_files.map { |path| parse_episode(path) }
episodes.reject! { |e| e[:tracks].empty? }

FileUtils.mkdir_p(File.dirname(OUT_PATH))
File.write(OUT_PATH, JSON.pretty_generate(episodes))

puts "Wrote #{OUT_PATH}"
puts "#{episodes.size} episodes, #{episodes.sum { |e| e[:tracks].size }} tracks total"
puts "#{episodes.count { |e| e[:mixcloud_url] }} with a Mixcloud link, #{episodes.count { |e| !e[:mixcloud_url] }} without"
