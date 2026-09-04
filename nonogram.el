;;; nonogram.el --- Play nonogram (picross) puzzles with SVG graphics  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Andros Fenollosa

;; Author: Andros Fenollosa <hi@andros.dev>
;; Maintainer: Andros Fenollosa <hi@andros.dev>
;; URL: https://git.andros.dev/andros/nonogram.el
;; Version: 1.0.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: games

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Nonogram is a player for nonogram puzzles (also known as picross,
;; griddlers or hanjie).  Fill the grid so that each row and column
;; matches its clue numbers, revealing a hidden picture.

;; The whole board, including the clue numbers, is drawn with SVG on a
;; solid white background so it stays legible under any Emacs theme,
;; light or dark.

;; Usage:

;;   M-x nonogram

;; This opens a list of the puzzles found in `nonogram-puzzle-directory'
;; (files in Steven Simpson's .non format).  Move with n and p and press
;; RET to play the puzzle under point.

;; If the directory is empty, Nonogram offers to download a set of
;; puzzles from `nonogram-puzzle-source-url'.  Press U in the list (or
;; run M-x nonogram-download-puzzles) at any time to re-download and
;; update them.

;; In-game controls:

;;   SPC or mouse-1   toggle a filled (black) cell
;;   x   or mouse-3   toggle a cross mark (a cell you believe is empty)
;;   c   or mouse-2   toggle a dot hint (a cell you suspect is filled)
;;   arrows / h j k l move the cursor
;;   n                load a random puzzle
;;   u                undo the last mark
;;   q                back to the puzzle list

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; ──────────────────────────────────────────────────────────────────
;; Customization
;; ──────────────────────────────────────────────────────────────────

(defgroup nonogram nil
  "Play nonogram (picross) puzzles."
  :group 'games
  :prefix "nonogram-")

(defcustom nonogram-cell-px 26
  "Size in pixels of each board cell (both width and height).
Increase it for high-resolution displays, decrease it for a more
compact board.  Start a new puzzle for the change to take effect."
  :type 'integer)

(defcustom nonogram-background-color "#FFFFFF"
  "Background color of the whole board, including the clue numbers.
It is drawn as a solid SVG fill so the board looks the same under
any theme."
  :type 'color)

(defcustom nonogram-filled-color "#111111"
  "Color of a filled cell and of the grid lines between cells."
  :type 'color)

(defcustom nonogram-cross-color "#B03030"
  "Color of the cross mark drawn on a crossed cell."
  :type 'color)

(defcustom nonogram-dot-color "#111111"
  "Color of the small dot used as a `maybe filled here' visual hint."
  :type 'color)

(defcustom nonogram-clue-color "#111111"
  "Color of the clue numbers."
  :type 'color)

(defcustom nonogram-cursor-color "#E8901A"
  "Color of the ring that marks the cursor position."
  :type 'color)

(defvar nonogram--load-directory
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory this file was loaded from, used to locate bundled puzzles.")

(defcustom nonogram-puzzle-directory
  (expand-file-name "puzzles" nonogram--load-directory)
  "Directory scanned for puzzle files in Steven Simpson's .non format."
  :type 'directory)

(defcustom nonogram-puzzle-source-url
  "https://git.andros.dev/api/v1/repos/andros/nonogram.el/contents/puzzles"
  "Gitea contents-API URL listing the downloadable .non puzzles.
`nonogram-download-puzzles' reads this listing and fetches every
file it names.  Point it at any Gitea repository directory."
  :type 'string)

(defcustom nonogram-auto-download t
  "When non-nil, offer to download puzzles if the directory is empty.
The offer is made when the puzzle list is opened with no local
puzzles present."
  :type 'boolean)

;; ──────────────────────────────────────────────────────────────────
;; Game state
;; ──────────────────────────────────────────────────────────────────

(cl-defstruct (nonogram-game (:constructor nonogram--game-create))
  "State of a single nonogram game."
  name rows cols
  state                                 ; vector of row vectors of symbols
  row-clues col-clues                   ; lists of lists of integers
  cursor-row cursor-col
  won)

(defvar-local nonogram--game nil
  "The `nonogram-game' shown in the current buffer.")

(defvar-local nonogram--positions nil
  "Vector of row vectors holding the buffer position of each grid cell.")

(defvar-local nonogram--undo nil
  "Stack of (ROW COL PREVIOUS-STATE) entries for undo.")

(defvar-local nonogram--status-pos nil
  "Buffer position where the status area begins.")

;; ──────────────────────────────────────────────────────────────────
;; Puzzle parsing and clue computation
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--line-clues (cells)
  "Return the clue numbers for CELLS, a list of booleans.
Consecutive non-nil values become run lengths.  An empty line
yields (0)."
  (let ((res '())
        (run 0))
    (dolist (cell cells)
      (if cell
          (setq run (1+ run))
        (when (> run 0)
          (push run res)
          (setq run 0))))
    (when (> run 0)
      (push run res))
    (or (nreverse res) '(0))))

(defun nonogram--column-cells (solution col rows)
  "Return the list of booleans in column COL of SOLUTION for ROWS rows."
  (let ((res '()))
    (dotimes (r rows)
      (push (aref (aref solution r) col) res))
    (nreverse res)))

(defun nonogram--clues-from-goal (goal width height)
  "Return (ROW-CLUES . COL-CLUES) computed from GOAL for a WIDTH×HEIGHT grid.
GOAL is a row-major string of 1 (filled) and 0 (empty) characters."
  (let ((grid (make-vector height nil)))
    (dotimes (r height)
      (let ((rv (make-vector width nil)))
        (dotimes (c width)
          (aset rv c (eq (aref goal (+ (* r width) c)) ?1)))
        (aset grid r rv)))
    (cons (cl-loop for r below height
                   collect (nonogram--line-clues (append (aref grid r) nil)))
          (cl-loop for c below width
                   collect (nonogram--line-clues
                            (nonogram--column-cells grid c height))))))

(defun nonogram--parse-non (file)
  "Parse the .non FILE and return a plist describing the puzzle.
The plist keys are :name, :width, :height, :rows, :columns and :goal.
:rows and :columns are lists of clue lists.  Format reference:
Steven Simpson's .non, as exported by webpbn.com."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((name (file-name-base file))
          width height goal rows cols section)
      (while (not (eobp))
        (let ((line (string-trim
                     (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position)))))
          (cond
           ((string= line "") (setq section nil))
           ((string= line "rows") (setq section 'rows))
           ((string= line "columns") (setq section 'columns))
           ((string-match "\\`title +\"\\(.*\\)\"" line)
            (setq name (match-string 1 line) section nil))
           ((string-match "\\`width +\\([0-9]+\\)" line)
            (setq width (string-to-number (match-string 1 line)) section nil))
           ((string-match "\\`height +\\([0-9]+\\)" line)
            (setq height (string-to-number (match-string 1 line)) section nil))
           ((string-match "\\`goal +\"?\\([01]+\\)\"?" line)
            (setq goal (match-string 1 line) section nil))
           ((and section (string-match "\\`[0-9]" line))
            (let ((clue (mapcar #'string-to-number (split-string line "[ ,]+" t))))
              (if (eq section 'rows) (push clue rows) (push clue cols))))
           (t (setq section nil)))
          (forward-line 1)))
      (list :name name :width width :height height
            :rows (nreverse rows) :columns (nreverse cols) :goal goal))))

(defun nonogram--load-non (file)
  "Build a `nonogram-game' by reading the .non FILE."
  (let* ((p (nonogram--parse-non file))
         (rclues (plist-get p :rows))
         (cclues (plist-get p :columns))
         (goal (plist-get p :goal))
         (width  (or (plist-get p :width)  (length cclues)))
         (height (or (plist-get p :height) (length rclues))))
    ;; Derive the clues from GOAL when the file omits them.
    (when (and goal (or (null rclues) (null cclues))
               (> width 0) (> height 0))
      (let ((derived (nonogram--clues-from-goal goal width height)))
        (setq rclues (car derived) cclues (cdr derived))))
    (unless (and rclues cclues (> width 0) (> height 0))
      (user-error "Not a valid .non puzzle: %s" file))
    (let ((state (make-vector height nil)))
      (dotimes (r height)
        (aset state r (make-vector width 'blank)))
      (nonogram--game-create
       :name (plist-get p :name)
       :rows height :cols width :state state
       :row-clues rclues :col-clues cclues
       :cursor-row 0 :cursor-col 0 :won nil))))

(defun nonogram--puzzle-files ()
  "Return the sorted list of .non files in `nonogram-puzzle-directory'."
  (when (file-directory-p nonogram-puzzle-directory)
    (sort (directory-files nonogram-puzzle-directory t "\\.non\\'")
          #'string<)))

;; ──────────────────────────────────────────────────────────────────
;; Downloading puzzles
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--http-get-once (url)
  "Fetch URL once.  Return (STATUS . BODY); BODY is nil unless STATUS is 200."
  (require 'url)
  (let ((buffer (url-retrieve-synchronously url t t 30)))
    (unless buffer
      (error "Could not connect to %s" url))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (unless (re-search-forward "\\`HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
            (error "Malformed response from %s" url))
          (let ((status (string-to-number (match-string 1))))
            (if (/= status 200)
                (cons status nil)
              (goto-char (point-min))
              (unless (re-search-forward "\r?\n\r?\n" nil t)
                (error "No response body from %s" url))
              (cons 200 (buffer-substring-no-properties (point) (point-max))))))
      (kill-buffer buffer))))

(defun nonogram--http-get (url)
  "Return the body of an HTTP GET request to URL as a string.
Retry a few times, backing off, when the server answers 429 or 503.
Signal an error on a network failure or any other non-200 status."
  (let ((attempts 4)
        (delay 1))
    (catch 'done
      (while t
        (let* ((res (nonogram--http-get-once url))
               (status (car res)))
          (cond
           ((= status 200) (throw 'done (cdr res)))
           ((and (memq status '(429 503)) (> attempts 1))
            (setq attempts (1- attempts))
            (sleep-for delay)
            (setq delay (* delay 2)))
           (t (error "HTTP %d while fetching %s" status url))))))))

;;;###autoload
(defun nonogram-download-puzzles ()
  "Download all puzzles from `nonogram-puzzle-source-url'.
The files are written to `nonogram-puzzle-directory', overwriting
existing ones.  Run it to populate an empty directory or to update
the local puzzles to the latest published set.  Return the number
of puzzles downloaded."
  (interactive)
  (let* ((listing (nonogram--http-get nonogram-puzzle-source-url))
         (entries (json-parse-string listing
                                     :object-type 'alist :array-type 'list))
         (dir nonogram-puzzle-directory)
         (count 0))
    (make-directory dir t)
    (dolist (entry entries)
      (let ((name (alist-get 'name entry))
            (type (alist-get 'type entry))
            (url  (alist-get 'download_url entry)))
        (when (and (equal type "file") url
                   (stringp name) (string-suffix-p ".non" name))
          (when (> count 0) (sleep-for 0.2))
          (let ((body (nonogram--http-get url)))
            (with-temp-file (expand-file-name name dir)
              (insert body)))
          (setq count (1+ count)))))
    (message "Downloaded %d puzzle%s to %s"
             count (if (= count 1) "" "s") (abbreviate-file-name dir))
    count))

;; ──────────────────────────────────────────────────────────────────
;; SVG cell rendering
;;
;; Every cell is a space character whose `display' property holds a
;; fresh SVG image.  A new image object is built on every call: Emacs
;; renders a run of identical adjacent `display' objects only once, so
;; reusing an object would collapse equal neighbours into a single
;; picture.
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--cell-svg (kind &optional digit cursor)
  "Return the inner SVG markup (without the <svg> wrapper) for cell KIND.
KIND is one of `pad', `clue', `blank', `filled' or `crossed'.
DIGIT is the number string drawn when KIND is `clue'.  When CURSOR
is non-nil a highlight ring is drawn over the cell."
  (let* ((px    nonogram-cell-px)
         (inner (- px 2))
         (half  (/ px 2.0))
         (fsize (round (* px 0.6)))
         (grid  (memq kind '(blank filled crossed dot)))
         (fill  (if (eq kind 'filled)
                    nonogram-filled-color
                  nonogram-background-color))
         (parts '()))
    (if grid
        ;; Grid cells carry a full-size backing rect (the grid line)
        ;; with the fill inset by 1px on every side, so adjacent cells
        ;; share a 2px line between them.
        (progn
          (push (format "<rect width='%d' height='%d' fill='%s'/>"
                        px px nonogram-filled-color)
                parts)
          (push (format "<rect x='1' y='1' width='%d' height='%d' fill='%s'/>"
                        inner inner fill)
                parts))
      ;; Clue and pad cells are a plain opaque white square so the
      ;; whole board stays white regardless of the theme.
      (push (format "<rect width='%d' height='%d' fill='%s'/>"
                    px px nonogram-background-color)
            parts))
    (cond
     ((eq kind 'crossed)
      (push (nonogram--text half fsize nonogram-cross-color "✕") parts))
     ((eq kind 'dot)
      (push (format "<circle cx='%s' cy='%s' r='%s' fill='%s'/>"
                    half half (* px 0.18) nonogram-dot-color)
            parts))
     ((and (eq kind 'clue) digit)
      (push (nonogram--text half fsize nonogram-clue-color digit) parts)))
    (when cursor
      (push (format (concat "<rect x='2' y='2' width='%d' height='%d' "
                            "fill='none' stroke='%s' stroke-width='2' rx='2'/>")
                    (- px 4) (- px 4) nonogram-cursor-color)
            parts))
    (mapconcat #'identity (nreverse parts) "")))

(defun nonogram--cell-image (kind &optional digit cursor)
  "Return a fresh SVG image for cell KIND.
KIND, DIGIT and CURSOR are passed to `nonogram--cell-svg'.  A new
image object is built on every call so Emacs never coalesces
identical adjacent cells into a single picture."
  (create-image
   (format (concat "<svg xmlns='http://www.w3.org/2000/svg' "
                   "width='%d' height='%d'>%s</svg>")
           nonogram-cell-px nonogram-cell-px
           (nonogram--cell-svg kind digit cursor))
   'svg t :ascent 'center))

(defun nonogram--text (half fsize color str)
  "Return an SVG centered text element for STR.
HALF is the cell mid-point, FSIZE the font size and COLOR the fill."
  (format (concat "<text x='%s' y='%s' text-anchor='middle' "
                  "dominant-baseline='central' fill='%s' font-size='%d' "
                  "font-family='monospace' font-weight='bold'>%s</text>")
          half half color fsize str))

;; ──────────────────────────────────────────────────────────────────
;; Drawing the board
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--insert (kind &optional digit)
  "Insert a non-interactive cell of KIND with optional DIGIT."
  (insert (propertize " " 'display (nonogram--cell-image kind digit))))

(defun nonogram--insert-grid-cell (row col state cursor)
  "Insert the interactive grid cell at ROW, COL showing STATE.
Draw the cursor ring when CURSOR is non-nil, and remember the cell
position so mouse clicks and refreshes can find it."
  (aset (aref nonogram--positions row) col (point))
  (insert (propertize " "
                      'display (nonogram--cell-image state nil cursor)
                      'nonogram-cell (cons row col)
                      'rear-nonsticky t)))

(defun nonogram--redraw ()
  "Draw the whole board from scratch in the current buffer."
  (let* ((inhibit-read-only t)
         (game nonogram--game)
         (rows (nonogram-game-rows game))
         (cols (nonogram-game-cols game))
         (rclues (nonogram-game-row-clues game))
         (cclues (nonogram-game-col-clues game))
         (rw (apply #'max 1 (mapcar #'length rclues)))
         (ch (apply #'max 1 (mapcar #'length cclues)))
         (cur-row (nonogram-game-cursor-row game))
         (cur-col (nonogram-game-cursor-col game)))
    (setq nonogram--positions (make-vector rows nil))
    (dotimes (r rows)
      (aset nonogram--positions r (make-vector cols nil)))
    (erase-buffer)
    ;; Column-clue header.  A blank cell on the right keeps a white
    ;; margin down the whole right edge of the board.
    (dotimes (line ch)
      (dotimes (_ rw) (nonogram--insert 'pad))
      (dotimes (c cols)
        (let* ((clue (nth c cclues))
               (idx  (- line (- ch (length clue)))))
          (if (and (>= idx 0) (< idx (length clue)))
              (nonogram--insert 'clue (number-to-string (nth idx clue)))
            (nonogram--insert 'pad))))
      (nonogram--insert 'pad)
      (insert "\n"))
    ;; Grid rows, each preceded by its right-aligned row clue.
    (dotimes (r rows)
      (let* ((clue (nth r rclues))
             (offset (- rw (length clue))))
        (dotimes (i rw)
          (let ((idx (- i offset)))
            (if (and (>= idx 0) (< idx (length clue)))
                (nonogram--insert 'clue (number-to-string (nth idx clue)))
              (nonogram--insert 'pad)))))
      (dotimes (c cols)
        (nonogram--insert-grid-cell
         r c (aref (aref (nonogram-game-state game) r) c)
         (and (= r cur-row) (= c cur-col))))
      (nonogram--insert 'pad)
      (insert "\n"))
    ;; Bottom white margin: a full-width row of blank cells.
    (dotimes (_ (+ rw cols 1)) (nonogram--insert 'pad))
    (insert "\n\n")
    (setq nonogram--status-pos (point))
    (nonogram--insert-status)
    (nonogram--goto-cursor)))

(defconst nonogram--help
  '(("SPC / click"       . "fill a cell")
    ("x / right-click"   . "cross a cell")
    ("c / middle-click"  . "mark a maybe dot")
    ("arrows / h j k l"  . "move")
    ("n"                 . "random puzzle")
    ("u"                 . "undo")
    ("q"                 . "back to list"))
  "Control legend shown below the board, one entry per line.")

(defun nonogram--insert-status ()
  "Insert the status and help lines below the board."
  (let ((game nonogram--game)
        (width (apply #'max (mapcar (lambda (e) (length (car e)))
                                    nonogram--help))))
    (insert (format " %s\n\n" (nonogram-game-name game)))
    (when (nonogram-game-won game)
      (insert " Solved!  n for another · q for the list\n\n"))
    (let ((fmt (format " %%-%ds  %%s\n" width)))
      (dolist (entry nonogram--help)
        (insert (format fmt (car entry) (cdr entry)))))))

(defun nonogram--goto-cursor ()
  "Move point onto the current cursor cell."
  (let ((pos (aref (aref nonogram--positions
                         (nonogram-game-cursor-row nonogram--game))
                   (nonogram-game-cursor-col nonogram--game))))
    (when pos (goto-char pos))))

(defun nonogram--refresh-cell (row col)
  "Redraw only the grid cell at ROW, COL in place."
  (let ((pos (aref (aref nonogram--positions row) col))
        (inhibit-read-only t))
    (when pos
      (put-text-property
       pos (1+ pos) 'display
       (nonogram--cell-image
        (aref (aref (nonogram-game-state nonogram--game) row) col)
        nil
        (and (= row (nonogram-game-cursor-row nonogram--game))
             (= col (nonogram-game-cursor-col nonogram--game))))))))

(defun nonogram--refresh-status ()
  "Redraw the status area only."
  (let ((inhibit-read-only t))
    (when nonogram--status-pos
      (save-excursion
        (goto-char nonogram--status-pos)
        (delete-region (point) (point-max))
        (nonogram--insert-status)))))

;; ──────────────────────────────────────────────────────────────────
;; Movement
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--move (drow dcol)
  "Move the cursor by DROW rows and DCOL columns, clamped to the board."
  (let* ((game nonogram--game)
         (old-r (nonogram-game-cursor-row game))
         (old-c (nonogram-game-cursor-col game))
         (new-r (max 0 (min (1- (nonogram-game-rows game)) (+ old-r drow))))
         (new-c (max 0 (min (1- (nonogram-game-cols game)) (+ old-c dcol)))))
    (unless (and (= new-r old-r) (= new-c old-c))
      (setf (nonogram-game-cursor-row game) new-r
            (nonogram-game-cursor-col game) new-c)
      (nonogram--refresh-cell old-r old-c)
      (nonogram--refresh-cell new-r new-c))
    (nonogram--goto-cursor)))

(defun nonogram-move-up ()    "Move the cursor up."    (interactive) (nonogram--move -1 0))
(defun nonogram-move-down ()  "Move the cursor down."  (interactive) (nonogram--move 1 0))
(defun nonogram-move-left ()  "Move the cursor left."  (interactive) (nonogram--move 0 -1))
(defun nonogram-move-right () "Move the cursor right." (interactive) (nonogram--move 0 1))

;; ──────────────────────────────────────────────────────────────────
;; Marking cells
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--set-cell (row col new-state)
  "Set the cell at ROW, COL to NEW-STATE, recording it for undo."
  (let* ((game nonogram--game)
         (state (nonogram-game-state game))
         (old (aref (aref state row) col)))
    (unless (eq old new-state)
      (push (list row col old) nonogram--undo)
      (aset (aref state row) col new-state)
      (nonogram--refresh-cell row col)
      (nonogram--check-win))))

(defun nonogram--toggle (kind)
  "Toggle the cursor cell between blank and KIND (`filled' or `crossed')."
  (let* ((game nonogram--game)
         (row (nonogram-game-cursor-row game))
         (col (nonogram-game-cursor-col game))
         (cur (aref (aref (nonogram-game-state game) row) col)))
    (nonogram--set-cell row col (if (eq cur kind) 'blank kind))))

(defun nonogram-toggle-fill ()
  "Toggle the black fill of the cursor cell."
  (interactive)
  (nonogram--toggle 'filled))

(defun nonogram-toggle-cross ()
  "Toggle the cross mark of the cursor cell."
  (interactive)
  (nonogram--toggle 'crossed))

(defun nonogram-toggle-dot ()
  "Toggle the dot hint of the cursor cell.
The dot is a visual aid marking a cell you suspect might be filled;
it does not count as filled for solving."
  (interactive)
  (nonogram--toggle 'dot))

(defun nonogram-undo ()
  "Undo the last fill or cross."
  (interactive)
  (if (null nonogram--undo)
      (message "Nothing to undo")
    (let* ((entry (pop nonogram--undo))
           (row (nth 0 entry))
           (col (nth 1 entry)))
      (aset (aref (nonogram-game-state nonogram--game) row) col (nth 2 entry))
      (nonogram--refresh-cell row col)
      (nonogram--check-win))))

;; ──────────────────────────────────────────────────────────────────
;; Mouse
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--mouse-cell (event)
  "Return the (ROW . COL) of the cell clicked in EVENT, or nil."
  (let ((pos (posn-point (event-end event))))
    (and pos (get-text-property pos 'nonogram-cell))))

(defun nonogram--mouse-act (event kind)
  "Move the cursor to the cell clicked in EVENT and toggle it to KIND."
  (let ((cell (nonogram--mouse-cell event)))
    (when cell
      (let ((old-r (nonogram-game-cursor-row nonogram--game))
            (old-c (nonogram-game-cursor-col nonogram--game)))
        (setf (nonogram-game-cursor-row nonogram--game) (car cell)
              (nonogram-game-cursor-col nonogram--game) (cdr cell))
        (nonogram--refresh-cell old-r old-c))
      (nonogram--toggle kind)
      (nonogram--goto-cursor))))

(defun nonogram-mouse-fill (event)
  "Toggle the fill of the cell clicked in EVENT."
  (interactive "e")
  (nonogram--mouse-act event 'filled))

(defun nonogram-mouse-cross (event)
  "Toggle the cross of the cell clicked in EVENT."
  (interactive "e")
  (nonogram--mouse-act event 'crossed))

(defun nonogram-mouse-dot (event)
  "Toggle the dot hint of the cell clicked in EVENT."
  (interactive "e")
  (nonogram--mouse-act event 'dot))

;; ──────────────────────────────────────────────────────────────────
;; Win detection
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--state-runs (states)
  "Return the run lengths of `filled' cells in STATES, a list of state symbols."
  (nonogram--line-clues (mapcar (lambda (s) (eq s 'filled)) states)))

(defun nonogram--solved-p ()
  "Return non-nil when the filled cells satisfy every row and column clue."
  (let* ((game  nonogram--game)
         (rows  (nonogram-game-rows game))
         (cols  (nonogram-game-cols game))
         (state (nonogram-game-state game)))
    (and (cl-loop for r below rows
                  always (equal (nonogram--state-runs (append (aref state r) nil))
                                (nth r (nonogram-game-row-clues game))))
         (cl-loop for c below cols
                  always (equal (nonogram--state-runs
                                 (cl-loop for r below rows
                                          collect (aref (aref state r) c)))
                                (nth c (nonogram-game-col-clues game)))))))

(defun nonogram--check-win ()
  "Update the won flag and status when the puzzle becomes solved."
  (let ((was (nonogram-game-won nonogram--game))
        (now (nonogram--solved-p)))
    (unless (eq was now)
      (setf (nonogram-game-won nonogram--game) now)
      (nonogram--refresh-status)
      (when now
        (message "Solved!")))))

;; ──────────────────────────────────────────────────────────────────
;; New game
;; ──────────────────────────────────────────────────────────────────

(defun nonogram--start (file)
  "Reset the current buffer to play the puzzle in FILE."
  (setq nonogram--game (nonogram--load-non file)
        nonogram--undo nil)
  (nonogram--redraw))

(defun nonogram-new ()
  "Load a random puzzle from `nonogram-puzzle-directory'."
  (interactive)
  (let ((files (nonogram--puzzle-files)))
    (if files
        (nonogram--start (seq-random-elt files))
      (user-error "No .non puzzles found in %s" nonogram-puzzle-directory))))

;; ──────────────────────────────────────────────────────────────────
;; Mode
;; ──────────────────────────────────────────────────────────────────

(defvar nonogram-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") #'nonogram-toggle-fill)
    (define-key map (kbd "RET") #'nonogram-toggle-fill)
    (define-key map (kbd "x")   #'nonogram-toggle-cross)
    (define-key map (kbd "X")   #'nonogram-toggle-cross)
    (define-key map (kbd "c")   #'nonogram-toggle-dot)
    (define-key map (kbd "<up>")    #'nonogram-move-up)
    (define-key map (kbd "<down>")  #'nonogram-move-down)
    (define-key map (kbd "<left>")  #'nonogram-move-left)
    (define-key map (kbd "<right>") #'nonogram-move-right)
    (define-key map (kbd "k") #'nonogram-move-up)
    (define-key map (kbd "j") #'nonogram-move-down)
    (define-key map (kbd "h") #'nonogram-move-left)
    (define-key map (kbd "l") #'nonogram-move-right)
    (define-key map (kbd "n") #'nonogram-new)
    (define-key map (kbd "u") #'nonogram-undo)
    (define-key map (kbd "q") #'nonogram-menu)
    (define-key map [mouse-1] #'nonogram-mouse-fill)
    (define-key map [mouse-3] #'nonogram-mouse-cross)
    (define-key map [mouse-2] #'nonogram-mouse-dot)
    map)
  "Keymap for `nonogram-mode'.")

(define-derived-mode nonogram-mode special-mode "Nonogram"
  "Major mode for playing nonogram puzzles.

\\{nonogram-mode-map}"
  (setq-local truncate-lines t
              cursor-type nil
              buffer-read-only t))

;; ──────────────────────────────────────────────────────────────────
;; Puzzle menu
;; ──────────────────────────────────────────────────────────────────

(defvar nonogram-menu-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET")     #'nonogram-menu-open)
    (define-key map [mouse-1]       #'nonogram-menu-open)
    (define-key map (kbd "n")       #'next-line)
    (define-key map (kbd "p")       #'previous-line)
    (define-key map (kbd "j")       #'next-line)
    (define-key map (kbd "k")       #'previous-line)
    (define-key map (kbd "g")       #'nonogram-menu)
    (define-key map (kbd "U")       #'nonogram-menu-update)
    map)
  "Keymap for `nonogram-menu-mode'.")

(define-derived-mode nonogram-menu-mode special-mode "Nonogram Menu"
  "Major mode listing the available nonogram puzzles.

\\{nonogram-menu-mode-map}"
  (setq-local truncate-lines t))

(defun nonogram--draw-menu ()
  "Fill the current buffer with the list of available puzzles."
  (let ((inhibit-read-only t)
        (files (nonogram--puzzle-files)))
    (erase-buffer)
    (setq-local header-line-format " Nonogram   RET play   U update   q quit")
    (if (null files)
        (insert (format "No .non files in %s\n" nonogram-puzzle-directory))
      (dolist (file files)
        (let* ((p (nonogram--parse-non file))
               (w (or (plist-get p :width)  (length (plist-get p :columns))))
               (h (or (plist-get p :height) (length (plist-get p :rows)))))
          (insert (propertize
                   (concat (plist-get p :name)
                           (propertize (format "  %d×%d" w h) 'face 'shadow)
                           "\n")
                   'nonogram-file file
                   'mouse-face 'highlight)))))
    (goto-char (point-min))))

(defun nonogram-menu-open ()
  "Play the puzzle on the current line."
  (interactive)
  (let ((file (get-text-property (point) 'nonogram-file)))
    (if (null file)
        (message "Point is not on a puzzle")
      (nonogram-mode)
      (nonogram--start file))))

(defun nonogram-menu-update ()
  "Download the latest puzzles and refresh the list."
  (interactive)
  (nonogram-download-puzzles)
  (nonogram--draw-menu))

;;;###autoload
(defun nonogram-menu ()
  "Show the list of available nonogram puzzles.
When the directory is empty and `nonogram-auto-download' is on,
offer to download the default puzzle set first."
  (interactive)
  (unless (image-type-available-p 'svg)
    (user-error "Nonogram needs an Emacs built with SVG (librsvg) support"))
  (when (and nonogram-auto-download
             (null (nonogram--puzzle-files))
             (y-or-n-p "No puzzles found.  Download the default set? "))
    (condition-case err
        (nonogram-download-puzzles)
      (error (message "Puzzle download failed: %s"
                      (error-message-string err)))))
  (let ((buf (get-buffer-create "*nonogram*")))
    (with-current-buffer buf
      (nonogram-menu-mode)
      (nonogram--draw-menu))
    (switch-to-buffer buf)))

;;;###autoload
(defun nonogram ()
  "Play nonogram: open the list of available puzzles."
  (interactive)
  (nonogram-menu))

(provide 'nonogram)
;;; nonogram.el ends here
