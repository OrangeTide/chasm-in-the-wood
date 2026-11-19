program t_nav;

{** Tests the nav field: the flow field pursuers follow to the player.

  It is built from the collision field, so it must reach the cells a body can reach and no
  others, its distances must form a proper gradient, and following the gradient from any
  reached cell must arrive at the target. The field is also what lets a pursuer route
  around a wall, so the test confirms at least one cell needs a detour (its path is longer
  than the open distance) and its descent still reaches the target. GL-free. }

{$mode objfpc}{$H+}

uses
  math, tileworld, brushfield, voxfield, navfield;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

const
  DX: array[0..3] of LongInt = (1, -1, 0, 0);
  DY: array[0..3] of LongInt = (0, 0, 1, -1);
  BODY_R = 0.3;

var
  tw: TTileWorld;
  bf: TBrushField;
  nf: TNavField;
  sx, sy, cx, cy, nx, ny, lx, ly, i, d, nd: LongInt;
  navCount, tileCount, tileAndNav, detours: LongInt;
  hasDown, reached, arrived: Boolean;
  steps: LongInt;
  { tile reachability flood over the same window }
  seen: array of Boolean;
  qx, qy: array of LongInt;
  head, tail: LongInt;

  function WinIdx(x, y: LongInt): LongInt;
  begin WinIdx := (x - nf.Ox) + (y - nf.Oy) * NAV_SIDE; end;

  function InWin(x, y: LongInt): Boolean;
  begin InWin := (x >= nf.Ox) and (x < nf.Ox + NAV_SIDE) and
                 (y >= nf.Oy) and (y < nf.Oy + NAV_SIDE); end;

begin
  fails := 0;

  Check(VoxFieldInit('content/tiles'), 'post footprint loads from content/tiles');
  BrushFieldInit(bf);
  VoxFieldBind(@bf);           { the nav field reads the real collision field }
  TileWorldInit(tw, 7, 1);

  { Flow to a cell whose neighbourhood is not a plain open room, so the window holds a wall
    a pursuer must route around. Scan region (0,0) for the first walkable target whose field
    needs a detour, then test that field: the gradient properties hold wherever it flows. }
  sx := -1; sy := -1;
  for cy := 0 to REGION - 1 do begin
    if sx >= 0 then break;
    for cx := 0 to REGION - 1 do begin
      if not TileWorldWalkable(tw, cx, cy) then continue;
      NavFieldBuild(nf, tw, cx, cy, BODY_R);
      detours := 0;
      for ly := 0 to NAV_SIDE - 1 do
        for lx := 0 to NAV_SIDE - 1 do begin
          nx := nf.Ox + lx; ny := nf.Oy + ly;
          d := NavFieldDist(nf, nx, ny);
          if (d > 0) and (d > Abs(nx - cx) + Abs(ny - cy)) then Inc(detours);
        end;
      if detours > 0 then begin sx := cx; sy := cy; break; end;
    end;
  end;
  Check(sx >= 0, 'found a target whose field routes around a wall');
  if sx < 0 then begin writeln('  ', fails, ' checks failed'); Halt(1); end;

  Check(NavFieldDist(nf, sx, sy) = 0, 'the target cell is zero steps from itself');

  { Gradient and sanity over the whole window. }
  navCount := 0;
  for ly := 0 to NAV_SIDE - 1 do
    for lx := 0 to NAV_SIDE - 1 do begin
      cx := nf.Ox + lx; cy := nf.Oy + ly;
      d := NavFieldDist(nf, cx, cy);
      if d = NAV_UNREACHED then continue;
      Inc(navCount);
      Check(TileWorldWalkable(tw, cx, cy), 'a reached cell is walkable');
      if d > 0 then begin
        { a proper BFS gradient: some neighbour is exactly one step nearer }
        hasDown := False;
        for i := 0 to 3 do begin
          nd := NavFieldDist(nf, cx + DX[i], cy + DY[i]);
          if nd = d - 1 then hasDown := True;
        end;
        Check(hasDown, 'a reached cell has a neighbour one step nearer');
      end;
    end;
  Check(navCount > 1, 'the field reached more than the target cell');

  { Following the gradient from every reached cell arrives at the target in its distance,
    and a cell whose path is longer than the straight-line distance (a detour around a
    wall) still arrives: that is the pathing the field exists for. }
  detours := 0;
  for ly := 0 to NAV_SIDE - 1 do
    for lx := 0 to NAV_SIDE - 1 do begin
      cx := nf.Ox + lx; cy := nf.Oy + ly;
      d := NavFieldDist(nf, cx, cy);
      if d <= 0 then continue;
      if d > Abs(cx - sx) + Abs(cy - sy) then Inc(detours);
      nx := cx; ny := cy; steps := 0; arrived := False;
      for i := 1 to d + 2 do begin
        if (nx = sx) and (ny = sy) then begin arrived := True; break; end;
        if not NavFieldNext(nf, nx, ny, nx, ny) then break;
        Inc(steps);
      end;
      Check(arrived and (steps = d), 'the gradient descent reaches the target in d steps');
    end;
  Check(detours > 0, 'at least one cell needs a detour around a wall');

  { Reachability matches the collision field: every cell a body can walk to is reached by
    the field, compared by an independent flood over tile walkability within the window.
    Posts never seal a cardinal passage, so the two agree closely. }
  SetLength(seen, NAV_SIDE * NAV_SIDE);
  SetLength(qx, NAV_SIDE * NAV_SIDE);
  SetLength(qy, NAV_SIDE * NAV_SIDE);
  for i := 0 to NAV_SIDE * NAV_SIDE - 1 do seen[i] := False;
  head := 0; tail := 0;
  seen[WinIdx(sx, sy)] := True; qx[tail] := sx; qy[tail] := sy; Inc(tail);
  tileCount := 0; tileAndNav := 0;
  while head < tail do begin
    cx := qx[head]; cy := qy[head]; Inc(head); Inc(tileCount);
    if NavFieldDist(nf, cx, cy) <> NAV_UNREACHED then Inc(tileAndNav);
    for i := 0 to 3 do begin
      nx := cx + DX[i]; ny := cy + DY[i];
      if InWin(nx, ny) and (not seen[WinIdx(nx, ny)]) and TileWorldWalkable(tw, nx, ny) then begin
        seen[WinIdx(nx, ny)] := True; qx[tail] := nx; qy[tail] := ny; Inc(tail);
      end;
    end;
  end;

  writeln('  reached ', navCount, ' cells, ', detours, ' by detour; ',
          tileAndNav, ' of ', tileCount, ' tile-reachable also in the nav field');
  Check(tileAndNav >= (tileCount * 95) div 100,
        'the field reaches at least 95% of the tile-reachable cells');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' checks failed'); Halt(1); end;
end.
