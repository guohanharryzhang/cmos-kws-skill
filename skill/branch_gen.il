;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; branch_gen.il
;;; Purpose : parametrized generator for Week 2 feature branches.
;;; Library : kws_project
;;; Dependencies : tap_cells.il must have been run first (needs tap_pos,
;;;                tap_neg symbols to instantiate).
;;;
;;; Public function:
;;;   buildBranch( t_name t_pattern )
;;;
;;;   - t_name    : cell-name suffix, e.g. "A" → creates cell branch_A
;;;   - t_pattern : 8-character string of '+' and '-'.
;;;                 Position 0 of the string maps to tap x0,
;;;                 position 7 maps to tap x7. Left-to-right = x0-to-x7.
;;;
;;; Example (in CIW):
;;;   load("branch_gen.il")
;;;   buildBranch("A" "+-+-+-+-")      ;; x0,x2,x4,x6 positive; x1,x3,x5,x7 negative
;;;   buildBranch("B" "++++----")      ;; x0..x3 positive; x4..x7 negative
;;;
;;; Safety: only deletes schematic/symbol of branch_<name>. Does not touch
;;; tap_pos, tap_neg, any Week 1 cell, or any other library.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ===================== CONFIGURATION =====================
KWS_LIB     = "kws_project"
ANALOG_LIB  = "analogLib"
R_LOAD_OHM  = "100K"          ;; 100 kΩ load resistor on bk
KWS_TAP_DX  = 10.0            ;; horizontal pitch between adjacent taps

;; ===================== UTILITIES =====================

procedure( KWSBinfo(msg)  printf("[branch_gen] %s\n" msg) )
procedure( KWSBfatal(msg) error("[branch_gen] FATAL: %s\n" msg) )

procedure( KWSBdeleteView(lib cell view)
  let( (ddObj)
    ddObj = ddGetObj(lib cell view)
    when( ddObj
      KWSBinfo(sprintf(nil "deleting %s/%s/%s" lib cell view))
      ddDeleteObj(ddObj)
    )
  )
)

;; See KWStermXY in tap_cells.il for the rationale — uses master~>terminals
;; because inst~>instTerms is empty on freshly placed instances on this build.
procedure( KWSBtermXY(inst termName)
  let( (master masterTerm pin xy)
    master = inst~>master
    masterTerm = car(setof(x master~>terminals x~>name == termName))
    unless( masterTerm
      KWSBfatal(sprintf(nil "term '%s' not on master %s/%s"
                        termName master~>libName master~>cellName))
    )
    pin = car(masterTerm~>pins)
    unless( pin && pin~>fig && pin~>fig~>bBox
      KWSBfatal(sprintf(nil "no pin/fig/bBox for term '%s' on %s"
                        termName master~>cellName))
    )
    xy = centerBox(pin~>fig~>bBox)
    list( xCoord(xy) + xCoord(inst~>xy)
          yCoord(xy) + yCoord(inst~>xy) )
  )
)

procedure( KWSBwire(cv p1 p2)
  schCreateWire(cv "route" "full" list(p1 p2) 0.0625 0.0 0.0)
)

procedure( KWSBvalidatePattern(pattern)
  unless( stringp(pattern) && (strlen(pattern) == 8)
    KWSBfatal(sprintf(nil "pattern must be an 8-char string, got '%s'"
                      pattern))
  )
  for( i 0 7
    let( (ch)
      ch = substring(pattern i + 1 1)
      unless( (ch == "+") || (ch == "-")
        KWSBfatal(sprintf(nil "pattern char %d must be '+' or '-', got '%s'"
                          i ch))
      )
    )
  )
  t
)

;; ===================== OPEN MASTER CELLVIEWS =====================

resCV      = dbOpenCellViewByType(ANALOG_LIB "res"   "symbol" "schematicSymbol" "r")
unless( resCV KWSBfatal("cannot open analogLib/res/symbol") )

ipinCV_B   = dbOpenCellViewByType("basic" "ipin"  "symbol" "schematicSymbol" "r")
opinCV_B   = dbOpenCellViewByType("basic" "opin"  "symbol" "schematicSymbol" "r")
iopinCV_B  = dbOpenCellViewByType("basic" "iopin" "symbol" "schematicSymbol" "r")
unless( ipinCV_B && opinCV_B && iopinCV_B
        KWSBfatal("cannot open basic pin masters (ipin/opin/iopin)") )

;; ===================== MAIN: buildBranch =====================

procedure( buildBranch(name pattern)
  let( (cellName cv tapPosCV tapNegCV resInst
        tapInst ch tapCell xPos i
        yXpin yVbiasP yVbiasN yBk yVddRail yGndRail
        xLeft xRight resMidXY)

    KWSBvalidatePattern(pattern)
    cellName = strcat("branch_" name)

    KWSBinfo(sprintf(nil ">>> buildBranch %s : %s <<<" cellName pattern))

    ;; Verify tap_pos / tap_neg exist before touching anything.
    tapPosCV = dbOpenCellViewByType(KWS_LIB "tap_pos" "symbol" "schematicSymbol" "r")
    tapNegCV = dbOpenCellViewByType(KWS_LIB "tap_neg" "symbol" "schematicSymbol" "r")
    unless( tapPosCV && tapNegCV
      KWSBfatal("tap_pos or tap_neg symbol missing — run tap_cells.il first")
    )

    KWSBdeleteView(KWS_LIB cellName "symbol")
    KWSBdeleteView(KWS_LIB cellName "schematic")

    cv = dbOpenCellViewByType(KWS_LIB cellName "schematic" "schematic" "w")
    unless( cv
      KWSBfatal(sprintf(nil "cannot open %s schematic for write" cellName))
    )

    ;; Layout Y coordinates.
    yXpin    =  10.0          ;; x0..x7 pin row (enter tap xi from above)
    yVbiasP  =  -8.0
    yVbiasN  = -10.0
    yBk      =  -4.0
    yVddRail =  12.0
    yGndRail = -12.0

    ;; Place 8 taps left-to-right, one per character of pattern.
    ;; pattern[0] → x0 (leftmost), pattern[7] → x7 (rightmost).
    ;; Use explicit case + parenthesized substring to avoid SKILL parser
    ;; ambiguity that previously produced reversed pattern mapping.
    for( i 0 7
      ch      = substring(pattern (i + 1) 1)
      tapCell = nil
      case( ch
        ("+" tapCell = tapPosCV)
        ("-" tapCell = tapNegCV)
        (t   KWSBfatal(sprintf(nil "pattern char %d invalid: '%s'" i ch)))
      )
      xPos    = i * KWS_TAP_DX
      tapInst = dbCreateInst(cv tapCell
                             sprintf(nil "T%d" i)
                             list(xPos 0.0) "R0")
      unless( tapInst
        KWSBfatal(sprintf(nil "dbCreateInst failed for T%d" i))
      )

      ;; Create pin x<i> at the top of the xi column.
      schCreatePin(cv ipinCV_B
                   sprintf(nil "x%d" i)
                   "input" nil
                   list(xPos yXpin) "R0")

      ;; xi from tap up to the x<i> pin.
      KWSBwire(cv KWSBtermXY(tapInst "xi") list(xPos yXpin))

      ;; Bias: positive tap ties to vbias_p rail; negative tap ties to vbias_n.
      case( ch
        ("+" KWSBwire(cv KWSBtermXY(tapInst "vbias_p") list(xPos yVbiasP)))
        ("-" KWSBwire(cv KWSBtermXY(tapInst "vbias_n") list(xPos yVbiasN)))
      )

      ;; Every tap's bk to shared bk rail; vdd/gnd to rails.
      KWSBwire(cv KWSBtermXY(tapInst "bk")  list(xPos yBk))
      KWSBwire(cv KWSBtermXY(tapInst "vdd") list(xPos yVddRail))
      KWSBwire(cv KWSBtermXY(tapInst "gnd") list(xPos yGndRail))
    )

    ;; Horizontal rails across all 8 columns.
    xLeft  = 0.0
    xRight = 7 * KWS_TAP_DX
    KWSBwire(cv list(xLeft yBk)      list(xRight yBk))
    KWSBwire(cv list(xLeft yVbiasP)  list(xRight yVbiasP))
    KWSBwire(cv list(xLeft yVbiasN)  list(xRight yVbiasN))
    KWSBwire(cv list(xLeft yVddRail) list(xRight yVddRail))
    KWSBwire(cv list(xLeft yGndRail) list(xRight yGndRail))

    ;; Load resistor bk → gnd on the far right.
    resMidXY = list(8 * KWS_TAP_DX  (yBk + yGndRail) / 2.0)
    resInst  = dbCreateInst(cv resCV "R_LOAD" resMidXY "R0")
    unless( resInst KWSBfatal("dbCreateInst failed for R_LOAD") )
    resInst~>r = R_LOAD_OHM

    ;; Terminal names on analogLib/res are PLUS and MINUS.
    KWSBwire(cv list(7 * KWS_TAP_DX yBk)       KWSBtermXY(resInst "PLUS"))
    KWSBwire(cv KWSBtermXY(resInst "MINUS")    list(8 * KWS_TAP_DX yGndRail))
    KWSBwire(cv list(7 * KWS_TAP_DX yGndRail)  list(8 * KWS_TAP_DX yGndRail))

    ;; Top-level branch pins.
    schCreatePin(cv ipinCV_B  "vbias_p" "input"       nil list(-3.0 yVbiasP)  "R0")
    KWSBwire(cv list(-3.0 yVbiasP) list(0.0 yVbiasP))

    schCreatePin(cv ipinCV_B  "vbias_n" "input"       nil list(-3.0 yVbiasN)  "R0")
    KWSBwire(cv list(-3.0 yVbiasN) list(0.0 yVbiasN))

    schCreatePin(cv opinCV_B  "bk"      "output"      nil list(9 * KWS_TAP_DX yBk)  "R0")
    KWSBwire(cv list(8 * KWS_TAP_DX yBk) list(9 * KWS_TAP_DX yBk))

    schCreatePin(cv iopinCV_B "vdd"     "inputOutput" nil list(-3.0 yVddRail) "R0")
    KWSBwire(cv list(-3.0 yVddRail) list(0.0 yVddRail))

    schCreatePin(cv iopinCV_B "gnd"     "inputOutput" nil list(-3.0 yGndRail) "R0")
    KWSBwire(cv list(-3.0 yGndRail) list(0.0 yGndRail))

    schCheck(cv)
    dbSave(cv)
    dbClose(cv)

    ;; Symbol generation: do this MANUALLY in the GUI after the schematic
    ;; is built. See the KWSgenSymbol comment in tap_cells.il for the
    ;; rationale and the 5-click recipe.
    KWSBinfo(sprintf(nil "manual step: create symbol for kws_project/%s" cellName))
    KWSBinfo("  open schematic -> Create -> Cellview -> From Cellview")
    KWSBinfo("  target view = symbol, target type = schematicSymbol, OK, Save.")

    printf("=== SUCCESS: %s built (pattern %s, x0..x7 left-to-right) ===\n"
           cellName pattern)
    t
  )
)

KWSBinfo("branch_gen.il loaded; call e.g. buildBranch(\"A\" \"+-+-+-+-\")")
