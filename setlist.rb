# frozen_string_literal: true

# Shared parsing/formatting for Weekly Catch song lists.
# Used by setlist_card.rb (render) and align_setlist.rb (timing).

Track = Struct.new(:num, :artist, :title, :cue, :cue_seconds, :duration, :line_index,
                   :approx, :duration_approx) do
  def query
    [artist, title].compact.reject(&:empty?).join(' ')
  end

  def duration_label
    return nil unless duration
    format('%d:%02d', duration / 60, duration % 60)
  end
end

Setlist = Struct.new(:show, :date, :links, :tracks, :source, :lines)

module SetlistFormat
  module_function

  # "1:55:27" / "9:40" -> seconds
  def parse_cue(str)
    str.split(':').map(&:to_i).reverse.each_with_index.sum { |part, i| part * (60**i) }
  end

  # seconds -> "1:55:27" / "9:40", matching the style already in the .txt files
  def format_cue(seconds)
    seconds = seconds.round
    hours, rem = seconds.divmod(3600)
    minutes, secs = rem.divmod(60)
    hours.positive? ? format('%d:%02d:%02d', hours, minutes, secs) : format('%d:%02d', minutes, secs)
  end

  def parse_track(line)
    m = line.match(/\A\s*(\d+)\.\s+(.*?)\s*\z/)
    return nil unless m

    num, rest = m[1].to_i, m[2]

    # Trailing cue time, with or without the " - " separator (some lines omit it).
    # A leading ~ marks a time that could not be verified against the audio.
    cue = nil
    approx = false
    if (t = rest.match(/\s*[-–—]?\s*(~?)((?:\d{1,2}:)?\d{1,2}:\d{2})\s*\z/))
      approx = t[1] == '~'
      cue = t[2]
      rest = t.pre_match.sub(/\s*[-–—]\s*\z/, '')
    end

    # Artist is everything before the first dash separator; the title keeps its own.
    artist, title = rest.split(/\s+[-–—]\s+/, 2)
    artist, title = nil, artist if title.nil?

    Track.new(num, artist&.strip, title.to_s.strip, cue, cue && parse_cue(cue), nil, nil, approx)
  end

  def parse_file(path)
    show = nil
    date = nil
    links = []
    tracks = []
    in_tracks = false
    lines = File.readlines(path, chomp: true, encoding: 'UTF-8')

    lines.each_with_index do |line, index|
      next if line.match?(/\A(<{4,}|>{4,}|={4,}|\|{4,})/) # git conflict markers / rules
      next if line.strip.empty?

      if !in_tracks && (m = line.match(/\ADate:\s*(.+)\z/i))
        date = m[1].strip
      elsif !in_tracks && (m = line.match(/\AURL:\s*(.+)\z/i))
        links = m[1].split(',').map(&:strip).reject(&:empty?)
      elsif line.match?(/\ATracks:\s*\z/i)
        in_tracks = true
      elsif (track = parse_track(line))
        track.line_index = index
        tracks << track
      elsif show.nil? && !in_tracks
        show = line.strip
      end
    end

    # Durations come from the gap to the next cue; the closer's length is unknown.
    # A length is only as trustworthy as the two cues it sits between.
    tracks.each_cons(2) do |a, b|
      next unless a.cue_seconds && b.cue_seconds
      a.duration = b.cue_seconds - a.cue_seconds
      a.duration_approx = a.approx || b.approx
    end

    Setlist.new(show || 'Setlist', date, links, tracks, path, lines)
  end

  # Rewrite each track line's trailing cue in place, preserving everything else.
  # A value may be a plain number, or {seconds:, approx:} to mark it unverified.
  def rewrite_cues(setlist, cues_by_num)
    lines = setlist.lines.dup

    setlist.tracks.each do |track|
      value = cues_by_num[track.num]
      next if value.nil? || track.line_index.nil?

      seconds = value.is_a?(Hash) ? value[:seconds] : value
      approx = value.is_a?(Hash) && value[:approx]
      next if seconds.nil?

      line = lines[track.line_index]
      body = line.sub(/\s*[-–—]?\s*~?(?:\d{1,2}:)?\d{1,2}:\d{2}\s*\z/, '')
      lines[track.line_index] = "#{body} - #{approx ? '~' : ''}#{format_cue(seconds)}"
    end

    lines.join("\n") + "\n"
  end
end
