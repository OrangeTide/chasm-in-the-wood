program t_worldgen;

{** Tests dungeon generation: reproducibility, a connected room graph, and a
  walkable spawn. All GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, roomgraph, worldgen;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function MapsEqual(const a, b: TTileMap): Boolean;
var
  i: LongInt;
begin
  MapsEqual := False;
  if (a.W <> b.W) or (a.H <> b.H) then exit;
  if (a.SpawnX <> b.SpawnX) or (a.SpawnY <> b.SpawnY) then exit;
  for i := 0 to a.W * a.H - 1 do
    if a.Cells[i] <> b.Cells[i] then exit;
  MapsEqual := True;
end;

function Connected(const g: TRoomGraph): Boolean;
{ Breadth-first over portals; every room must be reachable from room 0. }
var
  visited: array of Boolean;
  queue: array of LongInt;
  head, tail, i, r, count: LongInt;
begin
  Connected := False;
  if g.Nrooms = 0 then exit;
  SetLength(visited, g.Nrooms);
  SetLength(queue, g.Nrooms);
  queue[0] := 0; visited[0] := True; head := 0; tail := 1; count := 1;
  while head < tail do begin
    r := queue[head]; Inc(head);
    for i := 0 to g.Nportals - 1 do begin
      if (g.Portals[i].A = r) and not visited[g.Portals[i].B] then begin
        visited[g.Portals[i].B] := True; queue[tail] := g.Portals[i].B;
        Inc(tail); Inc(count);
      end;
      if (g.Portals[i].B = r) and not visited[g.Portals[i].A] then begin
        visited[g.Portals[i].A] := True; queue[tail] := g.Portals[i].A;
        Inc(tail); Inc(count);
      end;
    end;
  end;
  Connected := count = g.Nrooms;
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

  Check(g1.Nrooms > 0, 'no rooms generated');
  Check(g1.Nportals = g1.Nrooms - 1, 'portals should equal rooms - 1 (a tree)');
  Check(Connected(g1), 'room graph is not connected');
  Check(TileWalkable(m1, m1.SpawnX, m1.SpawnY), 'spawn tile is not walkable');

  writeln('  ', g1.Nrooms, ' rooms, ', g1.Nportals, ' portals, spawn (',
          m1.SpawnX, ',', m1.SpawnY, ')');
  if fails = 0 then writeln('  ok') else halt(1);
end.
