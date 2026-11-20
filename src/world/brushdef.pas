unit brushdef;

{** The brush registry: every modular piece the dungeon places, described as data.

  A brush is a modular voxel piece (a floor, a wall panel, a corner post, a door, a stair).
  Rather than hard-code where each one goes, the registry describes each brush by its
  socket: the local solid/open pattern it connects to. One table then drives rendering (draw
  the piece), collision (block its footprint), and, later, generation (assemble pieces by
  matching sockets). Because all three read placement from the same table through the same
  tileworld queries, they cannot drift apart.

  A brush carries:
    - an anchor, the kind of map element it attaches to: a cell, one of a cell's four edges,
      or a grid corner;
    - a socket, the requirement on the surrounding tiles that must hold for it to belong
      there (its "what must be next to me"); the matched direction then sets its rotation;
    - a style, how its transform is built once the socket matches;
    - a blocks flag, whether it contributes a footprint to the collision field.

  To add a piece, add a row and, if its placement is new, one style. Nothing else changes.
  A new wall variant or corner piece is a row alone. }

{$mode objfpc}{$H+}

interface

uses
  tilemap, tileworld, tilesock;

type
  { The map element a brush attaches to (its socket anchor). }
  TBrushAnchor = (baCell, baEdge, baCorner);

  { The socket requirement: the surrounding pattern a brush connects to. }
  TBrushSocket = (
    skOpenCell,     { a cell that is not solid and not a stair-down: it gets a floor }
    skWallEdge,     { an open cell's edge facing a solid neighbour: a wall panel }
    skPostCorner,   { a grid corner where wall panels turn: a beam post }
    skDoorCell,     { an open door cell: the swung leaf }
    skGateCell,     { a shut, locked door cell: the barred gate }
    skStairUpCell,  { an up-stair cell: the rising flight }
    skStairDnCell,  { a down-stair cell: the descending flight, drawn with no floor }
    skPropCell);    { a prop cell: a centred free-standing model, over its floor }

  { How a brush's transform is built once its socket matches. }
  TBrushStyle = (
    stFloorPlate, stEdgePanel, stCornerPost, stDoorSwing, stGate, stStairUp, stStairDn,
    stProp);

  TBrushDesc = record
    Name:   String[12];        { the mesh stem: <env>/<name>.vox, and the tilekit kind }
    Socket: TBrushSocket;
    Anchor: TBrushAnchor;
    Style:  TBrushStyle;
    Blocks: Boolean;           { contributes a footprint to the collision field }
  end;

const
  { The dungeon brush set. Order is draw order within a cell: the floor first, then the
    pieces that stand on it. }
  DUNGEON_BRUSHES: array[0..7] of TBrushDesc = (
    (Name: 'floor';    Socket: skOpenCell;    Anchor: baCell;   Style: stFloorPlate; Blocks: False),
    (Name: 'wall';     Socket: skWallEdge;    Anchor: baEdge;   Style: stEdgePanel;  Blocks: False),
    (Name: 'door';     Socket: skDoorCell;    Anchor: baCell;   Style: stDoorSwing;  Blocks: False),
    (Name: 'doorleaf'; Socket: skGateCell;    Anchor: baCell;   Style: stGate;       Blocks: False),
    (Name: 'stairup';  Socket: skStairUpCell; Anchor: baCell;   Style: stStairUp;    Blocks: False),
    (Name: 'stairdn';  Socket: skStairDnCell; Anchor: baCell;   Style: stStairDn;    Blocks: False),
    (Name: 'post';     Socket: skPostCorner;  Anchor: baCorner; Style: stCornerPost; Blocks: True),
    (Name: 'prop';     Socket: skPropCell;    Anchor: baCell;   Style: stProp;       Blocks: False)
  );

{ Socket predicates: does a brush with this socket belong at this map element? The renderer,
  the collision field, and generation all ask these, so they place brushes identically. }
function SocketCell(sock: TBrushSocket; var tw: TTileWorld; tx, ty: LongInt): Boolean;
function SocketEdge(sock: TBrushSocket; var tw: TTileWorld; tx, ty, dx, dy: LongInt): Boolean;
function SocketCorner(sock: TBrushSocket; var tw: TTileWorld; gx, gy: LongInt): Boolean;

implementation

function SocketCell(sock: TBrushSocket; var tw: TTileWorld; tx, ty: LongInt): Boolean;
begin
  case sock of
    skOpenCell:
      SocketCell := (not TileWorldSolid(tw, tx, ty)) and
                    (TileAt(tw, tx, ty) <> TILE_STAIRS_DOWN);
    skDoorCell:    SocketCell := TileAt(tw, tx, ty) = TILE_DOOR;
    skGateCell:    SocketCell := TileAt(tw, tx, ty) = TILE_DOOR_LOCKED;
    skStairUpCell: SocketCell := TileAt(tw, tx, ty) = TILE_STAIRS_UP;
    skStairDnCell: SocketCell := TileAt(tw, tx, ty) = TILE_STAIRS_DOWN;
    skPropCell:    SocketCell := TileAt(tw, tx, ty) = TILE_PROP;
  else
    SocketCell := False;
  end;
end;

function BrushProbe(ctx: Pointer; x, y: LongInt): Byte;
{ Read the streaming world as a cell probe, so the wall edge socket shares its one
  definition with generation and collision. }
begin
  BrushProbe := TileAt(PTileWorld(ctx)^, x, y);
end;

function SocketEdge(sock: TBrushSocket; var tw: TTileWorld; tx, ty, dx, dy: LongInt): Boolean;
begin
  case sock of
    skWallEdge: SocketEdge := SockWallEdge(@BrushProbe, @tw, tx, ty, dx, dy);
  else
    SocketEdge := False;
  end;
end;

function SocketCorner(sock: TBrushSocket; var tw: TTileWorld; gx, gy: LongInt): Boolean;
begin
  case sock of
    skPostCorner: SocketCorner := TileWorldPostAt(tw, gx, gy);
  else
    SocketCorner := False;
  end;
end;

end.
