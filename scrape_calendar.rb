#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'nokogiri'
require 'json'
require 'sqlite3'

SHOW_NAMES = [
  "Sunday Morning Folk Sunrise",
  "Music Mix with Rotating Hosts",
  "The Weekly Catch with Krister Axel",
  "KSKQ Morning Show"
]

# Initialize database
DB = SQLite3::Database.new('radio_plays.db')

# Create table if it doesn't exist
DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS radio_plays (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    link TEXT NOT NULL,
    program TEXT NOT NULL,
    artist TEXT NOT NULL,
    track_name TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
SQL

def fetch_page(url)
  uri = URI.parse(url)
  response = Net::HTTP.get_response(uri)

  unless response.is_a?(Net::HTTPSuccess)
    puts "Error fetching page: #{response.code} #{response.message}"
    return nil
  end

  Nokogiri::HTML(response.body)
end

def fetch_json(url)
  uri = URI.parse(url)
  response = Net::HTTP.get_response(uri)

  unless response.is_a?(Net::HTTPSuccess)
    return nil
  end

  JSON.parse(response.body)
end

def get_tracklist(playlist_url, program_name, event_date)
  doc = fetch_page(playlist_url)
  return [] if doc.nil?

  spins = doc.css('.spin')
  tracks = []

  spins.each do |spin|
    artist = spin.at_css('.artist')&.text&.strip
    song = spin.at_css('.song')&.text&.strip

    next if artist.nil? || artist.empty?
    next if song.nil? || song.empty?

    # Insert into database
    DB.execute(
      "INSERT INTO radio_plays (date, link, program, artist, track_name) VALUES (?, ?, ?, ?, ?)",
      [event_date, playlist_url, program_name, artist, song]
    )

    tracks << "#{artist} - #{song}"
  end

  tracks
end

# Fetch the calendar feed JSON with date parameters
# Calendar feed requires start and end date parameters
require 'date'
today = Date.today
start_date = (today - 7).strftime('%Y-%m-%d')  # Last 7 days
end_date = (today + 1).strftime('%Y-%m-%d')    # Through tomorrow

calendar_feed_url = "https://spinitron.com/KSKQ/calendar-feed?timeslot=30&start=#{start_date}&end=#{end_date}"
events = fetch_json(calendar_feed_url)

if events.nil? || events.empty?
  puts "Could not fetch calendar feed"
  puts "URL: #{calendar_feed_url}"
  exit 1
end

# Find events matching our show names
SHOW_NAMES.each do |show_name|
  puts "\n=== #{show_name} ==="

  # Find the most recent event for this show
  matching_events = events.select { |e| e['title'] == show_name }

  if matching_events.empty?
    puts "Show not found in calendar feed"
    next
  end

  # Get the most recent event
  event = matching_events.sort_by { |e| e['start'] }.last
  playlist_url = event['url']

  # Make it a full URL if it's relative
  unless playlist_url.start_with?('http')
    playlist_url = "https://spinitron.com#{playlist_url}"
  end

  puts "URL: #{playlist_url}"
  puts "Time: #{event['start']}"

  # Fetch the tracklist and save to database
  tracks = get_tracklist(playlist_url, show_name, event['start'])

  if tracks.empty?
    puts "No tracks found"
  else
    puts "#{tracks.length} tracks saved to database"
    tracks.each { |track| puts track }
  end
end

puts "\nData saved to radio_plays.db"
