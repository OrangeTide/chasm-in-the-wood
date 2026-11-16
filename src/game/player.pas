unit player;

{** The player's position and combat stats on the dungeon map.

  The player occupies one tile and moves a tile at a time, blocked by anything not
  walkable (walls, unexcavated rock). Movement queries the streaming tile world, so
  the player can walk into regions that have not been generated yet; the query
  generates them.

  The record also carries the combat stats the turn loop reads: hit points, armour
  class, a to-hit bonus, and a damage die. These are fixed starting values for now;
  deriving them from the species and class tables arrives with character creation. }

{$mode objfpc}{$H+}

interface

uses
  tileworld;

const
  { Starting combat stats, until species and class selection drives them. }
  PLAYER_HP     = 16;
  PLAYER_AC     = 14;
  PLAYER_ATK    = 2;
  PLAYER_DMGDIE = 6;   { melee damage is 1..PLAYER_DMGDIE }

type
  TPlayer = record
    Cx, Cy: LongInt;
    Hp, MaxHp: LongInt;
    Ac, Atk, DmgDie: LongInt;
    Alive: Boolean;
  end;

{ Full new-game init: position and starting combat stats, at full health. }
procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);

{ Move the player to a tile without touching stats, for stair travel between depths. }
procedure PlayerPlace(var p: TPlayer; sx, sy: LongInt);

{ Restore the player to full health and life, for a respawn. }
procedure PlayerRevive(var p: TPlayer);

{ Raw one-tile move, blocked by walls. The turn loop uses its own action path; this
  stays for callers that only need position movement. }
procedure PlayerMove(var p: TPlayer; dx, dy: LongInt; var tw: TTileWorld);

implementation

procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);
begin
  p.Cx := sx;
  p.Cy := sy;
  p.MaxHp := PLAYER_HP;
  p.Hp := PLAYER_HP;
  p.Ac := PLAYER_AC;
  p.Atk := PLAYER_ATK;
  p.DmgDie := PLAYER_DMGDIE;
  p.Alive := True;
end;

procedure PlayerPlace(var p: TPlayer; sx, sy: LongInt);
begin
  p.Cx := sx;
  p.Cy := sy;
end;

procedure PlayerRevive(var p: TPlayer);
begin
  p.Hp := p.MaxHp;
  p.Alive := True;
end;

procedure PlayerMove(var p: TPlayer; dx, dy: LongInt; var tw: TTileWorld);
begin
  if TileWorldWalkable(tw, p.Cx + dx, p.Cy + dy) then begin
    p.Cx := p.Cx + dx;
    p.Cy := p.Cy + dy;
  end;
end;

end.
