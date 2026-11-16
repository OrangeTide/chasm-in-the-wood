unit panels;
{ Game interface panels built on the gui toolkit: a multi-page inventory, an        }
{ equipment paperdoll, a character sheet, and an options window. They add no new     }
{ mechanism; each composes the core widgets. Contents are placeholders until the     }
{ entity and item systems land, so the panels can be wired to real data later.      }

{$mode objfpc}{$H+}

interface

uses
  sysutils, gui;

const
  { Item category bits, used as slot accept masks. }
  CAT_WEAPON = 1;
  CAT_SHIELD = 2;
  CAT_HELMET = 4;
  CAT_ARMOR  = 8;
  CAT_BOOTS  = 16;
  CAT_GLOVES = 32;
  CAT_RING   = 64;
  CAT_AMULET = 128;
  CAT_LEGS   = 256;
  CAT_POTION = 512;
  CAT_MISC   = 1024;

type
  { ---- multi-page inventory ---- }
  TInventoryWindow = class(TWindow)
  private
    FTabs:  TTabBar;
    FPages: array of TItemGrid;
    procedure HandleTab(index: LongInt);
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
    procedure ShowPage(i: LongInt);
    function  Page(i: LongInt): TItemGrid;
    { Empty every slot, freeing the item tiles. }
    procedure Clear;
    { Place one item tile in the next free slot, filling pages in order. False when
      every slot is taken. }
    function  Add(const name: String; cat: LongInt; color: TColor;
                  glyph: Char; tag: LongInt): Boolean;
    { Collect the payload tags of the filled slots, in slot order. }
    procedure ReadTags(out tags: array of LongInt; out n: LongInt);
  end;

  { ---- equipment paperdoll ---- }
  TBodySlot = (bsHead, bsAmulet, bsChest, bsMainHand, bsOffHand,
               bsGloves, bsLegs, bsFeet, bsRing);

  TPaperdoll = class(TWidget)
  private
    FSlots: array[TBodySlot] of TItemSlot;
  public
    constructor Create(AParent: TWidget; l, t, w, h: LongInt);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
    procedure PlaceSlot(s: TBodySlot; l, t, sz, accept: LongInt);
    function  Slot(s: TBodySlot): TItemSlot;
  end;

  TEquipmentWindow = class(TWindow)
  private
    FDoll: TPaperdoll;
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
    function Doll: TPaperdoll;
    { Put an item tile in a worn slot, freeing whatever it held; nil empties it. }
    procedure SetWorn(s: TBodySlot; it: TDragItem);
    { The payload tag of the worn slot, or -1 when empty. }
    function  WornTag(s: TBodySlot): LongInt;
  end;

  { ---- character sheet: flavour header, live stat lines, a scrolling skill list ---- }
  TCharacterSheet = class(TWindow)
  private
    FName, FClass, FSpecies: TLabel;
    FStats: array of TLabel;
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
    { Replace the identity header (name, class, species). }
    procedure SetIdentity(const name, klass, species: String);
    { Replace the live stat lines (health, armour, attack, and the like). }
    procedure SetStats(const lines: array of String);
  end;

  { ---- new-adventurer creation ---- }
  { Fired on Begin with the chosen species and class content indices and the name. }
  TCreateDoneProc = procedure(speciesIdx, classIdx: LongInt; const name: String) of object;

  TCharCreateWindow = class(TWindow)
  private
    FSpNames:  array of String;   { all species names, in content order }
    FClNames:  array of String;   { the offered class names }
    FClIdx:    array of LongInt;  { content index behind each offered class }
    FNames:    array of String;   { the random name pool }
    FSp, FCl:  LongInt;           { chosen species and class content indices }
    FNameI:    LongInt;           { chosen name pool index }
    FSpBtn, FClBtn, FNameBtn, FBeginBtn: TButton;
    procedure OnSpecies(sender: TWidget);
    procedure OnClass(sender: TWidget);
    procedure OnName(sender: TWidget);
    procedure OnBegin(sender: TWidget);
    procedure PickSpecies(index: LongInt);
    procedure PickClass(index: LongInt);
    procedure Refresh;
  public
    OnDone: TCreateDoneProc;
    constructor Create(AParent: TWidget; l, t: LongInt);
    { Fill the pickers. Class names and their content indices run in step; defSp and
      defCl are the initial species and class content indices. }
    procedure Setup(const spNames, clNames: array of String;
                    const clIdx: array of LongInt; const names: array of String;
                    defSp, defCl: LongInt);
  end;

  { ---- options: a few toggles, placeholders for real settings ---- }
  TOptionsWindow = class(TWindow)
  private
    FVsync, FSound: TButton;
    FCamera: TButton;
    FVsyncOn, FSoundOn: Boolean;
    FCam: LongInt;
    procedure OnVsync(sender: TWidget);
    procedure OnSound(sender: TWidget);
    procedure OnCamera(sender: TWidget);
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
  end;

implementation

{ ---- TInventoryWindow ---- }

constructor TInventoryWindow.Create(AParent: TWidget; l, t: LongInt);
var
  i: LongInt;
begin
  inherited Create(AParent, 'INVENTORY', [wfClose, wfDrag, wfZoom], l, t, 264, 230);
  FTabs := TTabBar.Create(Content, 6, 4, 58, 20);
  FTabs.OnChange := @HandleTab;
  SetLength(FPages, 4);
  for i := 0 to 3 do begin
    FTabs.AddTab('BAG' + IntToStr(i + 1));
    { cols, rows, accept, pitch, l, t }
    FPages[i] := TItemGrid.Create(Content, 6, 5, 0, 32, 6, 28);
    FPages[i].Visible := (i = 0);
  end;
end;

procedure TInventoryWindow.HandleTab(index: LongInt);
begin
  ShowPage(index);
end;

procedure TInventoryWindow.ShowPage(i: LongInt);
var
  k: LongInt;
begin
  for k := 0 to High(FPages) do FPages[k].Visible := (k = i);
end;

function TInventoryWindow.Page(i: LongInt): TItemGrid;
begin
  Page := FPages[i];
end;

procedure TInventoryWindow.Clear;
var
  p, col, row: LongInt;
  g: TItemGrid;
  slot: TItemSlot;
begin
  for p := 0 to High(FPages) do begin
    g := FPages[p];
    for row := 0 to g.Rows - 1 do
      for col := 0 to g.Cols - 1 do begin
        slot := g.SlotAt(col, row);
        if slot.Item <> nil then begin
          slot.Item.Free;
          slot.Item := nil;
        end;
      end;
  end;
end;

function TInventoryWindow.Add(const name: String; cat: LongInt; color: TColor;
  glyph: Char; tag: LongInt): Boolean;
var
  p, col, row: LongInt;
  g: TItemGrid;
  slot: TItemSlot;
  it: TDragItem;
begin
  for p := 0 to High(FPages) do begin
    g := FPages[p];
    for row := 0 to g.Rows - 1 do
      for col := 0 to g.Cols - 1 do begin
        slot := g.SlotAt(col, row);
        if slot.Item = nil then begin
          it := TDragItem.Create(name, cat, color, glyph);
          it.Tag := tag;
          slot.Item := it;
          exit(True);
        end;
      end;
  end;
  Add := False;
end;

procedure TInventoryWindow.ReadTags(out tags: array of LongInt; out n: LongInt);
var
  p, col, row: LongInt;
  g: TItemGrid;
  slot: TItemSlot;
begin
  n := 0;
  for p := 0 to High(FPages) do begin
    g := FPages[p];
    for row := 0 to g.Rows - 1 do
      for col := 0 to g.Cols - 1 do begin
        slot := g.SlotAt(col, row);
        if (slot.Item <> nil) and (n < Length(tags)) then begin
          tags[n] := slot.Item.Tag;
          Inc(n);
        end;
      end;
  end;
end;

{ ---- TPaperdoll ---- }

constructor TPaperdoll.Create(AParent: TWidget; l, t, w, h: LongInt);
var
  s: TBodySlot;
begin
  inherited Create(AParent);
  SetBounds(l, t, l + w, t + h);
  for s := Low(TBodySlot) to High(TBodySlot) do FSlots[s] := nil;
end;

procedure TPaperdoll.PlaceSlot(s: TBodySlot; l, t, sz, accept: LongInt);
begin
  FSlots[s] := TItemSlot.Create(Self, accept, l, t, sz);
end;

function TPaperdoll.Slot(s: TBodySlot): TItemSlot;
begin
  Slot := FSlots[s];
end;

procedure TPaperdoll.Draw(cv: TCanvas; theme: TTheme);
var
  r: TRect;
  cx, cy: LongInt;
  skin, line: TColor;
begin
  r := AbsRect;
  cv.FillRect(r, clWhite);
  skin := TColor($FFD9C9A8);
  line := TColor($FF8A764F);
  cx := (r.Left + r.Right) div 2;
  cy := r.Top + 20;
  cv.FillRect(Rect(cx - 12, cy, cx + 12, cy + 22), skin);        { head }
  cv.FrameRect(Rect(cx - 12, cy, cx + 12, cy + 22), line);
  cv.FillRect(Rect(cx - 20, cy + 24, cx + 20, cy + 70), skin);   { torso }
  cv.FrameRect(Rect(cx - 20, cy + 24, cx + 20, cy + 70), line);
  cv.FillRect(Rect(cx - 34, cy + 26, cx - 20, cy + 64), skin);   { left arm }
  cv.FrameRect(Rect(cx - 34, cy + 26, cx - 20, cy + 64), line);
  cv.FillRect(Rect(cx + 20, cy + 26, cx + 34, cy + 64), skin);   { right arm }
  cv.FrameRect(Rect(cx + 20, cy + 26, cx + 34, cy + 64), line);
  cv.FillRect(Rect(cx - 16, cy + 70, cx - 2, cy + 118), skin);   { left leg }
  cv.FrameRect(Rect(cx - 16, cy + 70, cx - 2, cy + 118), line);
  cv.FillRect(Rect(cx + 2, cy + 70, cx + 16, cy + 118), skin);   { right leg }
  cv.FrameRect(Rect(cx + 2, cy + 70, cx + 16, cy + 118), line);
end;

{ ---- TEquipmentWindow ---- }

constructor TEquipmentWindow.Create(AParent: TWidget; l, t: LongInt);
begin
  inherited Create(AParent, 'EQUIPMENT', [wfClose, wfDrag], l, t, 210, 268);
  FDoll := TPaperdoll.Create(Content, 0, 0, 206, 240);
  { Slots flank the figure: four down the left, five down the right. }
  FDoll.PlaceSlot(bsHead,     6, 6,   30, CAT_HELMET);
  FDoll.PlaceSlot(bsChest,    6, 46,  30, CAT_ARMOR);
  FDoll.PlaceSlot(bsLegs,     6, 86,  30, CAT_LEGS);
  FDoll.PlaceSlot(bsFeet,     6, 126, 30, CAT_BOOTS);
  FDoll.PlaceSlot(bsMainHand, 170, 6,   30, CAT_WEAPON);
  FDoll.PlaceSlot(bsOffHand,  170, 46,  30, CAT_SHIELD);
  FDoll.PlaceSlot(bsGloves,   170, 86,  30, CAT_GLOVES);
  FDoll.PlaceSlot(bsRing,     170, 126, 30, CAT_RING);
  FDoll.PlaceSlot(bsAmulet,   170, 166, 30, CAT_AMULET);
end;

function TEquipmentWindow.Doll: TPaperdoll;
begin
  Doll := FDoll;
end;

procedure TEquipmentWindow.SetWorn(s: TBodySlot; it: TDragItem);
var
  slot: TItemSlot;
begin
  slot := FDoll.Slot(s);
  if slot = nil then exit;
  if slot.Item <> nil then slot.Item.Free;
  slot.Item := it;
end;

function TEquipmentWindow.WornTag(s: TBodySlot): LongInt;
var
  slot: TItemSlot;
begin
  slot := FDoll.Slot(s);
  if (slot <> nil) and (slot.Item <> nil) then WornTag := slot.Item.Tag
  else WornTag := -1;
end;

{ ---- TCharacterSheet ---- }

constructor TCharacterSheet.Create(AParent: TWidget; l, t: LongInt);
var
  sv: TScrollView;
  list: TWidget;
  i, y: LongInt;
  skills: array[0..11] of String = (
    'BLADES 42', 'PARRY 28', 'DODGE 35', 'ATHLETICS 50', 'STEALTH 19',
    'LORE 33', 'ALCHEMY 12', 'SURVIVAL 44', 'FOCUS 27', 'HAGGLE 8',
    'LOCKPICK 21', 'FIRST AID 16');
const
  STAT_LINES = 5;   { level/xp, health/armour, attack, two ability rows }
begin
  inherited Create(AParent, 'CHARACTER', [wfClose, wfDrag], l, t, 300, 280);
  FName    := TLabel.Create(Content, 'NAME', 8, 8);
  FClass   := TLabel.Create(Content, 'CLASS', 8, 24);
  FSpecies := TLabel.Create(Content, 'SPECIES', 8, 40);
  { Live stat lines, filled by SetStats; created empty so the panel reads sensibly
    before the game pushes its first update. }
  SetLength(FStats, STAT_LINES);
  for i := 0 to STAT_LINES - 1 do
    FStats[i] := TLabel.Create(Content, '', 8, 60 + i * 16);
  TLabel.Create(Content, 'SKILLS', 8, 150);
  sv := TScrollView.Create(Content, 8, 166, 276, 84);
  list := TWidget.Create(sv);
  y := 4;
  for i := 0 to High(skills) do begin
    TLabel.Create(list, skills[i], 6, y);
    y := y + 16;
  end;
  sv.SetContentSize(y + 4);
end;

procedure TCharacterSheet.SetIdentity(const name, klass, species: String);
begin
  FName.Caption := 'NAME  ' + name;
  FClass.Caption := 'CLASS  ' + klass;
  FSpecies.Caption := 'SPECIES  ' + species;
end;

procedure TCharacterSheet.SetStats(const lines: array of String);
var
  i: LongInt;
begin
  for i := 0 to High(FStats) do
    if i <= High(lines) then FStats[i].Caption := lines[i]
    else FStats[i].Caption := '';
end;

{ ---- TOptionsWindow ---- }

constructor TOptionsWindow.Create(AParent: TWidget; l, t: LongInt);
begin
  inherited Create(AParent, 'OPTIONS', [wfClose, wfDrag], l, t, 200, 150);
  FVsyncOn := True; FSoundOn := False; FCam := 1;
  FVsync := TButton.Create(Content, 'VSYNC  ON', 12, 12, 160, 24);
  FVsync.OnClick := @OnVsync;
  FSound := TButton.Create(Content, 'SOUND  OFF', 12, 44, 160, 24);
  FSound.OnClick := @OnSound;
  FCamera := TButton.Create(Content, 'CAMERA  MED', 12, 76, 160, 24);
  FCamera.OnClick := @OnCamera;
end;

procedure TOptionsWindow.OnVsync(sender: TWidget);
begin
  FVsyncOn := not FVsyncOn;
  if FVsyncOn then FVsync.Caption := 'VSYNC  ON' else FVsync.Caption := 'VSYNC  OFF';
end;

procedure TOptionsWindow.OnSound(sender: TWidget);
begin
  FSoundOn := not FSoundOn;
  if FSoundOn then FSound.Caption := 'SOUND  ON' else FSound.Caption := 'SOUND  OFF';
end;

procedure TOptionsWindow.OnCamera(sender: TWidget);
begin
  FCam := (FCam + 1) mod 3;
  case FCam of
    0: FCamera.Caption := 'CAMERA  NEAR';
    1: FCamera.Caption := 'CAMERA  MED';
    2: FCamera.Caption := 'CAMERA  FAR';
  end;
end;

{ ---- TCharCreateWindow ---- }

constructor TCharCreateWindow.Create(AParent: TWidget; l, t: LongInt);
begin
  inherited Create(AParent, 'NEW ADVENTURER', [wfDrag], l, t, 280, 196);
  FSp := 0; FCl := 0; FNameI := 0;
  TLabel.Create(Content, 'FORGE YOUR ADVENTURER', 10, 8);
  FNameBtn  := TButton.Create(Content, 'NAME',    10, 32, 260, 24);
  FNameBtn.OnClick := @OnName;
  FSpBtn    := TButton.Create(Content, 'SPECIES', 10, 62, 260, 24);
  FSpBtn.OnClick := @OnSpecies;
  FClBtn    := TButton.Create(Content, 'CLASS',   10, 92, 260, 24);
  FClBtn.OnClick := @OnClass;
  FBeginBtn := TButton.Create(Content, 'DESCEND', 10, 128, 260, 28);
  FBeginBtn.OnClick := @OnBegin;
end;

procedure TCharCreateWindow.Setup(const spNames, clNames: array of String;
  const clIdx: array of LongInt; const names: array of String;
  defSp, defCl: LongInt);
var
  i: LongInt;
begin
  SetLength(FSpNames, Length(spNames));
  for i := 0 to High(spNames) do FSpNames[i] := spNames[i];
  SetLength(FClNames, Length(clNames));
  for i := 0 to High(clNames) do FClNames[i] := clNames[i];
  SetLength(FClIdx, Length(clIdx));
  for i := 0 to High(clIdx) do FClIdx[i] := clIdx[i];
  SetLength(FNames, Length(names));
  for i := 0 to High(names) do FNames[i] := names[i];
  FSp := defSp; FCl := defCl; FNameI := 0;
  Refresh;
end;

procedure TCharCreateWindow.Refresh;
var
  i: LongInt;
  cn: String;
begin
  if (Length(FNames) > 0) and (FNameI >= 0) and (FNameI < Length(FNames)) then
    FNameBtn.Caption := 'NAME  ' + FNames[FNameI]
  else
    FNameBtn.Caption := 'NAME  ?';
  if (FSp >= 0) and (FSp < Length(FSpNames)) then
    FSpBtn.Caption := 'SPECIES  ' + FSpNames[FSp]
  else
    FSpBtn.Caption := 'SPECIES  ?';
  cn := '?';
  for i := 0 to High(FClIdx) do
    if FClIdx[i] = FCl then cn := FClNames[i];
  FClBtn.Caption := 'CLASS  ' + cn;
end;

procedure TCharCreateWindow.OnSpecies(sender: TWidget);
var
  d: TDesktop;
begin
  d := Root;
  if d <> nil then
    d.ShowPopup(FSpNames, Pt(FSpBtn.AbsRect.Left, FSpBtn.AbsRect.Bottom),
                @PickSpecies);
end;

procedure TCharCreateWindow.OnClass(sender: TWidget);
var
  d: TDesktop;
begin
  d := Root;
  if d <> nil then
    d.ShowPopup(FClNames, Pt(FClBtn.AbsRect.Left, FClBtn.AbsRect.Bottom),
                @PickClass);
end;

procedure TCharCreateWindow.OnName(sender: TWidget);
begin
  if Length(FNames) = 0 then exit;
  FNameI := (FNameI + 1) mod Length(FNames);
  Refresh;
end;

procedure TCharCreateWindow.OnBegin(sender: TWidget);
var
  nm: String;
begin
  if (Length(FNames) > 0) and (FNameI >= 0) and (FNameI < Length(FNames)) then
    nm := FNames[FNameI]
  else
    nm := 'Vagrant';
  if Assigned(OnDone) then OnDone(FSp, FCl, nm);
end;

procedure TCharCreateWindow.PickSpecies(index: LongInt);
begin
  if (index >= 0) and (index < Length(FSpNames)) then FSp := index;
  Refresh;
end;

procedure TCharCreateWindow.PickClass(index: LongInt);
begin
  if (index >= 0) and (index < Length(FClIdx)) then FCl := FClIdx[index];
  Refresh;
end;

end.
