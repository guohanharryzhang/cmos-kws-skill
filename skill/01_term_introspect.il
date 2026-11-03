;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 01_term_introspect.il
;;; Place one pmos2v in a scratch schematic and print every plausible
;;; access path for terminal position. From this we learn which path
;;; actually works on this Cadence build.
;;;
;;; Usage in CIW:
;;;   load("01_term_introspect.il")
;;; Then screenshot the output and send back.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

procedure( KWSIheader(text) printf("\n--- %s ---\n" text) )

procedure( KWSIrun()
  let( (cv pmosCV inst masterTerms instTerm masterTerm)

    printf("\n=== terminal introspection on gpdk045/pmos2v ===\n")

    ;; Clean previous scratch.
    let( (o)
      o = ddGetObj("kws_project" "__kws_introspect__" "schematic")
      when( o ddDeleteObj(o) )
      o = ddGetObj("kws_project" "__kws_introspect__")
      when( o ddDeleteObj(o) )
    )

    ;; Open master and create scratch.
    pmosCV = dbOpenCellViewByType("gpdk045" "pmos2v" "symbol" "schematicSymbol" "r")
    unless( pmosCV error("cannot open gpdk045/pmos2v/symbol") )

    cv = dbOpenCellViewByType("kws_project" "__kws_introspect__"
                              "schematic" "schematic" "w")
    unless( cv error("cannot open scratch cellview") )

    inst = dbCreateInst(cv pmosCV "MTEST" list(0.0 0.0) "R0")
    unless( inst error("dbCreateInst failed") )

    KWSIheader("inst~>xy")
    printf("  %A\n" inst~>xy)

    KWSIheader("inst~>instTerms (list)")
    printf("  count: %d\n" length(inst~>instTerms))
    foreach( it inst~>instTerms
      printf("    name=%s\n" it~>name)
    )

    KWSIheader("inst~>master~>terminals (list)")
    masterTerms = inst~>master~>terminals
    printf("  count: %d\n" length(masterTerms))
    foreach( mt masterTerms
      printf("    name=%s direction=%A\n" mt~>name mt~>direction)
    )

    ;; For terminal G, exhaustively probe access paths.
    KWSIheader("paths to position of terminal G (gate)")
    instTerm   = car(setof(x inst~>instTerms     x~>name == "G"))
    masterTerm = car(setof(x inst~>master~>terminals x~>name == "G"))

    printf("  instTerm:                 %A\n" instTerm)
    printf("  instTerm~>name:           %A\n" instTerm~>name)
    printf("  instTerm~>net:            %A\n" instTerm~>net)
    printf("  instTerm~>pin:            %A\n" errset(instTerm~>pin))
    printf("  instTerm~>term:           %A\n" errset(instTerm~>term))

    printf("  masterTerm:               %A\n" masterTerm)
    printf("  masterTerm~>pins:         %A\n" errset(masterTerm~>pins))
    printf("  masterTerm~>pins length:  %A\n"
           errset(length(masterTerm~>pins)))

    when( masterTerm~>pins
      let( (firstPin)
        firstPin = car(masterTerm~>pins)
        printf("  pin:                      %A\n" firstPin)
        printf("  pin~>fig:                 %A\n" errset(firstPin~>fig))
        when( firstPin~>fig
          printf("  pin~>fig~>objType:        %A\n" errset(firstPin~>fig~>objType))
          printf("  pin~>fig~>bBox:           %A\n" errset(firstPin~>fig~>bBox))
          printf("  pin~>fig~>xy:             %A\n" errset(firstPin~>fig~>xy))
        )
      )
    )

    ;; Some Cadence builds expose a direct accessor.
    printf("\n  (alternate one-liners)\n")
    printf("  instTerm~>pin~>fig~>bBox: %A\n"
           errset(instTerm~>pin~>fig~>bBox))
    printf("  instTerm~>pinPosition:    %A\n"
           errset(instTerm~>pinPosition))

    ;; Cleanup scratch.
    dbClose(cv)
    let( (o)
      o = ddGetObj("kws_project" "__kws_introspect__" "schematic")
      when( o ddDeleteObj(o) )
      o = ddGetObj("kws_project" "__kws_introspect__")
      when( o ddDeleteObj(o) )
    )
    dbClose(pmosCV)

    printf("\n=== done ===\n")
    t
  )
)

KWSIrun()
