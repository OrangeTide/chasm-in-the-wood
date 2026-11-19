unit voxfield;

{** The collision field: solidity at voxel resolution.

  Movement tests this field rather than whole-tile walkability, so a body stops against the
  sub-cell brushes the map places, not just against wall cells. A solid or non-walkable cell
  (rock, wall, a shut gate) blocks in full, as before. On top of that the field carries the
  free-standing brushes that intrude into open cells: the beam posts standing at wall
  corners. The field is derived from the same map the renderer draws, through the shared
  tileworld queries, so collision and the drawn geometry agree.

  A brush contributes a footprint: the set of voxel columns it fills, taken from its .vox
  model (a column counts as solid when any voxel in it is set). A world point is solid when
  its cell is non-walkable, or when it falls inside the footprint of a post at one of the
  cell's four corners. The footprint is read at voxel precision, so the body clears a post
  by the real width of its bars, not a whole cell. }

{$mode objfpc}{$H+}

interface

uses
  tileworld;

{ Load the blocking brush footprints (the beam post) from baseDir/<env>/<file>.vox. Safe to
  skip: without it, the field falls back to whole-cell solidity and nothing sub-cell blocks.
  Returns True when the post footprint loaded. }
function VoxFieldInit(const baseDir: String): Boolean;

{ True when a body point at world (wx, wz) is inside solid matter: a non-walkable cell, or a
  corner post that reaches this point. }
function VoxelSolid(var tw: TTileWorld; wx, wz: Single): Boolean;

implementation

uses
  sysutils, math, voxfile, brushdef;

const
  { Collision runs in tile units, where one cell is 1.0 and a body position is already in
    those units (see player.Px). A cell is VOXPERCELL voxels along an edge, so a voxel is
    VU tile units (see docs/asset-pipeline.md). }
  VOXPERCELL = 24;
  CELL = 1.0;
  VU = CELL / VOXPERCELL;

type
  TFoot = record
    W, D: LongInt;             { footprint extent in voxels: width (x) by depth (z) }
    Col: array of Boolean;     { W*D, a column is set when the brush fills it }
    Loaded: Boolean;
  end;

var
  gPost: TFoot;

procedure BuildFoot(const m: TVoxModel; out f: TFoot);
{ Flatten a .vox model to its horizontal footprint: a column (x, y) is solid when any voxel
  up its height (z, the format's up axis) is set. }
var
  x, y, z: LongInt;
  hit: Boolean;
begin
  f.W := m.Sx;
  f.D := m.Sy;
  f.Loaded := True;
  SetLength(f.Col, f.W * f.D);
  for y := 0 to f.D - 1 do
    for x := 0 to f.W - 1 do begin
      hit := False;
      for z := 0 to m.Sz - 1 do
        if VoxCell(m, x, y, z) <> 0 then begin hit := True; break; end;
      f.Col[x + y * f.W] := hit;
    end;
end;

function VoxFieldInit(const baseDir: String): Boolean;
var
  m: TVoxModel;
  path: String;
  i: LongInt;
begin
  gPost.Loaded := False;
  { The registry names which brush blocks and at which anchor; the corner post is the one
    that reaches into open cells. Load its footprint from the same .vox the renderer draws. }
  for i := 0 to High(DUNGEON_BRUSHES) do
    if DUNGEON_BRUSHES[i].Blocks and (DUNGEON_BRUSHES[i].Anchor = baCorner) then begin
      path := baseDir + '/dungeon/' + DUNGEON_BRUSHES[i].Name + '.vox';
      if FileExists(path) and VoxLoad(path, m) then BuildFoot(m, gPost);
    end;
  VoxFieldInit := gPost.Loaded;
end;

function FootCovers(const f: TFoot; cxw, cyw, wx, wz: Single): Boolean;
{ True when world (wx,wz) lands on a set column of a footprint centred on the world point
  (cxw,cyw). The footprint spans W by D voxels, so it reaches half its extent each way. }
var
  lx, ly: LongInt;
begin
  FootCovers := False;
  if not f.Loaded then exit;
  lx := Floor((wx - cxw) / VU + f.W / 2);
  ly := Floor((wz - cyw) / VU + f.D / 2);
  if (lx < 0) or (lx >= f.W) or (ly < 0) or (ly >= f.D) then exit;
  FootCovers := f.Col[lx + ly * f.W];
end;

function PostBlocks(var tw: TTileWorld; gx, gy: LongInt; wx, wz: Single): Boolean;
{ A post at grid corner (gx,gy) blocks (wx,wz) when the corner carries one and the point
  falls in its footprint. The footprint is capped to a small core radius: a post stands in
  the corner of a one-cell passage, and its full width would seal the gap for a body, so
  only its core collides. A body may clip the outer bars, which at a corner post is slight. }
const
  POST_REACH = 0.18;   { core collision radius, tile units; below the 0.2 that seals a gap }
var
  dx, dy: Single;
begin
  PostBlocks := False;
  if not TileWorldPostAt(tw, gx, gy) then exit;
  dx := wx - gx * CELL;
  dy := wz - gy * CELL;
  if dx * dx + dy * dy > POST_REACH * POST_REACH then exit;
  PostBlocks := FootCovers(gPost, gx * CELL, gy * CELL, wx, wz);
end;

function VoxelSolid(var tw: TTileWorld; wx, wz: Single): Boolean;
var
  tx, ty: LongInt;
begin
  VoxelSolid := True;
  tx := Floor(wx);
  ty := Floor(wz);
  if not TileWorldWalkable(tw, tx, ty) then exit;
  { A post stands at a cell corner, so each of the cell's four corners may reach in. }
  if PostBlocks(tw, tx,     ty,     wx, wz) then exit;
  if PostBlocks(tw, tx + 1, ty,     wx, wz) then exit;
  if PostBlocks(tw, tx,     ty + 1, wx, wz) then exit;
  if PostBlocks(tw, tx + 1, ty + 1, wx, wz) then exit;
  VoxelSolid := False;
end;

end.
