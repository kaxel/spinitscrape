# frozen_string_literal: true

# Procedural 8-bit fish thumbnails for the episode ledger — deterministic per
# episode date, so a given episode always draws the same fish.
#
# Square canvas, 12x12. Fish shapes live in an 8-row band, padded 2 rows top
# and bottom. Each shape is a set of (row, col) pixel coordinates per layer:
# body (primary color), accent (secondary — head/fins/tail-tip), sheen (a
# lightened tint of the primary), and eye (fixed dark).

module FishThumbnail
  module_function

  def box(r0, r1, c0, c1) = (r0..r1).to_a.product((c0..c1).to_a)

  COLS = 12
  ROWS = 8
  PAD_TOP = 2
  VIEWBOX = 12

  EYE_COLOR = '#211f1c'
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
      body:   box(2, 5, 3, 8),
      accent: box(2, 5, 0, 1) + box(1, 1, 5, 6) + box(6, 6, 5, 6) + box(2, 5, 9, 10),
      sheen:  [[2, 4], [2, 5], [3, 4]],
      eye:    [[3, 9]]
    },
    { # long (koi)
      body:   box(2, 5, 2, 9),
      accent: box(3, 4, 0, 1) + box(1, 1, 5, 6) + box(2, 5, 10, 11),
      sheen:  [[2, 3], [2, 4], [3, 3]],
      eye:    [[3, 10]]
    },
    { # tall (angelfish / discus) — fins flare wider than the body, top and
      # bottom, so it reads as a tall flared shape rather than a plus sign.
      body:   box(2, 5, 5, 8),
      accent: box(0, 1, 4, 9) + box(6, 7, 4, 9) + [[3, 4], [4, 4]],
      sheen:  [[2, 6], [2, 7]],
      eye:    [[3, 8]]
    },
    { # betta — tiny body, huge flowing fin
      body:   box(3, 4, 7, 9),
      accent: box(1, 6, 0, 6) + box(2, 5, 10, 11),
      sheen:  [[3, 8]],
      eye:    [[3, 10]]
    },
    { # tiny (tetra / guppy)
      body:   box(3, 4, 4, 7),
      accent: [[3, 3], [4, 3]] + [[3, 8], [4, 8]],
      sheen:  [[3, 5]],
      eye:    [[3, 7]]
    },
    { # puffer
      body:   box(1, 6, 3, 8),
      accent: box(3, 4, 0, 2) + box(3, 4, 9, 10) +
              [[1, 4], [1, 6], [6, 4], [6, 6], [2, 3], [5, 3], [2, 8], [5, 8]],
      sheen:  [[2, 5], [2, 6], [3, 5]],
      eye:    [[3, 9]]
    },
    { # swordtail
      body:   box(2, 5, 4, 8),
      accent: box(3, 3, 0, 3) + box(2, 2, 5, 6) + box(2, 5, 9, 10),
      sheen:  [[2, 5], [2, 6]],
      eye:    [[3, 9]]
    },
    { # fantail
      body:   box(2, 5, 4, 9),
      accent: box(0, 7, 1, 3) + box(2, 5, 10, 11),
      sheen:  [[2, 5], [2, 6]],
      eye:    [[3, 10]]
    },
    { # predator (bass / tuna)
      body:   box(2, 5, 3, 9),
      accent: box(1, 6, 0, 1) + box(1, 1, 6, 7) + box(3, 4, 10, 11),
      sheen:  [[2, 4], [2, 5]],
      eye:    [[3, 9]]
    },
    { # seahorse
      body:   box(0, 1, 7, 8) + box(1, 2, 6, 7) + box(2, 4, 5, 6) +
              box(4, 5, 6, 7) + box(5, 6, 5, 6) + box(6, 7, 4, 5),
      accent: box(0, 0, 9, 10) + [[2, 4], [7, 3]],
      sheen:  [[1, 6], [2, 5]],
      eye:    [[0, 7]]
    }
  ].freeze

  def lighten(hex, amount)
    r, g, b = hex[1, 2].to_i(16), hex[3, 2].to_i(16), hex[5, 2].to_i(16)
    r += ((255 - r) * amount).round
    g += ((255 - g) * amount).round
    b += ((255 - b) * amount).round
    format('#%02x%02x%02x', r, g, b)
  end

  # seed: any integer (e.g. an episode date as YYYYMMDD) — same seed always
  # draws the same fish.
  def svg(seed)
    rng = Random.new(seed)
    shape = SHAPES[rng.rand(SHAPES.size)]
    primary = PALETTE.sample(random: rng)
    secondary = (PALETTE - [primary]).sample(random: rng)
    sheen = lighten(primary, 0.28 + rng.rand * 0.22)

    cells = {}
    shape[:body].each { |rc| cells[rc] = primary }
    shape[:accent].each { |rc| cells[rc] = secondary }
    shape[:sheen].each { |rc| cells[rc] = sheen }
    shape[:eye].each { |rc| cells[rc] = EYE_COLOR }

    rects = cells.map { |(r, c), color|
      %(<rect x="#{c}" y="#{r + PAD_TOP}" width="1" height="1" fill="#{color}"/>)
    }.join

    <<~SVG.strip
      <svg viewBox="0 0 #{VIEWBOX} #{VIEWBOX}" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true"><rect width="#{VIEWBOX}" height="#{VIEWBOX}" fill="#{BG_COLOR}"/>#{rects}</svg>
    SVG
  end
end
