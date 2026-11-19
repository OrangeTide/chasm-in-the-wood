program t_voxfield;

{** Tests the collision field: whole-cell solidity plus the sub-cell corner posts. GL-free;
  loads the post footprint from content/tiles and queries a generated dungeon. }

{$mode objfpc}{$H+}

uses
  tileworld, brushfield, voxfield;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function BodyFree(var tw: TTileWorld; x, y: Single): Boolean;
const
  R = 0.3;   { BODY_RADIUS, from turns.pas }
begin
  BodyFree := (not VoxelSolid(tw, x - R, y - R)) and (not VoxelSolid(tw, x + R, y - R)) and
              (not VoxelSolid(tw, x - R, y + R)) and (not VoxelSolid(tw, x + R, y + R));
end;

const
  LO = -8;
  HI = REGION + 8;
  SPAN = HI - LO;
var
  tw: TTileWorld;
  bf: TBrushField;
  tx, ty, gx, gy, openX, openY, solidX, solidY: LongInt;
  haveOpen, haveSolid, havePost: Boolean;
  sx, sy, nTile, nBody, head, tail, cx, cy, nx, ny, d: LongInt;
  seenTile, seenBody: array of Boolean;
  qx, qy: array of LongInt;
  dirx: array[0..3] of LongInt = (1, -1, 0, 0);
  diry: array[0..3] of LongInt = (0, 0, 1, -1);

  function Idx(x, y: LongInt): LongInt;
  begin Idx := (x - LO) + (y - LO) * SPAN; end;

begin
  fails := 0;

  Check(VoxFieldInit('content/tiles'), 'post footprint loads from content/tiles');
  BrushFieldInit(bf);
  VoxFieldBind(@bf);   { collision reads the art field, as in the game }

  TileWorldInit(tw, 7, 1);

  { A plain open floor cell whose centre sits clear of every corner, and a solid cell. }
  haveOpen := False; haveSolid := False;
  openX := 0; openY := 0; solidX := 0; solidY := 0;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do begin
      if (not haveOpen) and TileWorldWalkable(tw, tx, ty) and
         (not TileWorldPostAt(tw, tx, ty)) and (not TileWorldPostAt(tw, tx + 1, ty)) and
         (not TileWorldPostAt(tw, tx, ty + 1)) and (not TileWorldPostAt(tw, tx + 1, ty + 1)) then begin
        openX := tx; openY := ty; haveOpen := True;
      end;
      if (not haveSolid) and TileWorldSolid(tw, tx, ty) then begin
        solidX := tx; solidY := ty; haveSolid := True;
      end;
    end;

  Check(haveOpen, 'found an open cell clear of posts');
  if haveOpen then
    Check(not VoxelSolid(tw, openX + 0.5, openY + 0.5), 'open floor centre is free');

  Check(haveSolid, 'found a solid cell');
  if haveSolid then
    Check(VoxelSolid(tw, solidX + 0.5, solidY + 0.5), 'solid cell centre blocks');

  { A post corner whose south-east cell is open: the point just inside that cell by the
    corner must block (the post), while the cell centre stays free (sub-cell collision). }
  havePost := False; gx := 0; gy := 0;
  for ty := 1 to REGION - 1 do
    for tx := 1 to REGION - 1 do
      if (not havePost) and TileWorldPostAt(tw, tx, ty) and TileWorldWalkable(tw, tx, ty) then begin
        gx := tx; gy := ty; havePost := True;
      end;

  Check(havePost, 'found a post corner on an open cell');
  if havePost then begin
    Check(VoxelSolid(tw, gx + 0.03, gy + 0.03), 'point by the post corner blocks');
    Check(not VoxelSolid(tw, gx + 0.5, gy + 0.5), 'same cell centre stays free');
  end;

  { Connectivity: a body on the voxel field must still reach where tile-walking reaches, or
    the corner posts have sealed passages. Flood-fill from spawn both ways and compare. }
  TileWorldSpawn(tw, sx, sy);
  SetLength(seenTile, SPAN * SPAN);
  SetLength(seenBody, SPAN * SPAN);
  SetLength(qx, SPAN * SPAN);
  SetLength(qy, SPAN * SPAN);

  { tile reachability }
  head := 0; tail := 0; nTile := 0;
  seenTile[Idx(sx, sy)] := True; qx[tail] := sx; qy[tail] := sy; Inc(tail);
  while head < tail do begin
    cx := qx[head]; cy := qy[head]; Inc(head); Inc(nTile);
    for d := 0 to 3 do begin
      nx := cx + dirx[d]; ny := cy + diry[d];
      if (nx >= LO) and (nx < HI) and (ny >= LO) and (ny < HI) and
         (not seenTile[Idx(nx, ny)]) and TileWorldWalkable(tw, nx, ny) then begin
        seenTile[Idx(nx, ny)] := True; qx[tail] := nx; qy[tail] := ny; Inc(tail);
      end;
    end;
  end;

  { body reachability: a step is allowed when the body clears the shared edge midpoint }
  head := 0; tail := 0; nBody := 0;
  seenBody[Idx(sx, sy)] := True; qx[tail] := sx; qy[tail] := sy; Inc(tail);
  while head < tail do begin
    cx := qx[head]; cy := qy[head]; Inc(head); Inc(nBody);
    for d := 0 to 3 do begin
      nx := cx + dirx[d]; ny := cy + diry[d];
      if (nx >= LO) and (nx < HI) and (ny >= LO) and (ny < HI) and
         (not seenBody[Idx(nx, ny)]) and TileWorldWalkable(tw, nx, ny) and
         BodyFree(tw, (cx + nx) / 2.0 + 0.5, (cy + ny) / 2.0 + 0.5) and
         BodyFree(tw, nx + 0.5, ny + 0.5) then begin
        seenBody[Idx(nx, ny)] := True; qx[tail] := nx; qy[tail] := ny; Inc(tail);
      end;
    end;
  end;

  writeln('  reachable: ', nTile, ' tiles, ', nBody, ' with a body on the voxel field');
  Check(nBody >= (nTile * 95) div 100,
    'the body reaches at least 95% of the tile-reachable area (posts do not seal passages)');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' checks failed'); Halt(1); end;
end.
