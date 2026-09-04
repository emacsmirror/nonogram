# Nonogram for Emacs

Play nonogram puzzles (also known as picross, griddlers or hanjie) in Emacs.

Requires Emacs 27.1 or later, built with SVG support (librsvg).

Fill the grid so that each row and column matches its clue numbers and a hidden picture appears. Puzzles are plain `.non` files (Steven Simpson's format, as exported by [webpbn.com](https://webpbn.com)), and the package can download and update them from a remote source.

## Buffers

### Puzzle list (`M-x nonogram`)

```
 Nonogram   RET play   U update   q quit

Arrow    7×7
Cat      7×7
Check    7×7
Diamond  7×7
Heart    7×6
Smiley   8×8
```

### Game board (`RET` on a puzzle)

The board is drawn with SVG; every cell, including the clue numbers, sits on a solid white background. The clue numbers frame the grid on the top and left:

```
            1     1
            1 1 1 1
          1 1 1 1 1 1
        5 1 1 1 1 1 1 5
      6 · ■ ■ ■ ■ ■ ■ ·
    1 1 ■ · · · · · · ■
1 1 1 1 ■ · ■ · · ■ · ■
    1 1 ■ · · · · · · ■
  1 4 1 ■ · ■ ■ ■ ■ · ■
    1 1 ■ · · · · · · ■
    1 1 · ■ · · · · ■ ·
      4 · · ■ ■ ■ ■ · ·
```

Below the board a legend lists the controls. A cell can be empty, filled (black), crossed out in red for cells you rule out, or marked with a small dot for cells you suspect are filled.

## Keymap

### Puzzle list

| Key               | Description                   |
|-------------------|-------------------------------|
| `RET` / `mouse-1` | Play the puzzle at point      |
| `n` / `p`         | Move down / up                |
| `U`               | Download / update the puzzles |
| `g`               | Refresh the list              |
| `q`               | Quit                          |

### Game board

| Key                | Description                    |
|--------------------|--------------------------------|
| `SPC` / `mouse-1`  | Toggle a filled (black) cell   |
| `x` / `mouse-3`    | Toggle a cross mark            |
| `c` / `mouse-2`    | Toggle a dot hint              |
| arrows / `h j k l` | Move the cursor                |
| `n`                | Load a random puzzle           |
| `u`                | Undo the last mark             |
| `q`                | Back to the puzzle list        |

## Installation

### use-package with :vc (Emacs 29+)

```elisp
(use-package nonogram
  :vc (:url "https://git.andros.dev/andros/nonogram.el"
       :rev :newest))
```

### use-package with :load-path

For manual installation or Emacs < 29:

```elisp
(use-package nonogram
  :load-path "/path/to/nonogram.el")
```

## Usage

1. Run `M-x nonogram` to open the puzzle list.
2. Move with `n` and `p` and press `RET` to play the puzzle at point.
3. Fill cells with `SPC` (or left-click), cross out cells with `x` (right-click) and leave dot hints with `c` (middle-click).
4. You win when the filled cells match every row and column clue.
5. Press `q` to return to the list, or `n` for a random puzzle.

If the puzzle directory is empty the first time you open the list, Nonogram offers to download a set of puzzles. Press `U` in the list, or run `M-x nonogram-download-puzzles`, to re-download and update them at any time.

## Puzzle format

Puzzles are `.non` files in Steven Simpson's format:

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

Clue blocks within a line are comma-separated. If a file omits the `rows` and `columns` clues, they are derived from the `goal` grid. You can export any puzzle from webpbn.com in the "NON — Steve Simpson" format and drop it into `nonogram-puzzle-directory`.

## Customization

Run `M-x customize-group RET nonogram RET` to list all available options.

Key options:

- `nonogram-cell-px` (default `26`): size in pixels of each board cell.
- `nonogram-puzzle-directory`: directory scanned for `.non` files (default: the `puzzles` directory next to the package).
- `nonogram-puzzle-source-url`: Gitea contents-API URL listing the downloadable puzzles.
- `nonogram-auto-download` (default `t`): offer to download puzzles when the directory is empty.
- `nonogram-background-color` (default `"#FFFFFF"`): board background, drawn as a solid SVG fill.
- `nonogram-filled-color` (default `"#111111"`): filled cells and grid lines.
- `nonogram-cross-color` (default `"#B03030"`): cross marks.
- `nonogram-dot-color` (default `"#111111"`): dot hints.
- `nonogram-clue-color` (default `"#111111"`): clue numbers.
- `nonogram-cursor-color` (default `"#E8901A"`): the ring that marks the cursor.

## Contributing

Contributions are welcome! Please see the [contribution guidelines](https://git.andros.dev/andros/contribute) for instructions on how to submit issues or pull requests.

## License

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see [https://www.gnu.org/licenses/](https://www.gnu.org/licenses/).

The bundled puzzles are released under CC0-1.0.
