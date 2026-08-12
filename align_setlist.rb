#!/usr/bin/env ruby
# frozen_string_literal: true

# Recovers second-accurate song start times by fingerprint-aligning the original
# track files against the rendered show, using the Spinitron minute as a prior.
#
#   ./align_setlist.rb show.mp3 2026-07-29.txt -L ~/Music/WeeklyCatch
#   ./align_setlist.rb show.mp3 2026-07-08.txt -L ~/Music/WeeklyCatch --write
#
# Tracks with no local copy fall back to bracketed transition detection between
# their fingerprinted neighbours, and are reported as inferred, never as exact.

require 'json'
require 'open3'
require 'optparse'
require 'set'
require_relative 'setlist'

# Chromaprint hop: 1365 samples @ 11025 Hz. Verified empirically against fpcalc
# 1.6.1 over a 3600s baseline (8.076944 fps measured vs 8.076923 theoretical).
FRAME_SEC = 1365.0 / 11025.0
AUDIO_EXT = %w[.mp3 .m4a .flac .wav .aif .aiff .ogg .opus].freeze
CACHE_FILE = '.align_cache.json'

POPCOUNT = Array.new(65_536) { |i| i.to_s(2).count('1') }.freeze

def frames(seconds) = (seconds / FRAME_SEC).round
def seconds(frames) = frames * FRAME_SEC

# --- fingerprinting ----------------------------------------------------------

def fingerprint(path)
  out, err, status = Open3.capture3('fpcalc', '-raw', '-length', '0', path.to_s)
  raise "fpcalc failed on #{path}: #{err.strip}" unless status.success?

  raw = out[/^FINGERPRINT=(.*)$/, 1]
  raise "fpcalc returned no fingerprint for #{path}" if raw.nil? || raw.empty?

  raw.split(',').map { |n| n.to_i & 0xFFFF_FFFF }
end

# Bit-error rate between a needle and the show at a given frame offset, with an
# early bail once we exceed the best score so far.
def score_at(show_fp, needle, pos, ceiling)
  err = 0
  i = 0
  len = needle.size
  while i < len
    v = needle[i] ^ show_fp[pos + i]
    err += POPCOUNT[v & 0xFFFF] + POPCOUNT[(v >> 16) & 0xFFFF]
    return err if err >= ceiling
    i += 1
  end
  err
end

# Best alignment of needle within [lo, hi] frames of the show.
def best_match(show_fp, needle, lo, hi)
  lo = [lo, 0].max
  hi = [hi, show_fp.size - needle.size].min
  return nil if hi < lo

  # A wide search gets a subsampled coarse pass first, then exact rescoring of
  # the top candidates -- a full-resolution sweep of a 2h show is too slow.
  if hi - lo > 4_000
    coarse = needle.each_slice(4).map(&:first)
    scale = needle.size.to_f / coarse.size
    ranked = []
    pos = lo
    while pos <= hi
      ranked << [score_at(show_fp, coarse, pos, Float::INFINITY), pos]
      pos += 2
    end
    # Keep a generous shortlist: the coarse needle is only a quarter of the
    # frames, so the true position can rank well outside the top few.
    candidates = ranked.sort_by(&:first).first(100).flat_map { |(_, p)| ((p - 3)..(p + 3)).to_a }
    candidates = candidates.select { |p| p >= lo && p <= hi }.uniq
  else
    candidates = (lo..hi).to_a
  end

  best_pos = nil
  best_err = Float::INFINITY
  candidates.each do |pos|
    err = score_at(show_fp, needle, pos, best_err)
    if err < best_err
      best_err = err
      best_pos = pos
    end
  end
  return nil if best_pos.nil?

  [best_pos, best_err.to_f / (needle.size * 32)]
end

# Match every excerpt independently and require them to agree; a single window
# landing on a quiet passage then gets outvoted rather than deciding the result.
def align_track(show_fp, ref_fp, centre, radius)
  implied = []
  bers = []

  excerpt_plan(ref_fp.size).each do |(ex_start, ex_len)|
    needle = ref_fp[ex_start, ex_len]
    next if needle.nil? || needle.size < 8

    lo = radius ? centre + ex_start - radius : 0
    hi = radius ? centre + ex_start + radius : show_fp.size
    match = best_match(show_fp, needle, lo, hi)
    next if match.nil?

    pos, ber = match
    implied << (pos - ex_start)
    bers << ber
  end
  return nil if implied.empty?

  # Take the largest cluster of agreeing excerpts rather than demanding they all
  # agree: over a wide search one excerpt can legitimately match elsewhere (a
  # repeated hook, a sample), and it shouldn't veto the other two.
  pairs = implied.zip(bers).sort_by(&:first)
  cluster = pairs
            .map { |(v, _)| pairs.select { |(w, _)| (w - v).abs <= 8 } }
            .max_by { |members| [members.size, -members.map(&:last).min] }

  values = cluster.map(&:first).sort
  { median: values[values.size / 2],
    spread: values.last - values.first,
    ber: cluster.map(&:last).min,
    votes: cluster.size,
    total: implied.size }
end

# Three windows spread across the track, so one landing on a quiet or ambient
# passage can be outvoted by the other two.
def excerpt_plan(total_frames)
  len = frames(15)
  edge = frames(5)
  return [[0, total_frames]] if total_frames <= len

  usable = total_frames - (2 * edge)
  return [[0, len]] if usable < len

  [0.15, 0.45, 0.70].map { |f| [edge + ((usable - len) * f).round, len] }.uniq
end

# --- library index -----------------------------------------------------------

def normalize(str)
  str.to_s
     .unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
     .downcase
     .tr('øðþß', 'odts')
     .gsub(/\b(feat|ft|featuring)\b\.?/, ' ')
     .gsub('&', ' and ')
     .gsub(/[^a-z0-9]+/, ' ')
     .strip
end

def token_set(str)
  normalize(str).split.reject { |t| t == 'the' || t.empty? }.to_set
end

def dice(a, b)
  return 0.0 if a.empty? || b.empty?
  2.0 * (a & b).size / (a.size + b.size)
end

def probe(path)
  out, _, status = Open3.capture3('ffprobe', '-v', 'quiet', '-print_format', 'json',
                                  '-show_format', path.to_s)
  return {} unless status.success?

  json = begin
    JSON.parse(out)
  rescue JSON::ParserError
    nil
  end
  tags = (json&.dig('format', 'tags') || {}).transform_keys(&:downcase)
  {
    'artist' => tags['artist'] || tags['album_artist'],
    'title' => tags['title'],
    'duration' => json&.dig('format', 'duration')&.to_f
  }
end

def build_index(roots, verbose:)
  cache = File.exist?(CACHE_FILE) ? (JSON.parse(File.read(CACHE_FILE)) rescue {}) : {}
  fresh = {}
  entries = []

  files = roots.flat_map do |root|
    Dir.glob(File.join(root, '**', '*')).select do |f|
      File.file?(f) && AUDIO_EXT.include?(File.extname(f).downcase)
    end
  end.uniq

  warn "Indexing #{files.size} audio files..." if verbose

  files.each do |path|
    stat = File.stat(path)
    key = "#{path}|#{stat.mtime.to_i}|#{stat.size}"
    meta = cache[key] || probe(path)
    fresh[key] = meta

    tagged = [meta['artist'], meta['title']].compact.join(' ').strip
    named = File.basename(path, '.*').gsub(/\A\d+[\s._-]+/, '')
    entries << {
      path: path,
      duration: meta['duration'],
      tag_tokens: token_set(tagged),
      name_tokens: token_set(named),
      label: tagged.empty? ? named : tagged
    }
  end

  File.write(CACHE_FILE, JSON.generate(fresh))
  entries
end

def best_library_match(track, index, threshold)
  wanted = token_set(track.query)
  title_wanted = token_set(track.title)

  scored = index.map do |entry|
    score = [dice(wanted, entry[:tag_tokens]), dice(wanted, entry[:name_tokens])].max

    # A prolific artist would otherwise carry a wrong song over the line: every
    # Richy Mitch track scores ~0.71 against every other one on artist tokens
    # alone. Require the title itself to be substantially present.
    if title_wanted.any?
      present = (title_wanted & (entry[:tag_tokens] | entry[:name_tokens])).size
      score = 0.0 if present.to_f / title_wanted.size < 0.5
    end

    [score, entry]
  end

  score, entry = scored.max_by(&:first)
  score && score >= threshold ? [entry, score] : [nil, score || 0.0]
end

# --- bracketed fallback ------------------------------------------------------

# For tracks with no local copy: look for where audio resumes after a gap,
# inside the bracket established by confidently-aligned neighbours.
def silence_ends(show_path, from, to, noise_db, min_dur)
  span = to - from
  return [] if span <= 0

  _, err, = Open3.capture3('ffmpeg', '-v', 'info', '-ss', from.to_s, '-t', span.to_s,
                           '-i', show_path, '-af',
                           "silencedetect=noise=#{noise_db}dB:d=#{min_dur}",
                           '-f', 'null', '-')
  err.scan(/silence_end:\s*([\d.]+)/).flatten.map { |s| from + s.to_f }
end

# Talk-to-music transitions rarely go silent, but they do change spectral
# content sharply. Measuring self-dissimilarity across each point of the show
# fingerprint finds those seams without decoding any audio again.
def novelty_peaks(show_fp, from, to, half: 8)
  lo = [frames(from), half].max
  hi = [frames(to), show_fp.size - half - 1].min
  return [] if hi <= lo

  curve = (lo..hi).map do |i|
    d = 0
    (1..half).each do |k|
      v = show_fp[i - k] ^ show_fp[i + k - 1]
      d += POPCOUNT[v & 0xFFFF] + POPCOUNT[(v >> 16) & 0xFFFF]
    end
    d
  end
  return [] if curve.size < 3

  mean = curve.sum.to_f / curve.size
  sd = Math.sqrt(curve.sum { |v| (v - mean)**2 }.to_f / curve.size)
  return [] if sd.zero?

  peaks = []
  curve.each_with_index do |v, idx|
    next if v < mean + sd
    window = curve[[idx - half, 0].max..(idx + half)]
    peaks << [seconds(lo + idx), (v - mean) / sd] if v >= window.max
  end
  peaks
end

# --- reporting ---------------------------------------------------------------

CONFIDENCE_ORDER = { 'exact' => 0, 'good' => 1, 'bracketed' => 2, 'unresolved' => 3 }.freeze

def classify(spread_frames, ber, votes, total)
  quorum = [total, 3].min
  return 'exact' if votes >= quorum && spread_frames <= 2 && ber <= 0.22
  return 'good' if votes >= 2 && spread_frames <= 8 && ber <= 0.30
  # One excerpt can still be decisive: 0.12 over ~3,900 compared bits is far
  # beyond coincidence. This is the signature of a track aired only in part,
  # where the later excerpts have nothing in the show to match against.
  return 'good' if votes == 1 && ber <= 0.12
  'unresolved'
end

def print_report(results, io: $stdout)
  io.puts
  io.puts format('%-3s %-44s %9s %9s %7s %6s  %s',
                 '#', 'TRACK', 'LOGGED', 'ALIGNED', 'DELTA', 'BER', 'CONFIDENCE')
  io.puts '-' * 96

  results.each do |r|
    label = "#{r[:artist]} - #{r[:title]}"
    label = "#{label[0, 41]}..." if label.length > 44
    delta = r[:aligned] && r[:logged] ? format('%+.1fs', r[:aligned] - r[:logged]) : '—'
    io.puts format('%-3d %-44s %9s %9s %7s %6s  %s',
                   r[:num], label,
                   r[:logged] ? SetlistFormat.format_cue(r[:logged]) : '—',
                   r[:aligned] ? SetlistFormat.format_cue(r[:aligned]) : '—',
                   delta,
                   r[:ber] ? format('%.3f', r[:ber]) : '—',
                   r[:confidence])
  end

  io.puts
  counts = results.group_by { |r| r[:confidence] }.transform_values(&:size)
  summary = CONFIDENCE_ORDER.keys.filter_map { |k| "#{counts[k]} #{k}" if counts[k] }
  io.puts "Summary: #{summary.join(', ')} (of #{results.size} tracks)"

  flagged = results.reject { |r| r[:confidence] == 'exact' }
  unless flagged.empty?
    io.puts
    io.puts 'Needs a listen:'
    flagged.each do |r|
      io.puts "  #{r[:num]}. #{r[:artist]} - #{r[:title]} (#{r[:confidence]}#{r[:note] ? ": #{r[:note]}" : ''})"
    end
  end
end

# --- main --------------------------------------------------------------------

options = { window: 120, bracket_window: 90, library: [], threshold: 0.62, noise: -34,
            min_silence: 0.35, write: false, verbose: true }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} <show-audio> <setlist.txt> -L <library> [options]"
  opts.on('-L', '--library DIR', 'Track library root (repeatable; searched recursively)') do |v|
    options[:library] << v
  end
  opts.on('-w', '--window SECS', Integer, 'Search radius around the logged time (0 = whole show)') do |v|
    options[:window] = v
  end
  opts.on('-m', '--match FLOAT', Float, 'Library match threshold 0..1 (default 0.62)') { |v| options[:threshold] = v }
  opts.on('-b', '--bracket SECS', Integer, 'Scrub window around the logged time for unmatched tracks (default 90)') do |v|
    options[:bracket_window] = v
  end
  opts.on('--write', 'Rewrite the setlist file with aligned times') { options[:write] = true }
  opts.on('--json FILE', 'Also write the full report as JSON') { |v| options[:json] = v }
  opts.on('--offset SECS', Float, 'Fixed log-to-render offset (default: auto-detect)') { |v| options[:offset] = v }
  opts.on('-q', '--quiet', 'Suppress progress output') { options[:verbose] = false }
  opts.on('-h', '--help', 'Show this message') { puts opts; exit }
end
parser.parse!

if ARGV.size < 2
  warn parser.banner
  exit 1
end

show_path, setlist_arg = ARGV
setlist_path = File.exist?(setlist_arg) ? setlist_arg : "#{setlist_arg}.txt"

abort "Show audio not found: #{show_path}" unless File.exist?(show_path)
abort "Setlist not found: #{setlist_arg}" unless File.exist?(setlist_path)
abort 'No library given (-L). Nothing to fingerprint against.' if options[:library].empty?
options[:library].each { |d| abort "Library not found: #{d}" unless File.directory?(d) }

setlist = SetlistFormat.parse_file(setlist_path)
abort "No tracks found in #{setlist_path}" if setlist.tracks.empty?

warn "Fingerprinting show: #{show_path}" if options[:verbose]
show_fp = fingerprint(show_path)
show_seconds = seconds(show_fp.size)
warn format('  %d frames (%s)', show_fp.size, SetlistFormat.format_cue(show_seconds)) if options[:verbose]

index = build_index(options[:library], verbose: options[:verbose])
abort 'No audio files found in the library.' if index.empty?

FP_CACHE = {}
def cached_fingerprint(path) = FP_CACHE[path] ||= fingerprint(path)

matches = setlist.tracks.map { |track| [track, *best_library_match(track, index, options[:threshold])] }

# A render can carry pre-show content the spin log knows nothing about (the
# 2026-07-15 archive opens with ~11 minutes of it), which puts every logged time
# out of reach of a normal search window. Probe a few tracks across the whole
# show first and, if they agree on a shift, apply it to every prior.
global_offset = options[:offset] || 0.0

if options[:offset].nil?
  probes = matches.select { |(_, entry, _)| entry }
  probes = probes.each_slice([(probes.size / 4.0).ceil, 1].max).map(&:first).first(4)
  deltas = probes.filter_map do |(track, entry, _)|
    next unless track.cue_seconds
    ref = begin
      cached_fingerprint(entry[:path])
    rescue StandardError
      next
    end
    # Try the cheap windowed search first -- it catches modest offsets exactly.
    # Only fall back to sweeping the whole show when that finds nothing.
    fit = align_track(show_fp, ref, frames(track.cue_seconds), frames(options[:window]))
    fit = align_track(show_fp, ref, nil, nil) unless fit && fit[:ber] <= 0.25
    next unless fit && fit[:ber] <= 0.25
    seconds(fit[:median]) - track.cue_seconds
  end

  if deltas.size >= 2
    deltas.sort!
    median_delta = deltas[deltas.size / 2]
    agree = deltas.count { |d| (d - median_delta).abs <= 90 }
    if agree >= 2 && median_delta.abs > 15
      global_offset = median_delta
      warn format('Detected a %+.1fs offset between the log and this render; ' \
                  'applying it to all search priors.', global_offset) if options[:verbose]
    end
  end
end

results = []

matches.each do |(track, entry, match_score)|
  if entry.nil?
    results << { num: track.num, artist: track.artist, title: track.title,
                 logged: track.cue_seconds,
                 expected: track.cue_seconds ? track.cue_seconds + global_offset : nil,
                 aligned: nil, ber: nil,
                 confidence: 'unresolved', note: format('no library match (best %.2f)', match_score) }
    next
  end

  warn "  [#{track.num}] #{track.artist} - #{track.title}" if options[:verbose]

  ref_fp = begin
    cached_fingerprint(entry[:path])
  rescue StandardError => e
    results << { num: track.num, artist: track.artist, title: track.title,
                 logged: track.cue_seconds, expected: expected, aligned: nil, ber: nil,
                 confidence: 'unresolved', note: "fingerprint failed: #{e.message}" }
    next
  end

  expected = track.cue_seconds ? track.cue_seconds + global_offset : nil
  centre = expected ? frames(expected) : nil
  radius = options[:window].zero? || centre.nil? ? nil : frames(options[:window])

  fit = align_track(show_fp, ref_fp, centre, radius)

  # A result pinned near the edge of the search window is a warning sign: the
  # true position may lie outside it, with the edge merely being the least-bad
  # spot inside. Re-search wider before believing it.
  widened = false
  if fit && radius && (fit[:median] - centre).abs > radius * 0.8
    wider = align_track(show_fp, ref_fp, centre, radius * 3)
    if wider && wider[:ber] <= fit[:ber]
      fit = wider
      widened = true
    end
  end

  if fit.nil?
    results << { num: track.num, artist: track.artist, title: track.title,
                 logged: track.cue_seconds, expected: expected, aligned: nil, ber: nil,
                 confidence: 'unresolved', note: 'no usable excerpt' }
    next
  end

  median = fit[:median]
  spread = fit[:spread]
  ber = fit[:ber]
  confidence = classify(spread, ber, fit[:votes], fit[:total])
  aligned = [seconds(median), 0.0].max

  results << { num: track.num, artist: track.artist, title: track.title,
               logged: track.cue_seconds, expected: expected,
               aligned: confidence == 'unresolved' ? nil : aligned,
               ber: ber, confidence: confidence,
               source: entry[:path], match_score: match_score,
               ref_duration: entry[:duration] || seconds(ref_fp.size),
               note: if confidence == 'unresolved'
                       format('weak match (spread %.1fs)', seconds(spread))
                     elsif widened
                       'found outside the normal search window — verify'
                     end }
end

# Second pass: bracket anything still unresolved between confident neighbours.
# A previous track we DID fingerprint gives a hard floor -- its own start plus
# its own known duration -- so the seam can only lie in a narrow window.
results.each_with_index do |r, i|
  next unless r[:aligned].nil?

  before = results[0...i].reverse.find { |x| x[:aligned] }
  after = results[(i + 1)..].find { |x| x[:aligned] }

  # Hard bounds from fingerprinted neighbours, allowing for the previous track
  # being faded out early rather than played whole.
  floor = if before
            before[:aligned] + [(before[:ref_duration] || 60) * 0.5, 20].max
          else
            0.0
          end
  ceiling = after ? after[:aligned] : show_seconds

  # Soft bounds from the log itself. Spin times are only minute-accurate, but
  # they are monotonic, so an unmatched track still can't precede the one before
  # it. Without this a run of consecutive misses all collapse to one huge window.
  bw = options[:bracket_window]
  prev_expected = results[i - 1][:expected] if i.positive?
  next_expected = results[i + 1][:expected] if i + 1 < results.size
  if r[:expected]
    floor = [floor, r[:expected] - bw, prev_expected].compact.max
    ceiling = [ceiling, r[:expected] + bw, next_expected ? next_expected + bw : nil].compact.min
  end
  bracket = format('%s-%s', SetlistFormat.format_cue(floor), SetlistFormat.format_cue(ceiling))

  if ceiling <= floor
    r[:note] = "#{r[:note]}; neighbours leave no room to search"
    next
  end

  # A song usually starts shortly after the previous one ends, so rank candidate
  # seams by nearness to that point. Novelty peaks also fire on section changes
  # *inside* a song, so these are offered as hints -- never as a decided time.
  expected_end = before && before[:ref_duration] ? before[:aligned] + before[:ref_duration] : floor

  # Rank by nearness to this track's own logged time. Ranking against the last
  # fingerprinted track's end instead biases every later pick toward the front
  # of its window, since that anchor only gets staler as the run continues.
  target = if r[:expected] && r[:expected].between?(floor, ceiling)
             r[:expected]
           else
             [[expected_end, floor].max, ceiling].min
           end

  gaps = silence_ends(show_path, floor, ceiling, options[:noise], options[:min_silence])
  seams = novelty_peaks(show_fp, floor, ceiling)

  candidates = gaps.map { |at| [at, 'gap'] } + seams.sort_by { |(_, s)| -s }.first(6).map { |(at, _)| [at, 'seam'] }
  candidates = candidates
               .sort_by { |(at, kind)| [kind == 'gap' ? 0 : 1, (at - target).abs] }
               .uniq { |(at, _)| at.round }
               .first(3)

  r[:confidence] = 'bracketed'
  r[:bracket] = [floor, ceiling]
  r[:candidates] = candidates.map { |(at, kind)| { 'at' => at, 'kind' => kind } }
  where = before ? "#{bracket} (prev ends ~#{SetlistFormat.format_cue(expected_end)})" : bracket
  r[:note] = if candidates.empty?
               "#{r[:note] || 'no local copy'}; no seam found in #{where}"
             else
               hints = candidates.map { |(at, kind)| "#{SetlistFormat.format_cue(at)}#{kind == 'gap' ? '*' : ''}" }
               "#{r[:note] || 'no local copy'}; scrub #{where}, try #{hints.join(', ')}"
             end
end

print_report(results)

if options[:json]
  File.write(options[:json], JSON.pretty_generate(results))
  puts "Wrote #{options[:json]}"
end

if options[:write]
  # Verified times go in plain. When the log sits on a different timeline from
  # the render, unverified times are shifted onto it too -- otherwise the file
  # would run backwards -- but marked with ~ so they stay distinguishable.
  cues = results.each_with_object({}) do |r, h|
    if r[:aligned]
      h[r[:num]] = { seconds: r[:aligned], approx: false }
    elsif global_offset.abs > 1 && r[:expected]
      h[r[:num]] = { seconds: r[:expected], approx: true }
    end
  end
  verified = cues.count { |_, v| !v[:approx] }
  File.write(setlist_path, SetlistFormat.rewrite_cues(setlist, cues))
  puts "Updated #{setlist_path}: #{verified} verified, " \
       "#{cues.size - verified} shifted onto the render timeline and marked ~ " \
       "(of #{results.size} tracks)"
end
