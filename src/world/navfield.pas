unit navfield;

{** The nav field: the third derived map layer, for AI pathing.

  The art field says what to draw, the collision field says where a body may stand. This
  layer says how a body gets from one place to another. It is a flow field: a breadth
  first search outward from a target cell (the player) over the walkable cells in a
  bounded window, recording each cell's step distance back to the target. A pursuer reads
  the gradient, stepping to the neighbour whose distance is one less, and so is drawn to
  the target around walls and through doorways rather than pressing straight into a wall.

  Passability is taken from the collision field, not from tile walkability alone, so the
  graph agrees with where a body can actually move: an edge between two cells is open only
  when a body of the given radius clears the move on the voxel field. Cardinal moves
  between adjacent walkable cells are never sealed by the sub-cell posts (the collision
  field keeps them connected), so in practice the field reaches every cell a body can
  reach, which t_nav checks against the same body walk t_voxfield uses.

  The field flows from one target over a fixed window, so it is a pure function of the
  target cell and the surrounding world. Rebuild it when the target moves to a new cell
  or the world changes; between rebuilds every pursuer reads the one field. }

{$mode objfpc}{$H+}

interface

uses
  tileworld, voxfield;

const
  NAV_RADIUS    = 12;                    { window half width in cells around the target }
  NAV_SIDE      = NAV_RADIUS * 2 + 1;    { window edge in cells }
  NAV_UNREACHED = -1;                    { a cell the search never reached }

type
  TNavField = record
    Tx, Ty: LongInt;                     { the target cell the field flows to }
    Ox, Oy: LongInt;                     { window origin: the cell at local (0,0) }
    BodyR:  Single;                      { body radius the edges were tested with }
    Built:  Boolean;
    Dist:   array[0 .. NAV_SIDE * NAV_SIDE - 1] of LongInt;
  end;

{ Build the flow field over the window centred on (tcx, tcy), with distances in steps back
  to that cell. Edges are gated by the collision field for a body of radius bodyR. }
procedure NavFieldBuild(var nf: TNavField; var tw: TTileWorld;
  tcx, tcy: LongInt; bodyR: Single);

{ Steps from cell (cx, cy) back to the target, or NAV_UNREACHED when the cell is outside
  the window or the search never reached it. }
function NavFieldDist(const nf: TNavField; cx, cy: LongInt): LongInt;

{ The next cell a pursuer at (cx, cy) should step to: the cardinal neighbour with the
  smallest distance that is strictly nearer the target. False when the cell has no field
  information or no nearer neighbour (already at the target, or unreachable). }
function NavFieldNext(const nf: TNavField; cx, cy: LongInt;
  out ncx, ncy: LongInt): Boolean;

implementation

const
  DX: array[0..3] of LongInt = (1, -1, 0, 0);
  DY: array[0..3] of LongInt = (0, 0, 1, -1);

function Local(const nf: TNavField; cx, cy: LongInt; out li: LongInt): Boolean;
{ Map a world cell to its index in the window, or False when it falls outside. }
var
  lx, ly: LongInt;
begin
  Local := False;
  lx := cx - nf.Ox;
  ly := cy - nf.Oy;
  if (lx < 0) or (lx >= NAV_SIDE) or (ly < 0) or (ly >= NAV_SIDE) then exit;
  li := lx + ly * NAV_SIDE;
  Local := True;
end;

function BodyFree(var tw: TTileWorld; bodyR, wx, wy: Single): Boolean;
{ A body of radius bodyR centred at (wx, wy) stands clear on the collision field, the same
  four corner test movement uses. }
begin
  BodyFree :=
    (not VoxelSolid(tw, wx - bodyR, wy - bodyR)) and
    (not VoxelSolid(tw, wx + bodyR, wy - bodyR)) and
    (not VoxelSolid(tw, wx - bodyR, wy + bodyR)) and
    (not VoxelSolid(tw, wx + bodyR, wy + bodyR));
end;

function StepOpen(var tw: TTileWorld; bodyR: Single; ax, ay, bx, by: LongInt): Boolean;
{ A body may move from cell (ax, ay) to the adjacent cell (bx, by): the target cell centre
  is clear, and so is the midpoint of the shared edge, so it does not clip a post on the
  way across. }
begin
  StepOpen :=
    BodyFree(tw, bodyR, bx + 0.5, by + 0.5) and
    BodyFree(tw, bodyR, (ax + bx) / 2.0 + 0.5, (ay + by) / 2.0 + 0.5);
end;

procedure NavFieldBuild(var nf: TNavField; var tw: TTileWorld;
  tcx, tcy: LongInt; bodyR: Single);
var
  qx, qy: array[0 .. NAV_SIDE * NAV_SIDE - 1] of LongInt;
  head, tail, i, cx, cy, nx, ny, li, ni: LongInt;
begin
  nf.Tx := tcx;
  nf.Ty := tcy;
  nf.Ox := tcx - NAV_RADIUS;
  nf.Oy := tcy - NAV_RADIUS;
  nf.BodyR := bodyR;
  nf.Built := True;
  for i := 0 to NAV_SIDE * NAV_SIDE - 1 do nf.Dist[i] := NAV_UNREACHED;

  { The target seeds the search; it must itself be a place a body can stand. }
  if not Local(nf, tcx, tcy, li) then exit;
  if not TileWorldWalkable(tw, tcx, tcy) then exit;
  nf.Dist[li] := 0;
  head := 0; tail := 0;
  qx[tail] := tcx; qy[tail] := tcy; Inc(tail);

  while head < tail do begin
    cx := qx[head]; cy := qy[head]; Inc(head);
    Local(nf, cx, cy, li);
    for i := 0 to 3 do begin
      nx := cx + DX[i]; ny := cy + DY[i];
      if not Local(nf, nx, ny, ni) then continue;
      if nf.Dist[ni] <> NAV_UNREACHED then continue;
      if not TileWorldWalkable(tw, nx, ny) then continue;
      if not StepOpen(tw, bodyR, cx, cy, nx, ny) then continue;
      nf.Dist[ni] := nf.Dist[li] + 1;
      qx[tail] := nx; qy[tail] := ny; Inc(tail);
    end;
  end;
end;

function NavFieldDist(const nf: TNavField; cx, cy: LongInt): LongInt;
var
  li: LongInt;
begin
  if nf.Built and Local(nf, cx, cy, li) then NavFieldDist := nf.Dist[li]
  else NavFieldDist := NAV_UNREACHED;
end;

function NavFieldNext(const nf: TNavField; cx, cy: LongInt;
  out ncx, ncy: LongInt): Boolean;
var
  here, best, i, nx, ny, d: LongInt;
begin
  NavFieldNext := False;
  ncx := cx; ncy := cy;
  here := NavFieldDist(nf, cx, cy);
  if here <= 0 then exit;      { no information, or already on the target }
  best := here;
  for i := 0 to 3 do begin
    nx := cx + DX[i]; ny := cy + DY[i];
    d := NavFieldDist(nf, nx, ny);
    if (d <> NAV_UNREACHED) and (d < best) then begin
      best := d; ncx := nx; ncy := ny;
    end;
  end;
  NavFieldNext := best < here;
end;

end.
