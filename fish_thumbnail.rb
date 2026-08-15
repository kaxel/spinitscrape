# frozen_string_literal: true

require 'set'

# Procedural 16-bit-style fish thumbnails for the episode ledger and setlist
# card headers — deterministic per episode date, so a given episode always
# draws the same fish everywhere it appears.
#
# 24x16 canvas (3:2 — wide enough for an actual tapered fish body instead of
# a square block). Bodies are built from a half-thickness profile per column
# (thin-thick-thin, like a real torso), tails from a fork/fan/point curve,
# with small fin/head accents placed against the body's own edge. A dark
# outline is generated automatically around the whole silhouette, and a
# lighten/darken ramp shades body and accent — that outline-plus-shading
# treatment is what reads as "16-bit sprite" rather than flat color blocks.

module FishThumbnail
  module_function

  WIDTH = 24
  HEIGHT = 16
  CENTER = 8

  EYE_COLOR = '#141b21'
  GLINT_COLOR = '#f4f1e4'
  OUTLINE_COLOR = '#14100d'
  BG_COLOR = '#d9d6c2'

  PALETTE = %w[
    #1f2f3a
    #b23a2c
    #d99b2b
    #2f6f6a
    #3c5a34
    #6b3a5c
    #c1611a
    #4a6b8a
    #c9a227
    #d4634a
  ].freeze

  def in_bounds(coords) = coords.select { |(r, c)| r.between?(0, HEIGHT - 1) && c.between?(0, WIDTH - 1) }

  def box(r0, r1, c0, c1) = (r0..r1).to_a.product((c0..c1).to_a)

  # A tapered torso: `halves` is the half-thickness at each column, starting
  # at col_start. Produces a lens/torpedo silhouette instead of a rectangle.
  def taper(col_start, halves, center = CENTER)
    coords = []
    halves.each_with_index do |half, i|
      col = col_start + i
      (-half..half).each { |d| coords << [center + d, col] }
    end
    in_bounds(coords)
  end

  # Caudal fin, forking away from the body toward the left (tail side).
  def forked_tail(attach_col, length, start_half, spread, center = CENTER, thickness = 2)
    coords = []
    length.times do |i|
      col = attach_col - i
      off = start_half + (spread * i)
      thickness.times do |t|
        coords << [center - off - t, col]
        coords << [center + off + t, col]
      end
    end
    in_bounds(coords)
  end

  # Fan/lunate tail — a solid wedge widening toward the tip.
  def fan_tail(attach_col, length, start_half, spread, center = CENTER)
    coords = []
    length.times do |i|
      col = attach_col - i
      half = start_half + (spread * i)
      (-half..half).each { |d| coords << [center + d, col] }
    end
    in_bounds(coords)
  end

  # Single tapering point — a slim flowing tail rather than a fork.
  def point_tail(attach_col, length, start_half, center = CENTER)
    coords = []
    length.times do |i|
      col = attach_col - i
      half = start_half - i
      next if half <= 0

      (-half..half).each { |d| coords << [center + d, col] }
    end
    in_bounds(coords)
  end

  SHAPES = [
    { # goldfish — chubby taper, wide fork
      body:   taper(6, [3, 4, 5, 6, 6, 6, 6, 6, 5, 4, 3, 2]),
      accent: forked_tail(6, 5, 2, 1) + box(6, 9, 18, 20) + box(0, 1, 10, 12) + box(15, 15, 9, 11),
      sheen:  [[6, 10], [6, 11], [7, 10]],
      eye:    [[6, 19]],
      glint:  [[5, 19]]
    },
    { # koi — long slender taper, pointed flowing tail
      body:   taper(6, [2, 3, 3, 4, 4, 4, 4, 4, 4, 3, 3, 2]),
      accent: point_tail(6, 6, 3) + box(6, 9, 18, 21) + box(3, 3, 9, 11) + box(13, 13, 9, 10),
      sheen:  [[6, 9], [6, 10], [7, 9]],
      eye:    [[6, 19]],
      glint:  [[5, 19]]
    },
    { # angelfish / discus — tall body, fins flare above and below
      body:   taper(9, [2, 3, 4, 4, 4, 3, 2], 8),
      accent: box(0, 3, 8, 15) + box(12, 15, 8, 15) + point_tail(9, 4, 2) +
              box(6, 9, 16, 17),
      sheen:  [[6, 11], [6, 12], [7, 11]],
      eye:    [[7, 16]],
      glint:  [[6, 16]]
    },
    { # betta — tiny body, huge flowing fan fin
      body:   taper(15, [2, 3, 3, 2]),
      accent: fan_tail(15, 13, 1, 1) + box(6, 9, 18, 20),
      sheen:  [[7, 16], [7, 17]],
      eye:    [[6, 19]],
      glint:  [[5, 19]]
    },
    { # tetra / guppy — small slim taper, small point tail
      body:   taper(9, [2, 2, 3, 3, 3, 2, 2]),
      accent: point_tail(9, 5, 2) + box(6, 9, 16, 18) + box(5, 5, 11, 12),
      sheen:  [[7, 11], [7, 12]],
      eye:    [[6, 17]],
      glint:  [[5, 17]]
    },
    { # pufferfish — near-round body, tiny tail, spike dots
      body:   taper(7, [4, 6, 7, 7, 7, 7, 6, 4]),
      accent: point_tail(7, 3, 3) + box(6, 9, 15, 17) +
              [[2, 9], [2, 12], [14, 9], [14, 12], [3, 8], [3, 13], [13, 8], [13, 13]],
      sheen:  [[4, 10], [4, 11], [5, 10], [5, 9]],
      eye:    [[6, 16]],
      glint:  [[5, 16]]
    },
    { # swordtail — small body, long thin spike trailing off the tail
      body:   taper(6, [2, 3, 4, 4, 4, 3, 2]),
      accent: box(8, 8, 0, 5) + box(3, 3, 8, 10) + box(6, 9, 13, 15),
      sheen:  [[6, 9], [6, 10]],
      eye:    [[6, 14]],
      glint:  [[5, 14]]
    },
    { # fantail goldfish — big dramatic fan, plumper body
      body:   taper(8, [3, 4, 5, 5, 5, 4, 3, 2]),
      accent: fan_tail(8, 8, 1, 1) + box(6, 9, 16, 18),
      sheen:  [[6, 10], [6, 11], [7, 10]],
      eye:    [[6, 17]],
      glint:  [[5, 17]]
    },
    { # predator (bass / tuna) — long lean taper, crescent tail
      body:   taper(6, [2, 3, 4, 5, 5, 5, 5, 5, 4, 3, 2]),
      accent: forked_tail(6, 5, 2, 1) + box(6, 9, 17, 20) + box(1, 1, 9, 11),
      sheen:  [[6, 10], [6, 11], [7, 10]],
      eye:    [[6, 18]],
      glint:  [[5, 18]]
    },
    { # seahorse — vertical S-curve, the one outlier silhouette
      body:   box(0, 3, 12, 15) + box(3, 6, 9, 12) + box(6, 9, 10, 13) +
              box(9, 12, 8, 11) + box(12, 15, 9, 12),
      accent: box(0, 1, 15, 17) + box(4, 5, 12, 13) + [[14, 7], [15, 7], [15, 8]],
      sheen:  [[2, 13], [3, 12], [5, 11]],
      eye:    [[1, 14]],
      glint:  [[1, 15]]
    }
  ].freeze

  def lighten(hex, amount)
    r, g, b = hex[1, 2].to_i(16), hex[3, 2].to_i(16), hex[5, 2].to_i(16)
    r += ((255 - r) * amount).round
    g += ((255 - g) * amount).round
    b += ((255 - b) * amount).round
    format('#%02x%02x%02x', r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255))
  end

  def darken(hex, amount)
    r, g, b = hex[1, 2].to_i(16), hex[3, 2].to_i(16), hex[5, 2].to_i(16)
    r -= (r * amount).round
    g -= (g * amount).round
    b -= (b * amount).round
    format('#%02x%02x%02x', r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255))
  end

  # Shade each pixel in `coords` by its row position within the group's own
  # vertical span — top third lighter, bottom third darker — so a flat block
  # of coordinates reads as a lit, rounded form instead of a flat swatch.
  def shaded(coords, base_color, light_amount, dark_amount)
    rows = coords.map(&:first)
    return {} if rows.empty?

    r_min, r_max = rows.min, rows.max
    span = (r_max - r_min).zero? ? 1 : (r_max - r_min)
    coords.each_with_object({}) do |rc, out|
      rel = (rc[0] - r_min).to_f / span
      out[rc] = if rel < 0.34
                  lighten(base_color, light_amount)
                elsif rel > 0.66
                  darken(base_color, dark_amount)
                else
                  base_color
                end
    end
  end

  def outline_for(filled_coords)
    filled = filled_coords.to_set
    outline = {}
    filled.each do |(r, c)|
      [[r - 1, c], [r + 1, c], [r, c - 1], [r, c + 1]].each do |nr, nc|
        next if nr.negative? || nc.negative? || nr >= HEIGHT || nc >= WIDTH
        next if filled.include?([nr, nc])

        outline[[nr, nc]] = OUTLINE_COLOR
      end
    end
    outline
  end

  # seed: any integer (e.g. an episode date as YYYYMMDD) — same seed always
  # draws the same fish.
  def svg(seed)
    rng = Random.new(seed)
    shape = SHAPES[rng.rand(SHAPES.size)]
    primary = PALETTE.sample(random: rng)
    secondary = (PALETTE - [primary]).sample(random: rng)
    sheen = lighten(primary, 0.45 + rng.rand * 0.15)

    all_filled = shape[:body] + shape[:accent] + shape[:sheen] + shape[:eye] + shape[:glint]

    cells = outline_for(all_filled)
    cells.merge!(shaded(shape[:body], primary, 0.22, 0.28))
    cells.merge!(shaded(shape[:accent], secondary, 0.22, 0.22))
    shape[:sheen].each { |rc| cells[rc] = sheen }
    shape[:eye].each { |rc| cells[rc] = EYE_COLOR }
    shape[:glint].each { |rc| cells[rc] = GLINT_COLOR }

    if rng.rand < 0.5
      cells = cells.each_with_object({}) { |((r, c), color), out| out[[r, WIDTH - 1 - c]] = color }
    end

    rects = cells.map { |(r, c), color|
      %(<rect x="#{c}" y="#{r}" width="1" height="1" fill="#{color}"/>)
    }.join

    <<~SVG.strip
      <svg viewBox="0 0 #{WIDTH} #{HEIGHT}" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true"><rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{BG_COLOR}"/>#{rects}</svg>
    SVG
  end
end
