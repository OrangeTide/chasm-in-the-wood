unit worldgraph;

{** Traversal over the stitched world portal graph.

  Each region generates its own rooms and the portals between them, in isolation. The
  tile world stitches these islands together at the seam crossings: the room a region
  reaches at each edge is joined to the matching edge room of the neighbour across the
  seam. The result is one connected graph spanning every region and every zone.

  This unit walks that graph. It does not store it; the graph is produced on demand by
  the tile world, room by room, so traversal works on the unbounded world without
  holding it all in memory. A breadth-first search answers whether two rooms are
  connected and how many portals apart they are, which is how the engine confirms that
  separately generated zones form one seamless space. }

{$mode objfpc}{$H+}

interface

uses
  tileworld;

{ Portal-hop distance from room a to room b over the stitched graph: 0 when they are
  the same room, a positive hop count when b is reachable, or -1 when it is not found
  within maxRooms explored rooms. The cap keeps a search bounded on the infinite
  world. }
function WorldGraphDistance(var tw: TTileWorld; const a, b: TRoomRef;
  maxRooms: LongInt): LongInt;

{ Whether b is reachable from a within maxRooms explored rooms. }
function WorldGraphConnected(var tw: TTileWorld; const a, b: TRoomRef;
  maxRooms: LongInt): Boolean;

implementation

function SameRoom(const a, b: TRoomRef): Boolean;
begin
  SameRoom := (a.Rx = b.Rx) and (a.Ry = b.Ry) and (a.Idx = b.Idx);
end;

function WorldGraphDistance(var tw: TTileWorld; const a, b: TRoomRef;
  maxRooms: LongInt): LongInt;
var
  seen: array of TRoomRef;
  dist: array of LongInt;
  nseen, head, i, cur, nn: LongInt;
  nbrs: array[0..31] of TRoomRef;

  function Index(const r: TRoomRef): LongInt;
  { The visited-list slot for r, or -1 if it has not been seen. }
  var
    j: LongInt;
  begin
    for j := 0 to nseen - 1 do
      if SameRoom(seen[j], r) then begin Index := j; exit; end;
    Index := -1;
  end;

  procedure Visit(const r: TRoomRef; d: LongInt);
  begin
    if nseen >= length(seen) then begin
      SetLength(seen, nseen * 2 + 16);
      SetLength(dist, nseen * 2 + 16);
    end;
    seen[nseen] := r; dist[nseen] := d; Inc(nseen);
  end;

begin
  nseen := 0;
  SetLength(seen, 16);
  SetLength(dist, 16);
  Visit(a, 0);
  head := 0;
  while head < nseen do begin
    if nseen > maxRooms then break;
    if SameRoom(seen[head], b) then begin
      WorldGraphDistance := dist[head];
      exit;
    end;
    cur := head;
    TileWorldRoomNeighbours(tw, seen[cur], nbrs, nn);
    for i := 0 to nn - 1 do
      if Index(nbrs[i]) < 0 then Visit(nbrs[i], dist[cur] + 1);
    Inc(head);
  end;
  WorldGraphDistance := -1;
end;

function WorldGraphConnected(var tw: TTileWorld; const a, b: TRoomRef;
  maxRooms: LongInt): Boolean;
begin
  WorldGraphConnected := WorldGraphDistance(tw, a, b, maxRooms) >= 0;
end;

end.
