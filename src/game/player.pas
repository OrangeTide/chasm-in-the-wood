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
    Cx, Cy: LongInt;
  end;

procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);
procedure PlayerMove(var p: TPlayer; dx, dy: LongInt; var tw: TTileWorld);

implementation

procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);
begin
  p.Cx := sx;
  p.Cy := sy;
end;

procedure PlayerMove(var p: TPlayer; dx, dy: LongInt; var tw: TTileWorld);
begin
  if TileWorldWalkable(tw, p.Cx + dx, p.Cy + dy) then begin
    p.Cx := p.Cx + dx;
    p.Cy := p.Cy + dy;
  end;
end;

end.
