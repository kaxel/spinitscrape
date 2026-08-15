# frozen_string_literal: true

require 'set'

# Procedural 16-bit-style fish thumbnails for the episode ledger and setlist
# card headers — deterministic per episode date, so a given episode always
# draws the same fish everywhere it appears.
#
# Square 16x16 canvas. Each of the 10 species is a set of (row, col) pixel
# coordinates per layer: body (primary color, auto-shaded top-to-bottom),
# accent (secondary — head/fins/tail-tip, also lightly shaded), sheen (a
# bright highlight tint), eye + glint (fixed). A dark outline is generated
# automatically around the whole silhouette, and a lighten/darken ramp is
# applied across the body and accent layers — that outline-plus-shading
# treatment is what reads as "16-bit sprite" rather than flat 8-bit blocks.

module FishThumbnail
  module_function

  def box(r0, r1, c0, c1) = (r0..r1).to_a.product((c0..c1).to_a)

  GRID = 16
  VIEWBOX = 16

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

  SHAPES = [
    { # round (goldfish)
      body:   box(4, 11, 3, 11),
      accent: box(4, 11, 0, 2) + box(2, 3, 7, 9) + box(12, 13, 7, 9) + box(4, 11, 12, 13),
      sheen:  [[5, 5], [5, 6], [6, 5], [4, 6], [4, 7]],
      eye:    [[6, 12]],
      glint:  [[5, 12]]
    },
    { # long (koi)
      body:   box(4, 11, 2, 11),
      accent: box(5, 10, 0, 1) + box(2, 3, 6, 8) + box(4, 11, 13, 14),
      sheen:  [[5, 4], [5, 5], [6, 4], [4, 5], [4, 6]],
      eye:    [[6, 13]],
      glint:  [[5, 13]]
    },
    { # tall (angelfish / discus) — fins flare wider than the body,
      # top and bottom, so it reads as a tall flared shape.
      body:   box(4, 11, 6, 9),
      accent: box(0, 3, 4, 11) + box(12, 15, 4, 11) + [[7, 4], [8, 4], [7, 5], [8, 5]],
      sheen:  [[5, 7], [5, 8], [6, 7]],
      eye:    [[6, 9]],
      glint:  [[5, 9]]
    },
    { # betta — tiny body, huge flowing fin
      body:   box(6, 9, 10, 13),
      accent: box(3, 12, 0, 9) + box(5, 10, 14, 15),
      sheen:  [[7, 11], [7, 12]],
      eye:    [[7, 14]],
      glint:  [[6, 14]]
    },
    { # tiny (tetra / guppy) — slimmer body, still substantial
      body:   box(6, 9, 4, 12),
      accent: box(6, 9, 1, 3) + box(6, 9, 13, 14) + box(5, 5, 8, 10),
      sheen:  [[7, 7], [7, 8]],
      eye:    [[7, 13]],
      glint:  [[6, 13]]
    },
    { # puffer
      body:   box(2, 13, 3, 12),
      accent: box(6, 9, 0, 2) + box(6, 9, 13, 14) +
              [[3, 4], [3, 10], [12, 4], [12, 10], [4, 3], [11, 3], [4, 12], [11, 12]],
      sheen:  [[4, 5], [4, 6], [4, 7], [5, 5], [5, 6]],
      eye:    [[7, 13]],
      glint:  [[6, 13]]
    },
    { # swordtail
      body:   box(4, 11, 5, 12),
      accent: box(7, 8, 0, 4) + box(2, 3, 7, 9) + box(4, 11, 13, 14),
      sheen:  [[5, 7], [5, 8]],
      eye:    [[6, 13]],
      glint:  [[5, 13]]
    },
    { # fantail
      body:   box(4, 11, 5, 13),
      accent: box(0, 15, 1, 4) + box(4, 11, 14, 15),
      sheen:  [[5, 7], [5, 8], [6, 7]],
      eye:    [[6, 14]],
      glint:  [[5, 14]]
    },
    { # predator (bass / tuna)
      body:   box(4, 11, 3, 13),
      accent: box(2, 13, 0, 2) + box(1, 2, 7, 9) + box(6, 9, 14, 15),
      sheen:  [[5, 6], [5, 7], [6, 6]],
      eye:    [[7, 14]],
      glint:  [[6, 14]]
    },
    { # seahorse
      body:   box(0, 3, 10, 13) + box(3, 6, 7, 10) + box(6, 9, 8, 11) +
              box(9, 12, 6, 9) + box(12, 15, 7, 10),
      accent: box(0, 1, 13, 15) + box(4, 5, 10, 11) + [[14, 5], [15, 5], [15, 6]],
      sheen:  [[2, 11], [3, 10], [5, 8]],
      eye:    [[1, 12]],
      glint:  [[1, 13]]
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
        next if nr.negative? || nc.negative? || nr >= GRID || nc >= GRID
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

    rects = cells.map { |(r, c), color|
      %(<rect x="#{c}" y="#{r}" width="1" height="1" fill="#{color}"/>)
    }.join

    <<~SVG.strip
      <svg viewBox="0 0 #{VIEWBOX} #{VIEWBOX}" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true"><rect width="#{VIEWBOX}" height="#{VIEWBOX}" fill="#{BG_COLOR}"/>#{rects}</svg>
    SVG
  end
end
