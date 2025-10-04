#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'nokogiri'

url = ARGV[0] || 'https://spinitron.com/KSKQ/pl/21312434/The-Weekly-Catch-with-Krister-Axel'

uri = URI.parse(url)
response = Net::HTTP.get_response(uri)

unless response.is_a?(Net::HTTPSuccess)
  puts "Error fetching page: #{response.code} #{response.message}"
  exit 1
end

doc = Nokogiri::HTML(response.body)

# Find all spin entries on the page
spins = doc.css('.spin')

tracks = []

spins.each do |spin|
  # Extract artist and song from the spin div
  artist = spin.at_css('.artist')&.text&.strip
  song = spin.at_css('.song')&.text&.strip

  next if artist.nil? || artist.empty?
  next if song.nil? || song.empty?

  tracks << "#{artist} - #{song}"
end

if tracks.empty?
  puts "No tracks found. The page structure might have changed."
  exit 1
end

puts tracks
