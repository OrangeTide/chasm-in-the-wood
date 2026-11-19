unit tilesock;

{** The socket layer: every modular piece's placement rule, defined once.

  A socket is a local neighbour pattern that decides something about a cell: that
  a wall belongs on this edge, that a post belongs at this corner, that this rock
  should read as a built wall, that this floor is a doorway. The same patterns are
  asked at three times in a tile's life:

    - generation, which classifies raw carved tiles (rock next to floor becomes a
      wall ring, a floor crossing becomes a door);
    - rendering, which places a brush where a socket matches;
    - collision, which blocks the footprint a socket says is there.

  If each stage defined the patterns for itself they would drift. Instead the
  patterns live here once, phrased over a generic cell probe so they do not care
  what backs the tiles. Generation runs them over a flat buffer; rendering and
  collision run them over the streaming world. One definition, three readers, no
  drift.

  Generation is then data driven: a rule is a socket plus the tile it sets, and a
  pass is a list of rules applied in order. Adding a boundary piece is a rule in
  the table, not a new procedure. }

{$mode objfpc}{$H+}

interface

uses
  tilemap;

type
  { A read only probe of tile codes at integer cells. A cell outside the backing
    reads as TILE_ROCK, so the solid surround is the natural boundary. The context
    pointer carries whatever backs the tiles: a flat buffer during generation, the
    streaming world at render time. }
  TCellProbe = function(ctx: Pointer; x, y: LongInt): Byte;

  { A socket's match test, phrased over a probe so it reads any backing. }
  TSockMatch = function(probe: TCellProbe; ctx: Pointer; x, y: LongInt): Boolean;

  { A generation rule: where Match holds, set the cell to Becomes. Margin skips
    that many cells at each border, for a socket that needs its full neighbourhood
    in range (a doorway reads the cells flanking it). Rules in a pass run in order
    and read the live buffer, so a later rule sees the tiles an earlier one placed:
    the door rule relies on the wall rule having laid its walls. }
  TGenRule = record
    Match:   TSockMatch;
    Becomes: Byte;
    Margin:  LongInt;
  end;

{ A cell counts as solid when it reads as stone: unexcavated rock or a built wall.
  This is the boundary that walls stand on and collision meets. }
function SockSolid(probe: TCellProbe; ctx: Pointer; x, y: LongInt): Boolean;

{ The wall ring socket (generation): a rock cell that touches floor, in any of the
  eight directions, should read as a built wall. }
function SockWallRing(probe: TCellProbe; ctx: Pointer; x, y: LongInt): Boolean;

{ The doorway socket (generation): a floor cell that is a one tile crossing through
  a wall, where at least one side along the passage opens out of its flanking into a
  room or a wider space. A long corridor flanked by walls is left plain. }
function SockDoorCrossing(probe: TCellProbe; ctx: Pointer; x, y: LongInt): Boolean;

{ The wall edge socket (rendering): an open cell's edge in direction (dx,dy) that
  faces a solid neighbour, where a wall panel stands. }
function SockWallEdge(probe: TCellProbe; ctx: Pointer; x, y, dx, dy: LongInt): Boolean;

{ The post corner socket (rendering and collision): the grid corner (gx,gy) touches
  four cells, and a post belongs where wall panels turn, not along a straight run and
  not buried in solid. }
function SockPostCorner(probe: TCellProbe; ctx: Pointer; gx, gy: LongInt): Boolean;

{ Run a list of generation rules over a flat w*h tile buffer in place. This is the
  whole generation dressing pass: a generic driver over a socket rule table. }
procedure GenApplySockets(var cells: array of Byte; w, h: LongInt;
  const rules: array of TGenRule);

implementation

function SockSolid(probe: TCellProbe; ctx: Pointer; x, y: LongInt): Boolean;
var
  t: Byte;
begin
  t := probe(ctx, x, y);
  SockSolid := (t = TILE_ROCK) or (t = TILE_WALL);
end;

function SockWallRing(probe: TCellProbe; ctx: Pointer; x, y: LongInt): Boolean;
var
  dx, dy: LongInt;
begin
  SockWallRing := False;
  if probe(ctx, x, y) <> TILE_ROCK then exit;
  for dy := -1 to 1 do
    for dx := -1 to 1 do
      if probe(ctx, x + dx, y + dy) = TILE_FLOOR then begin
        SockWallRing := True;
        exit;
      end;
end;

function SockDoorCrossing(probe: TCellProbe; ctx: Pointer; x, y: LongInt): Boolean;

  function IsWall(ax, ay: LongInt): Boolean;
  begin
    IsWall := probe(ctx, ax, ay) = TILE_WALL;
  end;

begin
  SockDoorCrossing := False;
  if probe(ctx, x, y) <> TILE_FLOOR then exit;
  { Walls on two opposite sides, with at least one flank along the passage open. }
  if IsWall(x - 1, y) and IsWall(x + 1, y) and
     (not (IsWall(x - 1, y - 1) and IsWall(x + 1, y - 1)) or
      not (IsWall(x - 1, y + 1) and IsWall(x + 1, y + 1))) then
    SockDoorCrossing := True
  else if IsWall(x, y - 1) and IsWall(x, y + 1) and
     (not (IsWall(x - 1, y - 1) and IsWall(x - 1, y + 1)) or
      not (IsWall(x + 1, y - 1) and IsWall(x + 1, y + 1))) then
    SockDoorCrossing := True;
end;

function SockWallEdge(probe: TCellProbe; ctx: Pointer; x, y, dx, dy: LongInt): Boolean;
begin
  SockWallEdge := (not SockSolid(probe, ctx, x, y)) and
                  SockSolid(probe, ctx, x + dx, y + dy);
end;

function SockPostCorner(probe: TCellProbe; ctx: Pointer; gx, gy: LongInt): Boolean;
var
  a, b, c, d: Boolean;
begin
  a := SockSolid(probe, ctx, gx - 1, gy - 1);   { NW }
  b := SockSolid(probe, ctx, gx,     gy - 1);   { NE }
  c := SockSolid(probe, ctx, gx - 1, gy);       { SW }
  d := SockSolid(probe, ctx, gx,     gy);       { SE }
  if (a = b) and (b = c) and (c = d) then begin SockPostCorner := False; exit; end;
  { Two solid on one side and two open on the other is a straight wall run, not a
    turn, so no post stands there. }
  if (a and b and (not c) and (not d)) or (c and d and (not a) and (not b)) or
     (a and c and (not b) and (not d)) or (b and d and (not a) and (not c)) then begin
    SockPostCorner := False; exit;
  end;
  SockPostCorner := True;
end;

{ ---- the flat buffer backing, for generation ---- }

type
  TBufferSrc = record
    Cells: PByte;
    W, H: LongInt;
  end;

function BufferProbe(ctx: Pointer; x, y: LongInt): Byte;
var
  src: ^TBufferSrc;
begin
  src := ctx;
  if (x >= 0) and (y >= 0) and (x < src^.W) and (y < src^.H) then
    BufferProbe := src^.Cells[x + y * src^.W]
  else
    BufferProbe := TILE_ROCK;
end;

procedure GenApplySockets(var cells: array of Byte; w, h: LongInt;
  const rules: array of TGenRule);
var
  src: TBufferSrc;
  i, x, y, m: LongInt;
begin
  if (w <= 0) or (h <= 0) then exit;
  src.Cells := @cells[0];
  src.W := w;
  src.H := h;
  for i := 0 to High(rules) do begin
    m := rules[i].Margin;
    for y := m to h - 1 - m do
      for x := m to w - 1 - m do
        if rules[i].Match(@BufferProbe, @src, x, y) then
          cells[x + y * w] := rules[i].Becomes;
  end;
end;

end.
