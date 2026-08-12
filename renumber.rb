#!/usr/bin/env ruby

if ARGV.empty?
  warn "Usage: #{File.basename($0)} <filename>"
  exit 1
end

input = ARGV[0]
path = File.exist?(input) ? input : "#{input}.txt"

unless File.exist?(path)
  warn "File not found: #{input}"
  exit 1
end

n = 0
lines = File.readlines(path).map do |line|
  stripped = line.sub(/\A\s*\d+\.\s+/, '')
  if stripped =~ /\d+:\d+(?::\d+)?\s*\z/
    n += 1
    indent = line[/\A\s*/]
    "#{indent}#{n}. #{stripped.lstrip}"
  else
    line
  end
end

File.write(path, lines.join)
puts "Renumbered #{n} tracks in #{path}"
