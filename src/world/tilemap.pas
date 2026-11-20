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
  TILE_DOOR_LOCKED = 6;   { a shut door; a key opens it, turning it into TILE_DOOR }
  TILE_PROP  = 7;   { a free-standing prop (a tree, a barrel): blocks movement but shows no
                      wall face, drawn as a centred model standing on the floor }

type
  TTileMap = record
    W, H: LongInt;
    Cells: array of Byte;
    SpawnX, SpawnY: LongInt;
  end;

procedure TileMapInit(out m: TTileMap; w, h: LongInt);
function TileGet(const m: TTileMap; cx, cy: LongInt): Byte;
procedure TileSet(var m: TTileMap; cx, cy: LongInt; v: Byte);
function TileInBounds(const m: TTileMap; cx, cy: LongInt): Boolean;
function TileWalkable(const m: TTileMap; cx, cy: LongInt): Boolean;

implementation

procedure TileMapInit(out m: TTileMap; w, h: LongInt);
begin
  m.W := w; m.H := h;
  m.SpawnX := 0; m.SpawnY := 0;
  SetLength(m.Cells, w * h);
  FillChar(m.Cells[0], w * h, TILE_ROCK);
end;

function TileInBounds(const m: TTileMap; cx, cy: LongInt): Boolean;
begin
  TileInBounds := (cx >= 0) and (cy >= 0) and (cx < m.W) and (cy < m.H);
end;

function TileGet(const m: TTileMap; cx, cy: LongInt): Byte;
begin
  if TileInBounds(m, cx, cy) then TileGet := m.Cells[cx + cy * m.W]
  else TileGet := TILE_ROCK;
end;

procedure TileSet(var m: TTileMap; cx, cy: LongInt; v: Byte);
begin
  if TileInBounds(m, cx, cy) then m.Cells[cx + cy * m.W] := v;
end;

function TileWalkable(const m: TTileMap; cx, cy: LongInt): Boolean;
var
  t: Byte;
begin
  t := TileGet(m, cx, cy);
  TileWalkable := (t = TILE_FLOOR) or (t = TILE_DOOR) or
                  (t = TILE_STAIRS_DOWN) or (t = TILE_STAIRS_UP);
end;

end.
