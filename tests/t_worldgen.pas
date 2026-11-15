program t_worldgen;

{** Tests dungeon generation: reproducibility, a connected room graph, and a
  walkable spawn. All GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, roomgraph, worldgen;

var
  fails: longint;

procedure Check(cond: boolean; const msg: string);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function MapsEqual(const a, b: TTileMap): boolean;
var
  i: longint;
begin
  MapsEqual := false;
  if (a.w <> b.w) or (a.h <> b.h) then exit;
  if (a.spawnX <> b.spawnX) or (a.spawnY <> b.spawnY) then exit;
  for i := 0 to a.w * a.h - 1 do
    if a.cells[i] <> b.cells[i] then exit;
  MapsEqual := true;
end;

function Connected(const g: TRoomGraph): boolean;
{ Breadth-first over portals; every room must be reachable from room 0. }
var
  visited: array of boolean;
  queue: array of longint;
  head, tail, i, r, count: longint;
begin
  Connected := false;
  if g.nrooms = 0 then exit;
  SetLength(visited, g.nrooms);
  SetLength(queue, g.nrooms);
  queue[0] := 0; visited[0] := true; head := 0; tail := 1; count := 1;
  while head < tail do begin
    r := queue[head]; Inc(head);
    for i := 0 to g.nportals - 1 do begin
      if (g.portals[i].a = r) and not visited[g.portals[i].b] then begin
        visited[g.portals[i].b] := true; queue[tail] := g.portals[i].b;
        Inc(tail); Inc(count);
      end;
      if (g.portals[i].b = r) and not visited[g.portals[i].a] then begin
        visited[g.portals[i].a] := true; queue[tail] := g.portals[i].a;
        Inc(tail); Inc(count);
      end;
    end;
  end;
  Connected := count = g.nrooms;
end;

var
  m1, m2, m3: TTileMap;
  g1, g2, g3: TRoomGraph;
begin
  fails := 0;

  GenerateDungeon(m1, g1, 64, 64, 2024);
  GenerateDungeon(m2, g2, 64, 64, 2024);
  GenerateDungeon(m3, g3, 64, 64, 2025);

  Check(MapsEqual(m1, m2), 'same seed did not reproduce the level');
  Check(not MapsEqual(m1, m3), 'different seeds produced the same level');

  Check(g1.nrooms > 0, 'no rooms generated');
  Check(g1.nportals = g1.nrooms - 1, 'portals should equal rooms - 1 (a tree)');
  Check(Connected(g1), 'room graph is not connected');
  Check(TileWalkable(m1, m1.spawnX, m1.spawnY), 'spawn tile is not walkable');

  writeln('  ', g1.nrooms, ' rooms, ', g1.nportals, ' portals, spawn (',
          m1.spawnX, ',', m1.spawnY, ')');
  if fails = 0 then writeln('  ok') else halt(1);
end.
