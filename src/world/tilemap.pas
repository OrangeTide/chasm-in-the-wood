unit tilemap;

{** The logical dungeon map.

  A grid of tile codes that drives gameplay: movement, collision, and later
  line-of-sight and spawning. It carries no geometry; the voxel world (see world)
  renders it. Keeping the logical map separate from the voxels means movement and
  rules never depend on how a tile looks.

  For now the map is one bounded region. When the world starts streaming, this
  becomes a chunked, unbounded structure behind the same queries. }

{$mode objfpc}{$H+}

interface

const
  TILE_ROCK  = 0;   { unexcavated; not walkable, not drawn }
  TILE_FLOOR = 1;
  TILE_WALL  = 2;
  TILE_DOOR  = 3;
  TILE_STAIRS_DOWN = 4;
  TILE_STAIRS_UP   = 5;

type
  TTileMap = record
    w, h: longint;
    cells: array of byte;
    spawnX, spawnY: longint;
  end;

procedure TileMapInit(out m: TTileMap; w, h: longint);
function TileGet(const m: TTileMap; cx, cy: longint): byte;
procedure TileSet(var m: TTileMap; cx, cy: longint; v: byte);
function TileInBounds(const m: TTileMap; cx, cy: longint): boolean;
function TileWalkable(const m: TTileMap; cx, cy: longint): boolean;

implementation

procedure TileMapInit(out m: TTileMap; w, h: longint);
begin
  m.w := w; m.h := h;
  m.spawnX := 0; m.spawnY := 0;
  SetLength(m.cells, w * h);
  FillChar(m.cells[0], w * h, TILE_ROCK);
end;

function TileInBounds(const m: TTileMap; cx, cy: longint): boolean;
begin
  TileInBounds := (cx >= 0) and (cy >= 0) and (cx < m.w) and (cy < m.h);
end;

function TileGet(const m: TTileMap; cx, cy: longint): byte;
begin
  if TileInBounds(m, cx, cy) then TileGet := m.cells[cx + cy * m.w]
  else TileGet := TILE_ROCK;
end;

procedure TileSet(var m: TTileMap; cx, cy: longint; v: byte);
begin
  if TileInBounds(m, cx, cy) then m.cells[cx + cy * m.w] := v;
end;

function TileWalkable(const m: TTileMap; cx, cy: longint): boolean;
var
  t: byte;
begin
  t := TileGet(m, cx, cy);
  TileWalkable := (t = TILE_FLOOR) or (t = TILE_DOOR) or
                  (t = TILE_STAIRS_DOWN) or (t = TILE_STAIRS_UP);
end;

end.
