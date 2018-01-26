(module Visualizer racket
  (provide (all-defined-out))
  
  (require "parseState.rkt")
  (require racket/gui/base)
  (require plot)  

  (define CHUNK_SIZE 32)

  (define INVALID_CHUNK (Chunk -1 -1 0 0 0 0 0 0 0 0 0 0 0 0 0))

  (define windowX 500)
  (define windowY 0)
  (define windowWidth 1024)
  (define windowHeight 1024)

  (define activeHighlight null)
  (define activeLayer "movement")

  (define (normalize v low high)
    (/ (- v low)
       (- high low)))

  (define (roundTo x digits)
    (* (floor (/ x digits))
       digits))    

  (define (runIt)
  (define frameWithEvents% (class frame%
                             (define/override (on-subwindow-char r event)
                               (when (eq? (send event get-key-code) #\c)
                                 (exit))
                               (super on-subwindow-char r event))
                             (super-new)))

  (define (newFrame width height x y [label ""])
    (new frameWithEvents%
         [label label]
         [width width]
         [height height]
         [x x]
         [y y]))
  
  (define templates (list '(250 750 0 0 "controls")
                          (list windowWidth windowHeight windowX windowY "map")))
  (define frames (map (lambda (frame)
                        (match-let (((list width height x y name) frame))
                          (newFrame width height x y name)))
                      templates))

  (define mainFrame (first frames))
  (define mapFrame (second frames))

  (define activeChunkSet null)
  (define activeChunkSetLookup null)
  (define activeChunkMinMaxSet null)

  (define panel (new panel%
                     [parent mainFrame]
                     (alignment '(left top))))

  (define statusBox (new message%
                         [parent panel]
                         [label (~v "")]
                         [vert-margin 16]))
  (define siteBox (new message%
                       [parent panel]
                       [label ""]
                       [vert-margin 30]))
  
  (new button%
       [parent mainFrame]
       [label "Quit"]
       (callback (lambda (button event)
                   (exit))))

  (define tileWidth 0)
  (define tileHeight 0)

  (define minX 0)
  (define maxX 0)
  (define minY 0)
  (define maxY 0)
  
  (define canvasWithEvents% (class canvas%
                              (define/override (on-event event)
                                (match (send event get-event-type)
                                  ((== 'motion) (displayChunk (send event get-x) (send event get-y)))
                                  ((== 'left-down) (displayHighlight (send event get-x) (send event get-y)))
                                  ((== 'right-down) (begin (set! activeHighlight null)
                                                           (refresh (send this get-dc))))
                                  (_ (super on-event event))))
                              (super-new)))

  (define (refresh dc)
    (when (not (null? dc))
      (drawFrame dc)))

  (define drawFrame (lambda (context)
                      null))
  
  (define canvass (map (lambda (frame)
                         (let ((c (new canvasWithEvents%
                                       [parent frame]
                                       [paint-callback (lambda (canvas dc)
                                                         (drawFrame dc))])))
                           (send c set-canvas-background (make-object color% 111 111 111))
                           c))
                       (cdr frames)))
  (define dcs (map (lambda (canvas)
                     (send canvas get-dc))
                   canvass))

  (define (showVisual dc aiState)
    (match-let* (((AiState chunks chunkLookups chunkMinMaxes) aiState)
                 ((ChunkRange (MinMax miX maX)
                              (MinMax miY maY)
                              (MinMax minMovement maxMovement)
                              (MinMax minBase maxBase)
                              (MinMax minPlayer maxPlayer)
                              (MinMax minResource maxResource)
                              (MinMax minPassable maxPassable)
                              (MinMax minTick maxTick)
                              (MinMax minRating maxRating)
                              nests
                              worms
                              rally
                              retreat
                              resourceGen
                              playerGen) chunkMinMaxes))      
      
      (set! activeChunkSet chunks)
      (set! activeChunkMinMaxSet chunkMinMaxes)
      (set! activeChunkSetLookup chunkLookups)

      (when (Chunk? activeHighlight)
        (set! activeHighlight (findChunk (Chunk-x activeHighlight)
                                         (Chunk-y activeHighlight))))

      (set! minX miX)
      (set! maxX maX)
      (set! minY miY)
      (set! maxY maY)

      (set! tileWidth (ceiling (/ windowWidth (abs (/ (- maxX minX) CHUNK_SIZE)))))
      (set! tileHeight (ceiling (/ windowHeight (+ (abs (/ (- maxY minY) CHUNK_SIZE)) 1))))
      
      (refresh dc)

      (thread (lambda ()
                (sync (filesystem-change-evt "/data/games/factorio/script-output/rampantState.txt"))
                (showVisual dc (readState "/data/games/factorio/script-output/rampantState.txt"))))))

  (define dcMap (first dcs))

  (showVisual dcMap (readState "/data/games/factorio/script-output/rampantState.txt"))
  
  (define (chunkX->screenX x)
    (roundTo (* (normalize x minX maxX)
                windowWidth)
             tileWidth))

  (define (chunkY->screenY y)
    (roundTo (* (normalize y minY maxY)
                windowHeight)
             tileHeight))

  (define (screenX->chunkX x)
    (+ (* (ceiling (/ x tileWidth))
          CHUNK_SIZE)
       minX))
  
  (define (screenY->chunkY y)
    (- (- maxY
          (* (- (floor (/ y tileHeight)) 2)
             CHUNK_SIZE))))

  (set! drawFrame (lambda (context)
    (send context suspend-flush)
    (let ((chunkField (eval (string->symbol (string-append "Chunk-" activeLayer))))
          (chunkRangeField (eval (string->symbol (string-append "ChunkRange-" activeLayer)))))
      (map (lambda (chunk)
             (let ((x (chunkX->screenX (Chunk-x chunk)))
                   (y (chunkY->screenY (Chunk-y chunk))))
               (if (eq? activeHighlight chunk)
                   (send context set-pen (make-object color% 255 255 255) 1 'solid)
                   (send context set-pen (make-object color% 0 0 0) 1 'solid))
               (define (dcDraw dc property minMax)
                 (scaleColor dc property (MinMax-min minMax) (MinMax-max minMax))
                 (send dc draw-rectangle x y tileWidth tileHeight))
               (dcDraw context
                       (chunkField chunk)
                       (chunkRangeField activeChunkMinMaxSet))))
           activeChunkSet))
    (send context resume-flush)))

  (define (findChunk x y)
    (hash-ref activeChunkSetLookup (list x y) INVALID_CHUNK))
  
  (define (displayChunk x y)
    (send siteBox set-label
          (chunk->string (if (Chunk? activeHighlight)
                             activeHighlight
                             (findChunk (screenX->chunkX x)
                                        (screenY->chunkY y))))))

  (define (displayHighlight x y)
    (let ((chunk (findChunk (screenX->chunkX x)
                            (screenY->chunkY y))))
      (set! activeHighlight chunk))
    (refresh dcMap))

  (define (scaleColor dc value low high)
    (define v (if (= (- high low) 0)
                  0
                  (/ (- value low)
                     (- high low))))
    (define r (if (= v 0)
                  0
                  (if (> 0.75 v)
                      150
                      (if (> 0.50 v)
                          100
                          50))))
    (define g (inexact->exact (round (* v 255))))
    (send dc set-brush (make-object color% r g 0) 'solid))

  
  (new radio-box%
       [label "Show Layer"]
       [choices (list "movement" "base" "player" "resource" "passable" "tick" "rating" "nests" "worms" "rally" "retreat" "resourceGen" "playerGen")]
       [selection 0]
       [parent mainFrame]
       (callback (lambda (radioButton event)
                   (set! activeLayer (send radioButton get-item-label (send radioButton get-selection)))
                   (refresh dcMap))))

  (map (lambda (f)
         (send f show #t))
       frames)))