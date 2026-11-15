unit player;

{** The player's position on the dungeon map.

  The player occupies one tile and moves a tile at a time, blocked by anything not
  walkable (walls, unexcavated rock). This stays small; facing, stats, and
  inventory arrive with the gameplay releases. }

{$mode objfpc}{$H+}

interface

uses
  tilemap;

type
  TPlayer = record
    cx, cy: longint;
  end;

procedure PlayerInit(out p: TPlayer; const m: TTileMap);
procedure PlayerMove(var p: TPlayer; dx, dy: longint; const m: TTileMap);

implementation

procedure PlayerInit(out p: TPlayer; const m: TTileMap);
begin
  p.cx := m.spawnX;
  p.cy := m.spawnY;
end;

procedure PlayerMove(var p: TPlayer; dx, dy: longint; const m: TTileMap);
begin
  if TileWalkable(m, p.cx + dx, p.cy + dy) then begin
    p.cx := p.cx + dx;
    p.cy := p.cy + dy;
  end;
end;

end.
