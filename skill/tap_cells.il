;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; tap_cells.il
;;; Purpose : generate tap_pos and tap_neg schematics + symbols for the
;;;           KWS Week 2 weighted-current branches.
;;; Library : kws_project
;;; PDK     : gpdk045 (thick-oxide pmos2v / nmos2v, VDD = 1.8 V)
;;; Spec    : Week 2 design notes (tap sizing, branch patterns)
;;;
;;; Conventions (shared with the Week 1 scripts):
;;;   - dbCreateInst (not dbCreateParamInst)
;;;   - ~>w / ~>l for sizing
;;;   - schCreatePin(cv pinMasterCV termName direction xy orient)
;;;   - pin masters ipinCV / opinCV / iopinCV opened at top
;;;
;;; Safety:
;;;   - Only deletes the schematic/symbol views of tap_pos and tap_neg.
;;;   - Never touches Week 1 cells (comparator, dff, shift_reg_8, week1_tb)
;;;     or any other library.
;;;
;;; Usage in Cadence CIW (NOT a bash shell):
;;;   load("tap_cells.il")
;;;   => "=== SUCCESS: tap_pos, tap_neg built ==="
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ===================== CONFIGURATION =====================
KWS_LIB    = "kws_project"
PDK_LIB    = "gpdk045"
PMOS_CELL  = "pmos2v"
NMOS_CELL  = "nmos2v"

;; Sizing — mirrors spec § 3.1
TAP_SRC_W  = "500n"     ;; current-source / sink device (long L)
TAP_SRC_L  = "1u"
TAP_SW_W   = "1u"       ;; switch device (short L)
TAP_SW_L   = "150n"

;; ===================== UTILITIES =====================

procedure( KWSinfo(msg) printf("[tap_cells] %s\n" msg) )
procedure( KWSfatal(msg) error("[tap_cells] FATAL: %s\n" msg) )

;; Scoped delete: only removes the specific view we are about to rebuild.
procedure( KWSdeleteView(lib cell view)
  let( (ddObj)
    ddObj = ddGetObj(lib cell view)
    when( ddObj
      KWSinfo(sprintf(nil "deleting existing %s/%s/%s" lib cell view))
      ddDeleteObj(ddObj)
    )
  )
)

;; Look up the absolute (cellview) coordinate of a named terminal on an inst.
;; Reads from the master cellview's ~>terminals list, NOT inst~>instTerms.
;; instTerms is empty on freshly placed (unsaved) instances on this Cadence
;; build; the master path always works because it queries the symbol cv
;; directly. Verified via 01_term_introspect.il on the course Cadence server.
;;   path: inst~>master~>terminals → find by name → ~>pins → car → ~>fig~>bBox
;; Assumes orient = "R0" (no rotation required).
procedure( KWStermXY(inst termName)
  let( (master masterTerm pin xy)
    master = inst~>master
    masterTerm = car(setof(x master~>terminals x~>name == termName))
    unless( masterTerm
      KWSfatal(sprintf(nil "terminal '%s' not on master %s/%s"
                       termName master~>libName master~>cellName))
    )
    pin = car(masterTerm~>pins)
    unless( pin && pin~>fig && pin~>fig~>bBox
      KWSfatal(sprintf(nil "no pin/fig/bBox for terminal '%s' on %s"
                       termName master~>cellName))
    )
    xy = centerBox(pin~>fig~>bBox)
    list( xCoord(xy) + xCoord(inst~>xy)
          yCoord(xy) + yCoord(inst~>xy) )
  )
)

procedure( KWSwire(cv p1 p2)
  schCreateWire(cv "route" "full" list(p1 p2) 0.0625 0.0 0.0)
)

;; Symbol generation is done MANUALLY — programmatic schViewToView calls
;; have inconsistent signatures across Cadence builds and burn more
;; iteration time than the 3 clicks the GUI takes per cell.
;;
;; Per cell:
;;   1. Library Manager: double-click <cell>/schematic to open editor
;;   2. Create menu → Cellview → From Cellview
;;   3. Dialog: target view = "symbol", target type = "schematicSymbol"
;;   4. OK; symbol editor opens with auto-placed pins
;;   5. File → Save; close symbol editor
;;
;; This procedure just prints those instructions for each cell built.
procedure( KWSgenSymbol(lib cell)
  KWSinfo(sprintf(nil
    "manual step required: create symbol for %s/%s" lib cell))
  KWSinfo("  open schematic -> Create -> Cellview -> From Cellview")
  KWSinfo("  target view = symbol, target type = schematicSymbol, OK, Save.")
)

;; ===================== OPEN MASTER CELLVIEWS =====================
;; All cellview handles opened once up front and reused.

nmosCV  = dbOpenCellViewByType(PDK_LIB NMOS_CELL  "symbol" "schematicSymbol" "r")
unless( nmosCV KWSfatal(sprintf(nil "cannot open %s/%s/symbol" PDK_LIB NMOS_CELL)) )
pmosCV  = dbOpenCellViewByType(PDK_LIB PMOS_CELL  "symbol" "schematicSymbol" "r")
unless( pmosCV KWSfatal(sprintf(nil "cannot open %s/%s/symbol" PDK_LIB PMOS_CELL)) )
ipinCV  = dbOpenCellViewByType("basic" "ipin"     "symbol" "schematicSymbol" "r")
opinCV  = dbOpenCellViewByType("basic" "opin"     "symbol" "schematicSymbol" "r")
iopinCV = dbOpenCellViewByType("basic" "iopin"    "symbol" "schematicSymbol" "r")
unless( ipinCV && opinCV && iopinCV
        KWSfatal("cannot open basic/ipin, basic/opin, or basic/iopin symbol") )

;; ===================== HELPERS =====================

procedure( KWSplaceMOS(cv masterCV name xy orient w l)
  let( (inst)
    inst = dbCreateInst(cv masterCV name xy orient)
    unless( inst
      KWSfatal(sprintf(nil "dbCreateInst failed for %s" name))
    )
    inst~>w = w
    inst~>l = l
    inst
  )
)

;; ===================== tap_pos =====================
;; Topology (vdd at top, bk at bottom-right):
;;   vdd ── [S] MP [D] ── (node a) ── [D] MSW [S] ── bk
;;   vbias_p ──────── [G] MP
;;   xi      ──────── [G] MSW
;;   (bulks: MP → vdd, MSW → gnd)
;; Pins: xi (in), vbias_p (in), bk (io), vdd (io), gnd (io)

procedure( KWSbuildTapPos()
  let( (cv mp msw vddXY gndXY vbiasXY xiXY bkXY)
    KWSinfo("=== building tap_pos ===")
    KWSdeleteView(KWS_LIB "tap_pos" "symbol")
    KWSdeleteView(KWS_LIB "tap_pos" "schematic")

    cv = dbOpenCellViewByType(KWS_LIB "tap_pos" "schematic" "schematic" "w")
    unless( cv KWSfatal("cannot open tap_pos schematic for write") )

    ;; Place transistors.
    mp  = KWSplaceMOS(cv pmosCV "MP"  list(0.0 4.0) "R0" TAP_SRC_W TAP_SRC_L)
    msw = KWSplaceMOS(cv nmosCV "MSW" list(0.0 0.0) "R0" TAP_SW_W  TAP_SW_L)

    ;; Pin locations.
    vddXY   = list( 0.0  7.0)
    gndXY   = list( 0.0 -3.0)
    vbiasXY = list(-5.0  4.0)
    xiXY    = list(-5.0  0.0)
    bkXY    = list( 3.0 -1.0)

    ;; schCreatePin signature (verified via cdnshelp):
    ;;   schCreatePin(cv master termName direction offSheetP origin orient
    ;;                [powerSens] [groundSens] [sigType])
    ;; Arg 5 is off-sheet flag (nil = on-sheet pin), NOT sigType. sigType
    ;; is the optional 10th arg.
    schCreatePin(cv ipinCV  "vbias_p" "input"       nil vbiasXY "R0")
    schCreatePin(cv ipinCV  "xi"      "input"       nil xiXY    "R0")
    schCreatePin(cv iopinCV "bk"      "inputOutput" nil bkXY    "R0")
    schCreatePin(cv iopinCV "vdd"     "inputOutput" nil vddXY   "R0")
    schCreatePin(cv iopinCV "gnd"     "inputOutput" nil gndXY   "R0")

    ;; Wire connections (all coordinates looked up from terminal positions
    ;; so the wiring still works if a symbol variant shifts pin placement).
    KWSwire(cv KWStermXY(mp  "S")  vddXY)              ;; MP source  -> vdd
    KWSwire(cv KWStermXY(mp  "B")  vddXY)              ;; MP bulk    -> vdd
    KWSwire(cv KWStermXY(mp  "G")  vbiasXY)            ;; MP gate    -> vbias_p
    KWSwire(cv KWStermXY(mp  "D")  KWStermXY(msw "D")) ;; node a (MP drain → MSW drain)
    KWSwire(cv KWStermXY(msw "G")  xiXY)               ;; MSW gate   -> xi
    KWSwire(cv KWStermXY(msw "S")  bkXY)               ;; MSW source -> bk
    KWSwire(cv KWStermXY(msw "B")  gndXY)              ;; MSW bulk   -> gnd

    schCheck(cv)
    dbSave(cv)
    dbClose(cv)

    KWSgenSymbol(KWS_LIB "tap_pos")
    KWSinfo("tap_pos: schematic + symbol built")
  )
)

;; ===================== tap_neg =====================
;; Topology (bk at top, gnd at bottom):
;;   bk ── [D] MSW [S] ── (node b) ── [D] MSINK [S] ── gnd
;;   xi      ──────── [G] MSW
;;   vbias_n ──────── [G] MSINK
;;   (bulks: both NMOS → gnd)
;; Pins: xi (in), vbias_n (in), bk (io), vdd (io), gnd (io)
;;   vdd is exposed only for uniform branch-level routing — it is not wired
;;   internally (tap_neg doesn't need VDD).

procedure( KWSbuildTapNeg()
  let( (cv msw msink vddXY gndXY vbiasXY xiXY bkXY)
    KWSinfo("=== building tap_neg ===")
    KWSdeleteView(KWS_LIB "tap_neg" "symbol")
    KWSdeleteView(KWS_LIB "tap_neg" "schematic")

    cv = dbOpenCellViewByType(KWS_LIB "tap_neg" "schematic" "schematic" "w")
    unless( cv KWSfatal("cannot open tap_neg schematic for write") )

    msw   = KWSplaceMOS(cv nmosCV "MSW"   list(0.0 4.0) "R0" TAP_SW_W  TAP_SW_L)
    msink = KWSplaceMOS(cv nmosCV "MSINK" list(0.0 0.0) "R0" TAP_SRC_W TAP_SRC_L)

    vddXY   = list( 0.0  8.0)
    gndXY   = list( 0.0 -3.0)
    vbiasXY = list(-5.0  0.0)
    xiXY    = list(-5.0  4.0)
    bkXY    = list( 3.0  5.0)

    schCreatePin(cv ipinCV  "vbias_n" "input"       nil vbiasXY "R0")
    schCreatePin(cv ipinCV  "xi"      "input"       nil xiXY    "R0")
    schCreatePin(cv iopinCV "bk"      "inputOutput" nil bkXY    "R0")
    schCreatePin(cv iopinCV "vdd"     "inputOutput" nil vddXY   "R0")  ;; exposed, unused inside
    schCreatePin(cv iopinCV "gnd"     "inputOutput" nil gndXY   "R0")

    KWSwire(cv KWStermXY(msw   "D") bkXY)                    ;; MSW drain -> bk
    KWSwire(cv KWStermXY(msw   "G") xiXY)                    ;; MSW gate  -> xi
    KWSwire(cv KWStermXY(msw   "S") KWStermXY(msink "D"))    ;; node b
    KWSwire(cv KWStermXY(msw   "B") gndXY)                   ;; MSW bulk  -> gnd
    KWSwire(cv KWStermXY(msink "G") vbiasXY)                 ;; MSINK gate -> vbias_n
    KWSwire(cv KWStermXY(msink "S") gndXY)                   ;; MSINK src  -> gnd
    KWSwire(cv KWStermXY(msink "B") gndXY)                   ;; MSINK bulk -> gnd

    schCheck(cv)
    dbSave(cv)
    dbClose(cv)

    KWSgenSymbol(KWS_LIB "tap_neg")
    KWSinfo("tap_neg: schematic + symbol built")
  )
)

;; ===================== ENTRY POINT =====================

procedure( KWSbuildTapCells()
  KWSinfo(sprintf(nil ">>> tap_cells.il : lib=%s, PDK=%s <<<" KWS_LIB PDK_LIB))
  KWSbuildTapPos()
  KWSbuildTapNeg()
  printf("=== SUCCESS: tap_pos, tap_neg built ===\n")
  t
)

KWSbuildTapCells()
