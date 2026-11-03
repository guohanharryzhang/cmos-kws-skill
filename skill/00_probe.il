;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 00_probe.il — environment sanity check (load this FIRST)
;;;
;;; Before running the main generators, this probe verifies that every
;;; external dependency they assume is actually present and that we can
;;; create/delete a cellview in the target library. Each check returns
;;; PASS/FAIL and its result is folded into an overall verdict so a
;;; single silent failure cannot slip past the final status line.
;;;
;;; Usage in Cadence CIW (NOT a bash shell):
;;;   load("00_probe.il")
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ===================== utilities =====================

;; Run a no-arg function (passed as a value) wrapped in errset; print PASS/FAIL.
;; Classic SKILL doesn't allow `var()` syntax to invoke a function held in
;; a variable — must use funcall(varName) or apply(varName nil).
procedure( KWSPcheck(description fn)
  let( (result ok)
    result = errset( funcall(fn) t )
    ok = result && car(result)
    printf("  %s %s\n" (if ok "[PASS]" "[FAIL]") description)
    ok
  )
)

;; Return t if the named cellview opens for read. Uses the same 5-arg form
;; the generators use (schematicSymbol for symbols, schematic for schematics)
;; so a probe PASS actually matches what the generators will try to open.
procedure( KWSPcheckView(lib cell view)
  let( (cv viewType)
    viewType = cond(
      ((equal view "symbol")    "schematicSymbol")
      ((equal view "schematic") "schematic")
      (t                         view)
    )
    cv = dbOpenCellViewByType(lib cell view viewType "r")
    when( cv dbClose(cv) )
    cv && t
  )
)

;; Return the list of terminal names on a symbol cellview. Reads directly
;; from the master's ~>terminals attribute — no scratch cell or placed
;; instance needed. (Earlier version used inst~>instTerms on a freshly
;; placed instance; that returned an empty list before the cellview was
;; saved, causing false "no discoverable terminals" failures.)
procedure( KWSPtermNames(lib cell)
  let( (cv names)
    cv = dbOpenCellViewByType(lib cell "symbol" "schematicSymbol" "r")
    unless( cv return(nil) )
    ;; NOTE: parameter named `trm`, not `t` — `t` is SKILL's reserved
    ;; boolean true and cannot be used as a variable name.
    names = mapcar(lambda((trm) trm~>name) cv~>terminals)
    dbClose(cv)
    names
  )
)

;; ===================== main =====================

procedure( KWSPrun()
  let( (allPass)
    allPass = t
    printf("\n=== KWS Week 2 environment probe ===\n")

    ;; ---- 1. kws_project library --------------------------------------
    printf("\n-- library access --\n")
    unless( KWSPcheck("kws_project library visible"
                      lambda( () ddGetObj("kws_project") && t ))
      allPass = nil
      printf("         fix: check cds.lib has a DEFINE for kws_project.\n")
    )

    ;; ---- 2. Week 1 cells (only used by stretch-goal integrated TB) ---
    printf("\n-- Week 1 dependencies (informational — not required for core) --\n")
    foreach( cell list("comparator" "dff" "shift_reg_8" "week1_tb")
      KWSPcheck(sprintf(nil "kws_project/%s/schematic" cell)
                lambda( () KWSPcheckView("kws_project" cell "schematic") ))
      ;; Informational only; do not touch allPass.
    )

    ;; ---- 3. gpdk045 transistors (REQUIRED) ---------------------------
    printf("\n-- PDK devices (required) --\n")
    foreach( cell list("pmos2v" "nmos2v")
      unless( KWSPcheck(sprintf(nil "gpdk045/%s/symbol" cell)
                        lambda( () KWSPcheckView("gpdk045" cell "symbol") ))
        allPass = nil
        printf("         fix: ensure gpdk045 is in cds.lib.\n")
      )
    )

    ;; ---- 4. analogLib primitives (REQUIRED) --------------------------
    printf("\n-- analogLib primitives (required) --\n")
    foreach( cell list("vdc" "vpulse" "res" "gnd" "vdd")
      unless( KWSPcheck(sprintf(nil "analogLib/%s/symbol" cell)
                        lambda( () KWSPcheckView("analogLib" cell "symbol") ))
        allPass = nil
      )
    )

    ;; ---- 5. basic library pin masters (REQUIRED) ---------------------
    ;; tap_cells.il and branch_gen.il open basic/{ipin,opin,iopin} at
    ;; load time. If these are missing, every pin call fails.
    printf("\n-- basic-library pin masters (required) --\n")
    foreach( cell list("ipin" "opin" "iopin")
      unless( KWSPcheck(sprintf(nil "basic/%s/symbol" cell)
                        lambda( () KWSPcheckView("basic" cell "symbol") ))
        allPass = nil
        printf("         fix: ensure 'basic' library is in cds.lib.\n")
      )
    )

    ;; ---- 6. core SKILL functions (REQUIRED) --------------------------
    ;; NOTE: classic SKILL stores functions in a separate function slot, so
    ;; boundp (which only checks the value slot) returns nil for built-in
    ;; procedures. Use getd(symbol), which returns the function definition
    ;; object (or nil if undefined). isCallable would also work but isn't
    ;; available in older SKILL versions.
    printf("\n-- SKILL functions (required) --\n")
    foreach( fnSym '(dbOpenCellViewByType dbCreateInst
                     schCreateWire schCreatePin schCheck
                     dbCreateLabel schViewToView ddGetObj
                     ddDeleteObj centerBox dbSave dbClose)
      unless( KWSPcheck(sprintf(nil "function %A defined" fnSym)
                        lambda( () getd(fnSym) && t ))
        allPass = nil
      )
    )

    ;; ---- 7. write permission on kws_project (REQUIRED) ---------------
    ;; MUST run before terminal-name discovery (section 8) because that
    ;; section creates a scratch cellview. If write is blocked, every
    ;; later "no discoverable terminals" line would be a false symptom
    ;; of the same root cause.
    printf("\n-- write permission check (required) --\n")
    let( (writePass)
      writePass = KWSPcheck(
        "can create+delete a scratch cellview in kws_project"
        lambda( ()
          let( (cv obj)
            cv = dbOpenCellViewByType("kws_project" "__kws_probe__"
                                      "schematic" "schematic" "w")
            when( cv
              dbSave(cv)
              dbClose(cv)
              obj = ddGetObj("kws_project" "__kws_probe__" "schematic")
              when( obj ddDeleteObj(obj) )
              obj = ddGetObj("kws_project" "__kws_probe__")
              when( obj ddDeleteObj(obj) )
              t
            )
          )
        ))
      unless( writePass
        allPass = nil
        printf("         fix: check directory permissions on kws_project.\n")
      )

      ;; ---- 8. terminal-name discovery on global symbols --------------
      ;; Prints the actual term names so the testbench's KWSTsingleTermXY
      ;; (which discovers names at runtime) is sanity-verifiable. Needs
      ;; write access because it instantiates symbols into a scratch cell
      ;; to read placed-terminal bBoxes.
      printf("\n-- global-symbol terminal names --\n")
      if( writePass
        then
          foreach( probePair
                   '(("analogLib" "gnd") ("analogLib" "vdd") ("analogLib" "vdc"))
            let( (lib cell names)
              lib   = car(probePair)
              cell  = cadr(probePair)
              names = KWSPtermNames(lib cell)
              if( names
                printf("  [INFO] %s/%s terminals: %A\n" lib cell names)
                progn(
                  printf("  [FAIL] %s/%s has no discoverable terminals\n" lib cell)
                  allPass = nil
                )
              )
            )
          )
        else
          printf("  [SKIP] write permission failed; term-name discovery unavailable.\n")
          printf("         The above write-permission failure is the real root cause.\n")
      )
    )

    printf("\n=== probe %s ===\n"
           (if allPass "PASS" "FAIL — fix issues above before running main scripts"))
    allPass
  )
)

KWSPrun()
