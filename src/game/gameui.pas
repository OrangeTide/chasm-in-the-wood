unit gameui;
{ The game's interface layer: a desktop of floating windows over the diorama.    }
{ It wraps the gui toolkit behind a plain procedural API so the main program can  }
{ drive it with integers and strings, and never sees the toolkit's own types.    }

{$mode objfpc}{$H+}

interface

type
  { One item as the panels need it: the content index as a payload tag, the drop
    category, an ARGB tile colour, a glyph, and a name. A Tag of -1 means an empty
    worn slot. The game layer fills these; the interface never sees content types. }
  TUIItem = record
    Tag:   LongInt;
    Cat:   LongInt;
    Color: LongInt;
    Glyph: Char;
    Name:  String;
  end;

  { Called when the player rearranges the pack or the worn gear by dragging. The pack
    is the filled bag slots in order; the three worn tags are the content indices worn,
    or -1 when a slot is bare. }
  TInvChangeProc = procedure(const packTags: array of LongInt;
                             weaponTag, armorTag, shieldTag: LongInt);

{ Build the desktop and the status window for a viewW x viewH framebuffer. }
procedure GameUIInit(viewW, viewH: LongInt);

{ Replace the status panel's text with these lines. }
procedure GameUISetStatus(const lines: array of String);

{ The drop category (a CAT_* bit) an item of this kind takes. }
function GameUIItemCat(const kind: String): LongInt;

{ Replace the pack contents shown in the inventory window. }
procedure GameUISetInventory(const items: array of TUIItem);

{ Replace the three worn slots on the equipment doll. A Tag of -1 empties a slot. }
procedure GameUISetWorn(const weapon, armor, shield: TUIItem);

{ Replace the live stat lines on the character sheet. }
procedure GameUISetCharStats(const lines: array of String);

{ Register the callback run after the player drags an item in the panels. }
procedure GameUISetInvChange(cb: TInvChangeProc);

{ Toggle a floating panel: 0 inventory (with the equipment doll), 1 character
  sheet, 2 options. The same call shows a hidden panel and hides a shown one. }
procedure GameUITogglePanel(id: LongInt);

{ Feed a mouse event: kind 0 down, 1 up, 2 move, 3 wheel; button 0 left, 1 middle,
  2 right; wheel the signed scroll delta. }
procedure GameUIMouse(kind, x, y, button, wheel: LongInt);

{ Draw the desktop as an overlay. Call after the 3D scene, before the buffer swap. }
procedure GameUIRender;

procedure GameUIFree;

implementation

uses
  gui, guitheme, guigl, panels;

type
  { A panel that draws a list of text lines, the live game status. }
  THudPanel = class(TWidget)
  private
    FLines: array of String;
  public
    procedure SetLines(const lines: array of String);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

  { Owns the toggle panels and routes the HUD button clicks to them. A plain
    object, not a widget: its methods are the buttons' OnClick handlers. }
  TUIController = class
  public
    Inv:  TInventoryWindow;
    Equ:  TEquipmentWindow;
    Chr:  TCharacterSheet;
    Opts: TOptionsWindow;
    procedure TogglePanel(id: LongInt);
    procedure OnInv(sender: TWidget);
    procedure OnChar(sender: TWidget);
    procedure OnOpts(sender: TWidget);
    procedure DragEnded(sender: TWidget);
  end;

var
  gTheme:   TSystem7Theme;
  gDesktop: TDesktop;
  gCanvas:  TGLCanvas;
  gWin:     TWindow;
  gHud:     THudPanel;
  gCtl:     TUIController;
  gInvChange: TInvChangeProc;

procedure THudPanel.SetLines(const lines: array of String);
var
  i: LongInt;
begin
  SetLength(FLines, Length(lines));
  for i := 0 to High(lines) do FLines[i] := lines[i];
end;

procedure THudPanel.Draw(cv: TCanvas; theme: TTheme);
var
  r: TRect;
  i, lh: LongInt;
begin
  r := AbsRect;
  lh := cv.TextHeight + 4;
  for i := 0 to High(FLines) do
    cv.DrawText(r.Left + 4, r.Top + 4 + i * lh, FLines[i], clBlack);
end;

{ ---- TUIController ---- }

procedure TUIController.TogglePanel(id: LongInt);
var
  show: Boolean;
begin
  case id of
    0: begin
         show := not Inv.Visible;
         Inv.Visible := show;
         Equ.Visible := show;
         if show then begin
           gDesktop.BringToFront(Equ);
           gDesktop.BringToFront(Inv);
         end;
       end;
    1: begin
         show := not Chr.Visible;
         Chr.Visible := show;
         if show then gDesktop.BringToFront(Chr);
       end;
    2: begin
         show := not Opts.Visible;
         Opts.Visible := show;
         if show then gDesktop.BringToFront(Opts);
       end;
  end;
end;

procedure TUIController.OnInv(sender: TWidget);  begin TogglePanel(0); end;
procedure TUIController.OnChar(sender: TWidget); begin TogglePanel(1); end;
procedure TUIController.OnOpts(sender: TWidget); begin TogglePanel(2); end;

procedure TUIController.DragEnded(sender: TWidget);
{ A drag settled: read the new pack and worn layout back and hand it to the game. }
var
  tags: array[0 .. 127] of LongInt;
  pack: array of LongInt;
  n, i: LongInt;
begin
  if not Assigned(gInvChange) then exit;
  Inv.ReadTags(tags, n);
  SetLength(pack, n);
  for i := 0 to n - 1 do pack[i] := tags[i];
  gInvChange(pack, Equ.WornTag(bsMainHand), Equ.WornTag(bsChest),
             Equ.WornTag(bsOffHand));
end;

procedure GameUIInit(viewW, viewH: LongInt);
var
  b: TButton;
begin
  gTheme := TSystem7Theme.Create;
  gDesktop := TDesktop.Create(gTheme, viewW, viewH);
  gCanvas := TGLCanvas.Create(viewW, viewH);

  { status window: the live HUD lines, then a row of panel-toggle buttons }
  gWin := TWindow.Create(gDesktop, 'STATUS', [wfClose, wfDrag, wfZoom], 12, 12, 250, 240);
  gHud := THudPanel.Create(gWin.Content);
  gHud.SetBounds(0, 0, 250, 180);

  gCtl := TUIController.Create;
  b := TButton.Create(gWin.Content, 'INV',  6, 186, 72, 22);  b.OnClick := @gCtl.OnInv;
  b := TButton.Create(gWin.Content, 'CHAR', 86, 186, 72, 22); b.OnClick := @gCtl.OnChar;
  b := TButton.Create(gWin.Content, 'OPTS', 166, 186, 72, 22); b.OnClick := @gCtl.OnOpts;

  { the toggle panels, created hidden and shown on demand }
  gCtl.Inv  := TInventoryWindow.Create(gDesktop, 300, 40);
  gCtl.Equ  := TEquipmentWindow.Create(gDesktop, 580, 40);
  gCtl.Chr  := TCharacterSheet.Create(gDesktop, 300, 330);
  gCtl.Opts := TOptionsWindow.Create(gDesktop, 600, 330);
  gCtl.Inv.Visible := False;
  gCtl.Equ.Visible := False;
  gCtl.Chr.Visible := False;
  gCtl.Opts.Visible := False;
  gDesktop.OnDragEnd := @gCtl.DragEnded;

  gDesktop.BringToFront(gWin);
end;

procedure GameUITogglePanel(id: LongInt);
begin
  if gCtl <> nil then gCtl.TogglePanel(id);
end;

procedure GameUISetStatus(const lines: array of String);
begin
  if gHud <> nil then gHud.SetLines(lines);
end;

function GameUIItemCat(const kind: String): LongInt;
begin
  if kind = 'weapon' then GameUIItemCat := CAT_WEAPON
  else if kind = 'armor' then GameUIItemCat := CAT_ARMOR
  else if kind = 'shield' then GameUIItemCat := CAT_SHIELD
  else if kind = 'potion' then GameUIItemCat := CAT_POTION
  else GameUIItemCat := CAT_MISC;
end;

procedure GameUISetInventory(const items: array of TUIItem);
var
  i: LongInt;
begin
  if gCtl = nil then exit;
  gCtl.Inv.Clear;
  for i := 0 to High(items) do
    gCtl.Inv.Add(items[i].Name, items[i].Cat, TColor(items[i].Color),
                 items[i].Glyph, items[i].Tag);
end;

procedure SetWornSlot(s: TBodySlot; const it: TUIItem);
var
  tile: TDragItem;
begin
  if it.Tag < 0 then
    gCtl.Equ.SetWorn(s, nil)
  else begin
    tile := TDragItem.Create(it.Name, it.Cat, TColor(it.Color), it.Glyph);
    tile.Tag := it.Tag;
    gCtl.Equ.SetWorn(s, tile);
  end;
end;

procedure GameUISetWorn(const weapon, armor, shield: TUIItem);
begin
  if gCtl = nil then exit;
  SetWornSlot(bsMainHand, weapon);
  SetWornSlot(bsChest, armor);
  SetWornSlot(bsOffHand, shield);
end;

procedure GameUISetCharStats(const lines: array of String);
begin
  if gCtl <> nil then gCtl.Chr.SetStats(lines);
end;

procedure GameUISetInvChange(cb: TInvChangeProc);
begin
  gInvChange := cb;
end;

procedure GameUIMouse(kind, x, y, button, wheel: LongInt);
var
  e: TUIEvent;
begin
  if gDesktop = nil then exit;
  FillChar(e, SizeOf(e), 0);
  e.Pos := Pt(x, y);
  e.Button := button;
  e.Wheel := wheel;
  case kind of
    0: e.Kind := ekMouseDown;
    1: e.Kind := ekMouseUp;
    2: e.Kind := ekMouseMove;
    3: e.Kind := ekMouseWheel;
  else exit;
  end;
  gDesktop.Dispatch(e);
end;

procedure GameUIRender;
begin
  if gCanvas = nil then exit;
  gCanvas.BeginFrame;
  gDesktop.PaintAll(gCanvas);
  gCanvas.EndFrame;
end;

procedure GameUIFree;
begin
  if gDesktop <> nil then begin gDesktop.Free; gDesktop := nil; end;
  if gCtl <> nil then begin gCtl.Free; gCtl := nil; end;
  if gCanvas <> nil then begin gCanvas.Free; gCanvas := nil; end;
  if gTheme <> nil then begin gTheme.Free; gTheme := nil; end;
end;

end.
