;;; nonogram-preview.el --- Visual mid-game preview of nonogram.el  -*- lexical-binding: t; -*-

;; To run: M-x load-file RET nonogram-preview.el RET

;;; Code:

;; ──────────────────────────────────────────────────────────────────
;; SVG cell rendering
;;
;; Each game cell is a buffer space-char whose 'display property
;; holds an SVG image: a perfect square with a character inside.
;; Column-clue cells are also SVG of the same size → exact alignment.
;; ──────────────────────────────────────────────────────────────────

(defcustom np-cell-px 22
  "Size in pixels of each grid cell (width = height).
Increase for larger displays; decrease for compact layouts.
Call `nonogram-preview' again after changing this value."
  :type 'integer
  :group 'nonogram-preview)

(defconst np-colors
  '((space   . (:bg "none"    :fg nil      :ch nil))
    (blank   . (:bg "#FFFFFF" :fg nil      :ch nil))
    (filled  . (:bg "#111111" :fg nil      :ch nil))
    (crossed . (:bg "#FFFFFF" :fg "#222222" :ch "X"))
    (cursor  . (:bg "#FFF5A0" :fg "#664400" :ch nil))
    (clue    . (:bg "none"    :fg "#111111" :ch nil)))
  "Color and character definitions for each cell kind.")

;; Game cells: full SVG has a black background rect, then the colored
;; fill rect inset by 1px. Adjacent cells share the 1px black border
;; on each side → 2px black grid line between cells. Space/clue cells
;; stay transparent (no black backing).
(defconst np-grid-color "#111111" "Color of the grid lines between cells.")

(defun np--svg (kind &optional override-ch)
  "Return an SVG image spec for cell KIND, optionally with OVERRIDE-CH as label."
  (let* ((spec     (alist-get kind np-colors))
         (bg       (plist-get spec :bg))
         (fg       (plist-get spec :fg))
         (ch       (or override-ch (plist-get spec :ch)))
         (px       np-cell-px)
         (inner    (- px 2))
         (half     (/ px 2))
         (fsize    (round (* px 0.52)))
         (game-p   (not (string= bg "none")))
         (backing  (if game-p
                       (format "<rect width='%d' height='%d' fill='%s'/>"
                               px px np-grid-color)
                     ""))
         (rect     (if game-p
                       (format "<rect x='1' y='1' width='%d' height='%d' fill='%s'/>"
                               inner inner bg)
                     ""))
         (body  (if (and ch fg)
                    (format (concat "<text x='%d' y='%d' "
                                    "text-anchor='middle' "
                                    "dominant-baseline='central' "
                                    "fill='%s' "
                                    "font-size='%d' "
                                    "font-family='monospace'>%s</text>")
                            half half fg fsize ch)
                  ""))
         (svg   (format (concat "<svg xmlns='http://www.w3.org/2000/svg' "
                                "width='%d' height='%d'>"
                                "%s%s%s</svg>")
                        px px backing rect body)))
    (create-image svg 'svg t :ascent 'center)))

;; Each call to np--cell-img returns a FRESH image object.
;; Emacs coalesces adjacent characters that share the exact same
;; display-property object, showing the image only once. Fresh objects
;; prevent that — every cell is rendered individually.
(defun np--cell-img (kind)
  "Return a fresh SVG image for KIND (never reuses the same object)."
  (np--svg kind))

(defun np--clue-img (digit-str)
  "Return a fresh SVG clue image for DIGIT-STR."
  (np--svg 'clue digit-str))

;; ──────────────────────────────────────────────────────────────────
;; Buffer insertion helpers
;; ──────────────────────────────────────────────────────────────────

(defun np--ins-cell (kind &optional override-ch)
  "Insert one cell of KIND, generating a fresh image to prevent coalescing."
  (insert (propertize " " 'display (np--svg kind override-ch))))

(defun np--ins-text (str face)
  (insert (propertize str 'face face)))

;; ──────────────────────────────────────────────────────────────────
;; Faces for text areas
;; ──────────────────────────────────────────────────────────────────

(defface np-face-title
  '((t :foreground "#7AA2F7" :weight bold :height 1.3))
  "Title."
  :group 'nonogram-preview)

(defface np-face-subtitle
  '((t :foreground "#3D4166"))
  "Subtitle."
  :group 'nonogram-preview)

(defface np-face-row-clue
  '((t :foreground "#111111" :family "monospace"))
  "Row clue text."
  :group 'nonogram-preview)

(defface np-face-annotation
  '((t :foreground "#3D4166" :slant italic))
  "Row annotation."
  :group 'nonogram-preview)

(defface np-face-legend-key
  '((t :foreground "#BB9AF7" :weight bold))
  "Legend keybinding."
  :group 'nonogram-preview)

(defface np-face-legend
  '((t :foreground "#3D4166"))
  "Legend text."
  :group 'nonogram-preview)

(defgroup nonogram-preview nil
  "Visual preview for nonogram.el."
  :group 'games)

;; ──────────────────────────────────────────────────────────────────
;; Puzzle: 8×8 smiley face (mid-game)
;;
;;   Solution:   . # # # # # # .
;;               # . . . . . . #
;;               # . # . . # . #
;;               # . . . . . . #
;;               # . # # # # . #
;;               # . . . . . . #
;;               . # . . . . # .
;;               . . # # # # . .
;; ──────────────────────────────────────────────────────────────────

(defconst np-col-clues '((5) (1 1) (1 1 1) (1 1 1) (1 1 1) (1 1 1 1) (1 1) (5)))
(defconst np-row-clues '((6) (1 1) (1 1 1 1) (1 1) (1 4 1) (1 1) (1 1) (4)))

;; Cell kinds per row×col: blank filled crossed cursor
(defconst np-grid
  ;; blank=vacía(blanco), filled=marcada(negro), crossed=posibilidad(blanco+X)
  '((blank   filled  filled  filled  filled  filled  filled  blank)    ; 0
    (filled  blank   blank   blank   blank   blank   blank   filled)   ; 1
    (filled  blank   filled  blank   blank   filled  blank   filled)   ; 2 ojos
    (filled  crossed crossed cursor  crossed crossed crossed filled)   ; 3 posibilidades
    (filled  blank   filled  filled  filled  filled  blank   filled)   ; 4 sonrisa
    (filled  crossed crossed crossed crossed crossed crossed filled)   ; 5 posibilidades
    (blank   blank   blank   blank   blank   blank   blank   blank)    ; 6 vacío
    (blank   blank   filled  filled  filled  filled  blank   blank))  ; 7
  )

(defconst np-annotations nil)

;; ──────────────────────────────────────────────────────────────────
;; Layout constants
;; ──────────────────────────────────────────────────────────────────

(defconst np-n-cols 8)
(defconst np-n-rows 8)
(defconst np-row-clue-w 10 "Width in chars of the row-clue margin.")

;; ──────────────────────────────────────────────────────────────────
;; Drawing sections
;; ──────────────────────────────────────────────────────────────────

(defun np--draw-title ()
  (insert "\n"))

(defun np--draw-col-clues ()
  "Emit column clue rows (SVG cells, same width as grid cells)."
  (let* ((max-h (apply #'max (mapcar #'length np-col-clues))))
    (dotimes (line max-h)
      ;; Indent to match row-clue margin
      (insert (make-string np-row-clue-w ?\s))
      (dotimes (col np-n-cols)
        (let* ((clues  (nth col np-col-clues))
               (offset (- max-h (length clues)))
               (idx    (- line offset)))
          (if (and (>= idx 0) (< idx (length clues)))
              (np--ins-cell 'clue (number-to-string (nth idx clues)))
            (np--ins-cell 'space))))
      (insert "\n"))))

(defun np--draw-grid ()
  "Emit grid rows: row-clue text + SVG cells + annotation."
  (dotimes (row np-n-rows)
    ;; Row clue (right-aligned text)
    (let* ((clues (nth row np-row-clues))
           (str   (mapconcat #'number-to-string clues " "))
           (pad   (format (format "%%%ds " (1- np-row-clue-w)) str)))
      (np--ins-text pad 'np-face-row-clue))
    ;; Grid cells — each call generates a fresh image object
    (dolist (kind (nth row np-grid))
      (np--ins-cell kind))
    ;; Annotation
    (let ((ann (alist-get row np-annotations)))
      (when ann
        (insert "  ")
        (np--ins-text ann 'np-face-annotation)))
    (insert "\n")))


;; ──────────────────────────────────────────────────────────────────
;; Entry point
;; ──────────────────────────────────────────────────────────────────

;;;###autoload
(defun nonogram-preview ()
  "Open a visual mid-game preview of nonogram.el."
  (interactive)
  (unless (image-type-available-p 'svg)
    (error "SVG image support required (Emacs built with librsvg)"))
  (let ((buf (get-buffer-create "*nonogram-preview*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (np--draw-title)
        (np--draw-col-clues)
        (np--draw-grid))
      (setq truncate-lines t)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)
    ;; Ensure the frame is wide enough to show all columns without wrapping
    (when (< (frame-width) 80)
      (set-frame-width nil 80))))

(nonogram-preview)

;;; nonogram-preview.el ends here
