unit entities;
{ Deterministic placement of monsters and item props in the dungeon. Like the tiles  }
{ themselves, an entity is a pure function of the depth and region, so walking away    }
{ and back regenerates the same inhabitants. For 0.5.0 the entities are static: they    }
{ are placed and drawn, with movement and combat arriving in the turn loop.             }

{$mode objfpc}{$H+}

interface

uses
  tileworld, content;

type
  TEntityKind = (enMonster, enProp);

  TEntity = record
    Kind:   TEntityKind;
    Cx, Cy: LongInt;          { global tile }
    DefIdx: LongInt;          { index into content Monsters or Items }
    R, G, B: Single;          { draw tint }
    Size:   TSizeClass;       { monster bulk (enMonster only) }
  end;

  TEntitySet = record
    List:     array of TEntity;
    Count:    LongInt;
    Monsters: LongInt;
    Props:    LongInt;
  end;

{ Rebuild the entity set for the square of regions within radius of (centerRx,
  centerRy). The tile (avoidCx, avoidCy) is left empty, so the player never shares a
  tile with a freshly placed monster. }
procedure EntitiesBuild(var es: TEntitySet; const c: TContent; var tw: TTileWorld;
  centerRx, centerRy, radius, avoidCx, avoidCy: LongInt);

{ The roaming area a zone theme maps to, for picking the local monsters. }
function ThemeArea(theme: LongInt): TArea;

implementation

function ThemeArea(theme: LongInt): TArea;
begin
  case theme of
    0: ThemeArea := arCrypt;      { Catacombs }
    1: ThemeArea := arCave;       { Warrens }
    2: ThemeArea := arCoast;      { Cistern }
    3: ThemeArea := arCrypt;      { Cathedral }
    4: ThemeArea := arInfernal;   { Embers }
  else ThemeArea := arCave;
  end;
end;

function HashRC(a, b, c, d: LongInt): LongWord;
{ A small FNV-1a mix over the inputs; wraps mod 2^32 by LongWord arithmetic. }
begin
  HashRC := 2166136261;
  HashRC := (HashRC xor LongWord(a)) * 16777619;
  HashRC := (HashRC xor LongWord(b)) * 16777619;
  HashRC := (HashRC xor LongWord(c)) * 16777619;
  HashRC := (HashRC xor LongWord(d)) * 16777619;
end;

function StrHash(const s: String): LongWord;
var
  i: LongInt;
begin
  StrHash := 2166136261;
  for i := 1 to Length(s) do
    StrHash := (StrHash xor LongWord(Ord(s[i]))) * 16777619;
end;

procedure MonsterColor(const id: String; out r, g, b: Single);
{ A stable colour per monster type, kept bright enough to read against the floor. }
var
  h: LongWord;
begin
  h := StrHash(id);
  r := 0.40 + ((h shr 0)  and 255) / 255.0 * 0.60;
  g := 0.40 + ((h shr 8)  and 255) / 255.0 * 0.60;
  b := 0.40 + ((h shr 16) and 255) / 255.0 * 0.60;
end;

function IsPropKind(const kind: String): Boolean;
begin
  IsPropKind := (kind = 'treasure') or (kind = 'potion') or
                (kind = 'light') or (kind = 'misc');
end;

procedure PropColor(const kind: String; out r, g, b: Single);
begin
  if kind = 'treasure' then begin r := 0.85; g := 0.70; b := 0.20; end
  else if kind = 'potion' then begin r := 0.30; g := 0.75; b := 0.40; end
  else if kind = 'light' then begin r := 0.95; g := 0.65; b := 0.25; end
  else begin r := 0.75; g := 0.70; b := 0.55; end;   { misc }
end;

procedure Append(var es: TEntitySet; const e: TEntity);
begin
  if es.Count >= Length(es.List) then
    SetLength(es.List, (es.Count + 1) * 2);
  es.List[es.Count] := e;
  Inc(es.Count);
end;

procedure AddMonster(var es: TEntitySet; const c: TContent; area: TArea;
  gx, gy: LongInt; h: LongWord);
var
  cand: array of LongInt;
  nc, i, pick: LongInt;
  e: TEntity;
begin
  if Length(c.Monsters) = 0 then exit;
  SetLength(cand, Length(c.Monsters));
  nc := 0;
  for i := 0 to High(c.Monsters) do
    if area in c.Monsters[i].Areas then begin cand[nc] := i; Inc(nc); end;
  { No local monster for this area: fall back to the whole roster. }
  if nc = 0 then
    for i := 0 to High(c.Monsters) do begin cand[nc] := i; Inc(nc); end;
  pick := cand[(h shr 8) mod LongWord(nc)];
  e.Kind := enMonster;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := pick;
  e.Size := c.Monsters[pick].Size;
  MonsterColor(c.Monsters[pick].Id, e.R, e.G, e.B);
  Append(es, e);
  Inc(es.Monsters);
end;

procedure AddProp(var es: TEntitySet; const c: TContent; gx, gy: LongInt;
  h: LongWord);
var
  cand: array of LongInt;
  nc, i, pick: LongInt;
  e: TEntity;
begin
  if Length(c.Items) = 0 then exit;
  SetLength(cand, Length(c.Items));
  nc := 0;
  for i := 0 to High(c.Items) do
    if IsPropKind(c.Items[i].Kind) then begin cand[nc] := i; Inc(nc); end;
  if nc = 0 then exit;
  pick := cand[(h shr 8) mod LongWord(nc)];
  e.Kind := enProp;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := pick;
  e.Size := szSmall;
  PropColor(c.Items[pick].Kind, e.R, e.G, e.B);
  Append(es, e);
  Inc(es.Props);
end;

procedure EntitiesBuild(var es: TEntitySet; const c: TContent; var tw: TTileWorld;
  centerRx, centerRy, radius, avoidCx, avoidCy: LongInt);
var
  rx, ry, n, idx, depth, gx, gy: LongInt;
  area: TArea;
  ref: TRoomRef;
  h: LongWord;
begin
  es.Count := 0; es.Monsters := 0; es.Props := 0;
  depth := TileWorldDepth(tw);
  for ry := centerRy - radius to centerRy + radius do
    for rx := centerRx - radius to centerRx + radius do begin
      area := ThemeArea(TileWorldThemeAt(tw,
        rx * REGION + REGION div 2, ry * REGION + REGION div 2));
      n := TileWorldRegionRoomCount(tw, rx, ry);
      for idx := 0 to n - 1 do begin
        h := HashRC(depth, rx, ry, idx);
        { roll 0..5: 0,1 a monster, 2 a prop, 3..5 an empty room }
        if (h mod 6) > 2 then continue;
        ref.Rx := rx; ref.Ry := ry; ref.Idx := idx;
        if not TileWorldRoomCenter(tw, ref, gx, gy) then continue;
        if (gx = avoidCx) and (gy = avoidCy) then continue;
        if (h mod 6) <= 1 then AddMonster(es, c, area, gx, gy, h)
        else AddProp(es, c, gx, gy, h);
      end;
    end;
end;

end.
