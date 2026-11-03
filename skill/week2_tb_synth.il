;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; week2_tb_synth.il
;;; Purpose : fully-scripted, net-label-based testbench for Week 2.
;;; Library : kws_project
;;; Dependencies : branch_A and branch_B symbols (and tap_pos/_neg).
;;;
;;; Strategy (all connectivity by NET LABEL, no physical routing):
;;;   - Each branch pin gets a short wire stub + matching text label.
;;;   - Each source's PLUS gets a short wire stub + matching text label.
;;;   - Labels with the same text become the same net regardless of where
;;;     they are in the schematic.
;;;   - Labels ending in '!' (vdd!, gnd!) are global nets.
;;;
;;; Layout is tight: branches stacked vertically, 11 sources in a row
;;; above, short (2-unit) wire stubs, no long routing.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ===================== CONFIGURATION =====================
KWS_LIB    = "kws_project"
ANALOG_LIB = "analogLib"
TB_CELL    = "week2_tb_synth"

;; Source DC values.
VDD_V      = "1.8"
VBIASP_V   = "1.3"
VBIASN_V   = "0.5"
XI_INIT    = "0"        ;; default for every VX source

;; Layout constants — compact.
STUB_LEN   = 2.0        ;; wire stub length before a label
SRC_PITCH  = 4.0        ;; horizontal pitch between sources in the row
SRC_ROW_Y  = 15.0       ;; y of source instance origins
BR_A_XY    = list(0.0   0.0)
BR_B_XY    = list(0.0 -15.0)   ;; stacked just below BR_A
OPIN_DX    = 3.0        ;; distance from branch bk pin to opin

;; ===================== UTILITIES =====================

procedure( KWSTinfo(msg)  printf("[week2_tb_synth] %s\n" msg) )
procedure( KWSTfatal(msg) error("[week2_tb_synth] FATAL: %s\n" msg) )

procedure( KWSTdeleteView(lib cell view)
  let( (o)
    o = ddGetObj(lib cell view)
    when( o
      KWSTinfo(sprintf(nil "deleting %s/%s/%s" lib cell view))
      ddDeleteObj(o)
    )
  )
)

procedure( KWSTtermXY(inst termName)
  let( (master mt pin xy)
    master = inst~>master
    mt = car(setof(x master~>terminals x~>name == termName))
    unless( mt
      KWSTfatal(sprintf(nil "term '%s' not on master %s/%s"
                        termName master~>libName master~>cellName))
    )
    pin = car(mt~>pins)
    unless( pin && pin~>fig && pin~>fig~>bBox
      KWSTfatal(sprintf(nil "no pin/fig/bBox for '%s' on %s"
                        termName master~>cellName))
    )
    xy = centerBox(pin~>fig~>bBox)
    list( xCoord(xy) + xCoord(inst~>xy)
          yCoord(xy) + yCoord(inst~>xy) )
  )
)

procedure( KWSTsingleTermXY(inst)
  let( (ft pin xy)
    ft = car(inst~>master~>terminals)
    unless( ft
      KWSTfatal(sprintf(nil "master %s has no terminals"
                        inst~>master~>cellName))
    )
    pin = car(ft~>pins)
    xy = centerBox(pin~>fig~>bBox)
    list( xCoord(xy) + xCoord(inst~>xy)
          yCoord(xy) + yCoord(inst~>xy) )
  )
)

;; Draw a wire; return the first wire object so we can attach a label.
procedure( KWSTwireObj(cv p1 p2)
  let( (wires)
    wires = schCreateWire(cv "route" "full" list(p1 p2) 0.0625 0.0 0.0)
    car(wires)
  )
)

procedure( KWSTopenMaster(lib cell)
  let( (cv)
    cv = dbOpenCellViewByType(lib cell "symbol" "schematicSymbol" "r")
    unless( cv
      KWSTfatal(sprintf(nil "missing %s/%s/symbol — build prerequisites first"
                        lib cell))
    )
    cv
  )
)

;; Compute a stub endpoint in the given direction.
;; direction ∈ {"left", "right", "up", "down"}
procedure( KWSTstubEnd(xy direction)
  case( direction
    ("left"  list( xCoord(xy) - STUB_LEN  yCoord(xy) ))
    ("right" list( xCoord(xy) + STUB_LEN  yCoord(xy) ))
    ("up"    list( xCoord(xy)             yCoord(xy) + STUB_LEN ))
    ("down"  list( xCoord(xy)             yCoord(xy) - STUB_LEN ))
    (t       KWSTfatal(sprintf(nil "unknown direction '%s'" direction)))
  )
)

;; Draw stub from xy in direction, attach a label with netName. The label
;; glues to the wire so that net takes the given name.
;; cdnshelp: schCreateWireLabel(cvId wireObj point text justify orient
;;                              fontStyle fontHeight aliasP)
procedure( KWSTlabelStub(cv xy direction netName)
  let( (endXY wire)
    endXY = KWSTstubEnd(xy direction)
    wire  = KWSTwireObj(cv xy endXY)
    unless( wire
      KWSTfatal(sprintf(nil "schCreateWire returned nil for stub at %A" xy))
    )
    schCreateWireLabel(cv wire endXY netName
                       "lowerLeft" "R0" "stick" 0.0625 nil)
  )
)

;; ===================== OPEN MASTER CELLVIEWS =====================

vdcCV     = KWSTopenMaster(ANALOG_LIB "vdc")
gndCV     = KWSTopenMaster(ANALOG_LIB "gnd")
opinCV    = KWSTopenMaster("basic"    "opin")
branchACV = KWSTopenMaster(KWS_LIB    "branch_A")
branchBCV = KWSTopenMaster(KWS_LIB    "branch_B")

;; ===================== HIGHER-LEVEL HELPERS =====================

;; Label every pin on a branch instance with matching-name stubs.
;; Assumes standard sides: vbias_n, vbias_p, x0..x7 on LEFT; bk on RIGHT;
;; vdd, gnd on TOP. (Matches the auto-symbol layout observed earlier.)
procedure( KWSTlabelBranchPins(cv brInst)
  let( (i)
    KWSTlabelStub(cv KWSTtermXY(brInst "vbias_n") "left" "vbias_n")
    KWSTlabelStub(cv KWSTtermXY(brInst "vbias_p") "left" "vbias_p")
    for( i 0 7
      KWSTlabelStub(cv
                    KWSTtermXY(brInst sprintf(nil "x%d" i))
                    "left"
                    sprintf(nil "x%d" i))
    )
    KWSTlabelStub(cv KWSTtermXY(brInst "vdd") "up"   "vdd!")
    KWSTlabelStub(cv KWSTtermXY(brInst "gnd") "up"   "gnd!")
    ;; bk is handled separately (opin).
  )
)

;; Place a vdc source at (x, SRC_ROW_Y). Stub UP from PLUS, label it netName.
;; Stub DOWN from MINUS, connect to a gnd symbol.
procedure( KWSTmakeSource(cv x instName dcValue netName)
  let( (xy inst plusXY minusXY gndInst)
    xy   = list( x  SRC_ROW_Y )
    inst = dbCreateInst(cv vdcCV instName xy "R0")
    unless( inst
      KWSTfatal(sprintf(nil "dbCreateInst failed for %s" instName))
    )
    inst~>vdc = dcValue
    plusXY   = KWSTtermXY(inst "PLUS")
    minusXY  = KWSTtermXY(inst "MINUS")
    KWSTlabelStub(cv plusXY "up" netName)
    gndInst = dbCreateInst(cv gndCV
                           strcat("G_" instName)
                           list( xCoord(minusXY) yCoord(minusXY) - 3.0 )
                           "R0")
    KWSTwireObj(cv minusXY KWSTsingleTermXY(gndInst))
    inst
  )
)

;; ===================== MAIN =====================

procedure( KWSTbuild()
  let( (cv brA brB i opinAxy opinBxy bkAxy bkBxy
        srcX)

    KWSTinfo(sprintf(nil ">>> building %s/%s <<<" KWS_LIB TB_CELL))
    KWSTdeleteView(KWS_LIB TB_CELL "schematic")

    cv = dbOpenCellViewByType(KWS_LIB TB_CELL "schematic" "schematic" "w")
    unless( cv KWSTfatal("cannot open TB cellview for write") )

    ;; --- place branches -----------------------------------------------
    brA = dbCreateInst(cv branchACV "BR_A" BR_A_XY "R0")
    brB = dbCreateInst(cv branchBCV "BR_B" BR_B_XY "R0")

    ;; --- label all branch pins with matching net names ---------------
    KWSTlabelBranchPins(cv brA)
    KWSTlabelBranchPins(cv brB)

    ;; --- bk outputs: proper opin pins -------------------------------
    bkAxy   = KWSTtermXY(brA "bk")
    bkBxy   = KWSTtermXY(brB "bk")
    opinAxy = list( xCoord(bkAxy) + OPIN_DX  yCoord(bkAxy) )
    opinBxy = list( xCoord(bkBxy) + OPIN_DX  yCoord(bkBxy) )
    schCreatePin(cv opinCV "bk_A" "output" nil opinAxy "R0")
    schCreatePin(cv opinCV "bk_B" "output" nil opinBxy "R0")
    KWSTwireObj(cv bkAxy opinAxy)
    KWSTwireObj(cv bkBxy opinBxy)

    ;; --- 8 xi sources in a row at y = SRC_ROW_Y ---------------------
    ;; Each VX_i is placed at x = (i - 4) * SRC_PITCH so the 8 sources
    ;; are centered around x = -2 (slightly left of the branches).
    for( i 0 7
      srcX = (i - 4) * SRC_PITCH
      KWSTmakeSource(cv srcX
                     sprintf(nil "VX%d" i)
                     XI_INIT
                     sprintf(nil "x%d" i))
    )

    ;; --- bias sources: VBP, VBN, VDD to the right of the VX row -----
    KWSTmakeSource(cv  4 * SRC_PITCH "VBP" VBIASP_V "vbias_p")
    KWSTmakeSource(cv  5 * SRC_PITCH "VBN" VBIASN_V "vbias_n")
    KWSTmakeSource(cv  6 * SRC_PITCH "VDD" VDD_V    "vdd!")

    schCheck(cv)
    dbSave(cv)
    dbClose(cv)

    printf("=== SUCCESS: %s built ===\n" TB_CELL)
    printf("\nLayout: BR_A and BR_B stacked at center; 8 VX + 3 bias sources\n")
    printf("in a row above. All connectivity via net labels (xN, vbias_n,\n")
    printf("vbias_p, vdd!, gnd!). bk_A and bk_B exposed as opin pins.\n")
    printf("\nNEXT: schematic editor, verify no red X on wires.\n")
    printf("Then ADE: re-create maestro view if needed, add outputs /bk_A\n")
    printf("and /bk_B, run sim. To test a bit: click VX0, 'q', DC = 1.8.\n")
    t
  )
)

KWSTbuild()
