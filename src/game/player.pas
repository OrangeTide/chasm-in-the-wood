unit player;

{** The player's position on the dungeon map.

  The player occupies one tile and moves a tile at a time, blocked by anything not
  walkable (walls, unexcavated rock). Movement queries the streaming tile world, so
  the player can walk into regions that have not been generated yet; the query
  generates them. This stays small; facing, stats, and inventory arrive later. }

{$mode objfpc}{$H+}

interface

uses
  tileworld;

type
  TPlayer = record
    cx, cy: longint;
  end;

procedure PlayerInit(out p: TPlayer; sx, sy: longint);
procedure PlayerMove(var p: TPlayer; dx, dy: longint; var tw: TTileWorld);

implementation

procedure PlayerInit(out p: TPlayer; sx, sy: longint);
begin
  p.cx := sx;
  p.cy := sy;
end;

procedure PlayerMove(var p: TPlayer; dx, dy: longint; var tw: TTileWorld);
begin
  if TileWorldWalkable(tw, p.cx + dx, p.cy + dy) then begin
    p.cx := p.cx + dx;
    p.cy := p.cy + dy;
  end;
end;

end.
