# nonogram.el

Play nonogram puzzles (also known as picross, griddlers or hanjie) inside
Emacs. The whole board, including the clue numbers, is drawn with SVG on a
solid white background, so it stays legible under any theme, light or dark.

## Features

- SVG board that reads well on light and dark themes.
- Keyboard and mouse play.
- Puzzles are plain `.non` files (Steven Simpson's format, as exported by
  [webpbn.com](https://webpbn.com)); drop your own into the puzzles directory.
- Win detection by clues, so puzzles with more than one valid picture work.

## Requirements

Emacs 27.1 or newer, built with SVG support (librsvg). Check with:

```elisp
(image-type-available-p 'svg)
```

## Usage

```
M-x nonogram
```

This opens a list of the puzzles found in `nonogram-puzzle-directory`. Move
with `n` / `p` and press `RET` to play the one under point.

### In-game controls

| Key             | Action                                   |
|-----------------|------------------------------------------|
| `SPC` / `mouse-1` | toggle a filled (black) cell           |
| `x` / `mouse-3`   | toggle a cross mark (a cell you think is empty) |
| arrows / `h j k l` | move the cursor                        |
| `n`             | load a random puzzle                     |
| `u`             | undo the last mark                       |
| `q`             | back to the puzzle list                  |

## Adding puzzles

Puzzles live in `nonogram-puzzle-directory` (by default the `puzzles/`
directory next to `nonogram.el`) as `.non` files:

```
title "Smiley"
width 8
height 8
rows
6
1,1
...
columns
5
1,1
...
goal "0111111010000001..."
```

Clue blocks are comma-separated. If the file omits `rows`/`columns`, they are
derived from the `goal` grid. You can export any puzzle from webpbn.com in the
"NON — Steve Simpson" format and drop it in.

## Installation

Until it is on MELPA, clone the repository and load it:

```elisp
(add-to-list 'load-path "/path/to/nonogram.el")
(require 'nonogram)
```

### MELPA recipe

Because the puzzles ship as data files, the recipe must include them:

```elisp
(nonogram
 :fetcher git
 :url "https://git.andros.dev/andros/nonogram.el.git"
 :files ("*.el" "puzzles"))
```

## License

Code is GPLv3 (see `LICENSE`). The bundled puzzles are released under CC0-1.0.
