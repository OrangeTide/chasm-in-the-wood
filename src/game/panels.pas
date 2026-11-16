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
  end;

  { ---- character sheet: fixed fields plus a scrolling skill list ---- }
  TCharacterSheet = class(TWindow)
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
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

{ Fill the inventory and the equipment doll with placeholder items. }
procedure PlacePlaceholders(inv: TInventoryWindow; eq: TEquipmentWindow);

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
begin
  inherited Create(AParent, 'CHARACTER', [wfClose, wfDrag], l, t, 240, 260);
  TLabel.Create(Content, 'NAME  VAGRANT', 8, 8);
  TLabel.Create(Content, 'CLASS  WANDERER', 8, 24);
  TLabel.Create(Content, 'SPECIES  HUMAN', 8, 40);
  TLabel.Create(Content, 'LEVEL 1   XP 0', 8, 56);
  TLabel.Create(Content, 'STR 10  DEX 13', 8, 80);
  TLabel.Create(Content, 'INT 9   WIL 11', 8, 96);
  TLabel.Create(Content, 'HP 18/18  MP 4/4', 8, 112);
  TLabel.Create(Content, 'SKILLS', 8, 134);
  sv := TScrollView.Create(Content, 8, 150, 216, 84);
  list := TWidget.Create(sv);
  y := 4;
  for i := 0 to High(skills) do begin
    TLabel.Create(list, skills[i], 6, y);
    y := y + 16;
  end;
  sv.SetContentSize(y + 4);
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

{ ---- placeholder content ---- }

procedure PlacePlaceholders(inv: TInventoryWindow; eq: TEquipmentWindow);
var
  g: TItemGrid;
begin
  g := inv.Page(0);
  g.SlotAt(0, 0).Item := TDragItem.Create('SWORD',  CAT_WEAPON, TColor($FFB04030), 'S');
  g.SlotAt(1, 0).Item := TDragItem.Create('SHIELD', CAT_SHIELD, TColor($FF808890), 'H');
  g.SlotAt(2, 0).Item := TDragItem.Create('HELM',   CAT_HELMET, TColor($FF6070A0), 'C');
  g.SlotAt(3, 0).Item := TDragItem.Create('POTION', CAT_POTION, TColor($FF40A050), 'P');
  g.SlotAt(0, 1).Item := TDragItem.Create('RING',   CAT_RING,   TColor($FFD0B040), 'O');
  g.SlotAt(1, 1).Item := TDragItem.Create('BOOTS',  CAT_BOOTS,  TColor($FF8A5A2A), 'B');
  g.SlotAt(2, 1).Item := TDragItem.Create('GOLD',   CAT_MISC,   TColor($FFE0C040), 'G');
  eq.Doll.Slot(bsMainHand).Item :=
    TDragItem.Create('DAGGER', CAT_WEAPON, TColor($FFA03020), 'D');
end;

end.
