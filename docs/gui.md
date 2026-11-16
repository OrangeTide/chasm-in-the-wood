# Interface and HUD

The game draws a set of floating windows over the live diorama, in the System 7 and
SimCity idiom: the 3D world fills the screen and owns the background, and rectangular
panels float on top for status, and later inventory, character sheets, and menus. The
windowing layer and the game are two layers sharing one screen.

The toolkit is retained mode. Widgets are objects that persist between frames and
remember their state, as against an immediate-mode style that rebuilds the interface
every frame. A window dragged to a corner stays there; a scrollbar keeps its position.
This suits a game interface, where panels are opened, moved, and closed, over a debug
overlay style.

## Layers

The toolkit splits into a backend-agnostic core and two seams it draws through, so the
same widgets work over any renderer.

```
src/gui/gui       the core: widgets, windows, the desktop, events, drag and drop
src/gui/guitheme  the System 7 theme: all window and widget chrome
src/gui/guigl     the OpenGL canvas: the concrete drawing surface
src/game/gameui   the game's wrapper: the desktop, the status window, event glue
```

`gui` knows nothing about OpenGL or SDL. It draws through an abstract `TCanvas`, a
handful of primitives (filled and framed rectangles, lines, text, and a clip
rectangle), and an abstract `TTheme` that draws all the chrome. A widget asks the
canvas to fill a rectangle; it never touches the GPU.

`guitheme` is the System 7 look: white windows with a striped title bar, a close box
and a zoom box, a drop shadow, engraved slots, and framed buttons. It draws only
through `TCanvas`, so it is backend-neutral and could run over any canvas.

`guigl` is the one piece that talks to OpenGL. Every primitive the canvas offers,
text included, is a solid-coloured rectangle, so the canvas needs to draw only one
thing: coloured screen-space rectangles. It collects them into a vertex batch and
draws them in a single orthographic pass with alpha blending, clipping with the
scissor box. Text is a 5x7 bitmap font, each lit pixel a small rectangle in the same
batch, so no font texture is needed.

## Drawing over the 3D scene

The overlay draws after the world and the player, before the buffer is swapped. The
canvas sets its own GL state for the pass, blending on, depth test and face culling
off, and restores the 3D state when it is done, so the next frame's world draw is
unaffected. The whole interface is one program, one vertex buffer, and a handful of
draw calls, one per clip region.

## The game wrapper

`gameui` keeps the toolkit out of the main program. It owns the desktop, the theme,
the canvas, and the status window, and exposes a small procedural API: initialise for
a framebuffer size, set the status lines, feed a mouse event, and render. The main
program drives the interface with integers and strings and never sees the toolkit's
own types, which keeps its window and rectangle types from clashing with the standard
library's.

The one window today is a live status panel: depth, zone theme, seed, player tile,
and the resident region and chunk counts, refreshed every frame from the game state.
It is draggable and closable, and it is where the later inventory, character, and
menu panels will live.

## Input

SDL3 reports mouse motion, button, and wheel events with floating-point window
coordinates. The main loop translates each into a toolkit event and hands it to the
desktop, which routes it: a press brings the owning window to front, a drag on the
title bar moves the window, the close box hides it. Keyboard input still drives the
player directly; the interface takes the mouse.
