program t_brushdef;

{** Tests the brush registry's socket predicates: the conditions that decide where each
  modular piece belongs. GL-free; queries a generated dungeon. }

{$mode objfpc}{$H+}

uses
  tilemap, tileworld, brushdef;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  tw: TTileWorld;
  tx, ty, d: LongInt;
  haveFloor, haveDown, haveSolid, haveGate, havePost, haveWall, haveOpenEdge: Boolean;
  dx: array[0..3] of LongInt = (0, -1, 0, 1);
  dy: array[0..3] of LongInt = (-1, 0, 1, 0);
begin
  fails := 0;

  { The registry is complete: every tile that shows a piece has a descriptor, and the three
    anchors are all represented. }
  Check(Length(DUNGEON_BRUSHES) = 8, 'registry has the eight dungeon brushes');

  TileWorldInit(tw, 7, 1);

  haveFloor := False; haveDown := False; haveSolid := False;
  haveGate := False; havePost := False; haveWall := False; haveOpenEdge := False;

  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do begin
      case TileAt(tw, tx, ty) of
        TILE_FLOOR:
          if not haveFloor then begin
            haveFloor := True;
            { A floor cell gets a floor (open socket) and nothing else. }
            Check(SocketCell(skOpenCell, tw, tx, ty), 'floor cell matches the floor socket');
            Check(not SocketCell(skStairDnCell, tw, tx, ty), 'floor cell is not a down-stair');
            Check(not SocketCell(skGateCell, tw, tx, ty), 'floor cell is not a gate');
            Check(not SocketCell(skPropCell, tw, tx, ty), 'floor cell is not a prop');
          end;
        TILE_STAIRS_DOWN:
          if not haveDown then begin
            haveDown := True;
            { The down-stair opens into a hole, so it takes no floor. }
            Check(not SocketCell(skOpenCell, tw, tx, ty), 'down-stair takes no floor');
            Check(SocketCell(skStairDnCell, tw, tx, ty), 'down-stair matches its socket');
          end;
        TILE_DOOR_LOCKED:
          if not haveGate then begin
            haveGate := True;
            { A gate sits on a floor and bars the way. }
            Check(SocketCell(skOpenCell, tw, tx, ty), 'gate cell still gets a floor under it');
            Check(SocketCell(skGateCell, tw, tx, ty), 'gate cell matches the gate socket');
          end;
      end;
      if (not haveSolid) and TileWorldSolid(tw, tx, ty) then begin
        haveSolid := True;
        Check(not SocketCell(skOpenCell, tw, tx, ty), 'a solid cell takes no floor');
      end;
      if (not havePost) and TileWorldPostAt(tw, tx, ty) then begin
        havePost := True;
        Check(SocketCorner(skPostCorner, tw, tx, ty), 'a post corner matches the post socket');
      end;
      { A wall panel belongs on an open cell's edge that faces a solid neighbour, and not on
        an edge between two open cells. }
      if (not TileWorldSolid(tw, tx, ty)) then
        for d := 0 to 3 do begin
          if (not haveWall) and TileWorldSolid(tw, tx + dx[d], ty + dy[d]) then begin
            haveWall := True;
            Check(SocketEdge(skWallEdge, tw, tx, ty, dx[d], dy[d]), 'wall socket on a solid-facing edge');
          end;
          if (not haveOpenEdge) and (not TileWorldSolid(tw, tx + dx[d], ty + dy[d])) then begin
            haveOpenEdge := True;
            Check(not SocketEdge(skWallEdge, tw, tx, ty, dx[d], dy[d]), 'no wall on an open-facing edge');
          end;
        end;
    end;

  Check(haveFloor, 'the dungeon has a floor cell');
  Check(haveDown, 'the dungeon has a down-stair');
  Check(haveSolid, 'the dungeon has a solid cell');
  Check(havePost, 'the dungeon has a post corner');
  Check(haveWall, 'the dungeon has a wall edge');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' checks failed'); Halt(1); end;
end.
