#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'nokogiri'
require 'json'
require 'date'

SHOW_NAME = "The Weekly Catch with Krister Axel"
START_DATE = Date.new(2026, 07, 03)

def fetch_json(url)
  uri = URI.parse(url)
  response = Net::HTTP.get_response(uri)

  unless response.is_a?(Net::HTTPSuccess)
    return nil
  end

  JSON.parse(response.body)
end

def fetch_page(url)
  uri = URI.parse(url)
  response = Net::HTTP.get_response(uri)

  unless response.is_a?(Net::HTTPSuccess)
    puts "Error fetching page: #{response.code} #{response.message}"
    return nil
  end

  Nokogiri::HTML(response.body)
end

def parse_spin_time(time_str)
  return nil if time_str.nil? || time_str.empty?
  match = time_str.strip.match(/(\d+):(\d+)\s*(AM|PM)/i)
  return nil unless match
  hours = match[1].to_i % 12
  hours += 12 if match[3].upcase == 'PM'
  hours * 60 + match[2].to_i
end

def format_timestamp(total_seconds)
  total_seconds = total_seconds.to_i
  hours = total_seconds / 3600
  minutes = (total_seconds % 3600) / 60
  secs = total_seconds % 60
  hours > 0 ? format('%d:%02d:%02d', hours, minutes, secs) : format('%d:%02d', minutes, secs)
end

def get_tracklist(playlist_url)
  doc = fetch_page(playlist_url)
  return [] if doc.nil?

  spin_items = doc.css('.spin-item')
  raw = []

  spin_items.each do |item|
    artist = item.at_css('.artist')&.text&.strip
    song = item.at_css('.song')&.text&.strip
    time_text = item.at_css('.spin-time a')&.text&.strip

    next if artist.nil? || artist.empty?
    next if song.nil? || song.empty?

    raw << { artist: artist, song: song, time: time_text }
  end

  return [] if raw.empty?

  first_minutes = parse_spin_time(raw.first[:time])

  raw.map do |track|
    track_minutes = parse_spin_time(track[:time])
    if first_minutes && track_minutes
      # Handle crossing midnight
      diff = track_minutes - first_minutes
      diff += 24 * 60 if diff < 0
      timestamp = format_timestamp(diff * 60)
      "#{track[:artist]} - #{track[:song]} - #{timestamp}"
    else
      "#{track[:artist]} - #{track[:song]}"
    end
  end
end

# Generate all Wednesdays from START_DATE to today
today = Date.today
current_date = START_DATE

# Make sure we start on a Wednesday
until current_date.wednesday?
  current_date += 1
end

wednesdays = []
while current_date <= today
  wednesdays << current_date
  current_date += 7 # Next Wednesday
end

puts "Searching for #{SHOW_NAME} episodes on #{wednesdays.length} Wednesdays..."
puts "Date range: #{wednesdays.first} to #{wednesdays.last}\n\n"

found_count = 0
missing_count = 0

wednesdays.each do |wednesday|
  date_str = wednesday.strftime('%Y-%m-%d')

  # Query the calendar for this specific week
  # Use a range from the Wednesday to the next day to catch the show
  start_param = date_str
  end_param = (wednesday + 1).strftime('%Y-%m-%d')

  calendar_url = "https://spinitron.com/KSKQ/calendar-feed?timeslot=30&start=#{start_param}&end=#{end_param}"

  puts "Checking #{date_str}..."
  events = fetch_json(calendar_url)

  if events.nil? || events.empty?
    puts "  No events found for this date"
    missing_count += 1
    next
  end

  # Find The Weekly Catch event
  matching_event = events.find { |e| e['title'] == SHOW_NAME }

  if matching_event.nil?
    puts "  #{SHOW_NAME} not found"
    missing_count += 1
    next
  end

  playlist_url = matching_event['url']
  unless playlist_url.start_with?('http')
    playlist_url = "https://spinitron.com#{playlist_url}"
  end

  puts "  Found! Fetching tracks..."
  tracks = get_tracklist(playlist_url)

  if tracks.empty?
    puts "  No tracks found"
    missing_count += 1
    next
  end

  # Save to text file
  filename = "#{date_str}.txt"
  File.open(filename, 'w') do |file|
    file.puts "The Weekly Catch with Krister Axel"
    file.puts "Date: #{date_str}"
    file.puts "URL: #{playlist_url}"
    file.puts ""
    file.puts "Tracks:"
    file.puts "=" * 50
    tracks.each_with_index do |track, index|
      file.puts "#{index + 1}. #{track}"
    end
  end

  puts "  ✓ Saved #{tracks.length} tracks to #{filename}"
  found_count += 1

  # Be nice to the server
  sleep 1
end

puts "\n" + "=" * 60
puts "Summary:"
puts "  Episodes found and saved: #{found_count}"
puts "  Episodes missing/not found: #{missing_count}"
puts "  Total Wednesdays checked: #{wednesdays.length}"
