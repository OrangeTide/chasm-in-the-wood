program chasm;

{** Third-person voxel dungeon.

  Opens an SDL3 window with an OpenGL 3.3 core context, generates a dungeon, builds
  it as a chunked voxel world, and draws the frustum-visible chunks with a player
  voxel model on top. Move the player a tile at a time with WASD or the arrow keys
  (walls block); the diorama camera follows. Return takes the stairs under the player
  down or up a dungeon depth. Q/E orbit, -/= zoom, Escape quits.

  Args: [model.vox] [screenshot.ppm] [seed]. A screenshot path renders one frame
  and exits. The player model defaults to content/models/character.vox. }

{$mode objfpc}{$H+}

uses
  ctypes, sysutils, classes, math,
  sdl3, glcore, vecmath, camera,
  voxfile, voxmesh, gpumesh, meshshader,
  tilemap, tileworld, themes, worldgraph, world, player, gameui,
  content, entities, critters;

const
  WIN_W = 960;
  WIN_H = 720;
  PLAYER_HEIGHT = 1.6;
  FOLLOW = 0.15;
  ENTITY_RADIUS = 1;        { regions around the player that hold live entities }
  { Drawn height per monster bulk, indexed by TSizeClass. }
  SIZE_H: array[TSizeClass] of Single = (0.8, 1.0, 1.3, 1.9, 2.7, 3.6);

var
  win: PSDL_Window;
  glctx: TSDL_GLContext;
  ev: TSDL_Event;
  shader: TMeshShader;
  playerMesh: TVoxMesh;
  playerGpu: TGpuMesh;
  playerModel: TVoxModel;
  playerBase: TMat4;
  creatureMesh, propMesh: TVoxMesh;
  creatureGpu, propGpu: TGpuMesh;
  creatureModel, propModel: TVoxModel;
  creatureBase: array[TSizeClass] of TMat4;
  propBase: TMat4;
  gContent: TContent;
  entSet: TEntitySet;
  lastRx, lastRy: LongInt;
  cam: TCamera;
  tw: TTileWorld;
  wd: TWorld;
  pl: TPlayer;
  lightDir, desired: TVec3;
  voxPath, shotPath: String;
  seed, worldSeed: QWord;
  depth: LongInt;
  twInit: Boolean;
  sc: cuint32;
  running: Boolean;
  maxDim, drawn: LongInt;
  scale: Single;
  mx, my, wy: LongInt;
  sz: TSizeClass;
  ei: LongInt;

type
  TArrive = (arSpawn, arUp, arDown);

procedure Die(const msg: String);
begin
  writeln(StdErr, 'chasm: ', msg, ': ', SDL_GetError);
  halt(1);
end;

function FloorDivTile(t: LongInt): LongInt;
{ The region coordinate holding tile t, flooring toward negative. }
begin
  if t >= 0 then FloorDivTile := t div REGION
  else FloorDivTile := -(((-t) + REGION - 1) div REGION);
end;

function TileWorld(cx, cy: LongInt): TVec3;
begin
  TileWorld := Vec3((cx + 0.5) * TILE, FLOOR_TOP_Y, (cy + 0.5) * TILE);
end;

function PlayerModelMatrix: TMat4;
var
  c: TVec3;
begin
  c := TileWorld(pl.Cx, pl.Cy);
  PlayerModelMatrix := Mat4Multiply(Mat4Translate(c.X, FLOOR_TOP_Y, c.Z), playerBase);
end;

function ModelBase(const m: TVoxModel; targetH: Single): TMat4;
{ Stand a z-up voxel model targetH tall with its feet at y=0, centred on x and z. }
var
  md: LongInt;
  sc: Single;
begin
  md := m.Sz;
  if md < 1 then md := 1;
  sc := targetH / md;
  ModelBase := Mat4Multiply(
    Mat4Multiply(Mat4Translate(0, targetH / 2, 0), Mat4Scale(sc)),
    Mat4Multiply(Mat4RotateX(-pi / 2),
      Mat4Translate(-m.Sx / 2.0, -m.Sy / 2.0, -m.Sz / 2.0)));
end;

procedure RebuildEntities;
{ Repopulate the entity set for the player's current region neighbourhood. }
begin
  lastRx := FloorDivTile(pl.Cx);
  lastRy := FloorDivTile(pl.Cy);
  EntitiesBuild(entSet, gContent, tw, lastRx, lastRy, ENTITY_RADIUS, pl.Cx, pl.Cy);
end;

procedure SaveShot(const path: String);
var
  pix: array of Byte;
  y, stride: LongInt;
  fs: TFileStream;
  hdr: String;
begin
  stride := WIN_W * 3;
  SetLength(pix, stride * WIN_H);
  glReadPixels(0, 0, WIN_W, WIN_H, GL_RGB, GL_UNSIGNED_BYTE, @pix[0]);
  fs := TFileStream.Create(path, fmCreate);
  try
    hdr := 'P6'#10 + IntToStr(WIN_W) + ' ' + IntToStr(WIN_H) + #10 + '255'#10;
    fs.WriteBuffer(hdr[1], length(hdr));
    for y := WIN_H - 1 downto 0 do
      fs.WriteBuffer(pix[y * stride], stride);
  finally
    fs.Free;
  end;
  writeln('wrote ', path);
end;

procedure SnapCamera;
begin
  cam.Target := TileWorld(pl.Cx, pl.Cy);
  cam.Target.Y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;
end;

procedure EnterDepth(d: LongInt; arrive: TArrive; trx, try_: LongInt);
{ Switch to dungeon depth d, place the player at the chosen entry, and rebuild the
  voxel world from the new depth's tiles. Stair arrivals land in region (trx, try_),
  on the stair that matches the one just used; if none is there, fall back to spawn. }
var
  px, py: LongInt;
  ok: Boolean;
begin
  if twInit then TileWorldFree(tw);
  TileWorldInit(tw, worldSeed, d);
  twInit := True;
  case arrive of
    arUp:   ok := TileWorldRegionUpStair(tw, trx, try_, px, py);
    arDown: ok := TileWorldRegionDownStair(tw, trx, try_, px, py);
  else      ok := False;
  end;
  if not ok then TileWorldSpawn(tw, px, py);
  PlayerInit(pl, px, py);
  depth := d;
  WorldFree(wd);
  WorldSetSources(wd, @tw);
  WorldStream(wd, pl.Cx, pl.Cy);
  SnapCamera;
  RebuildEntities;
  writeln('depth ', d, ', spawn (', px, ',', py, '), ',
          ThemeTable[TileWorldThemeAt(tw, px, py)].Name, ' zone, ',
          TileWorldRegionCount(tw), ' regions, ', WorldResidentCount(wd),
          ' chunks resident, ', entSet.Monsters, ' foes');
end;

procedure ReportStitch;
{ Confirm the stitched world graph links zones: report how many portals the spawn room
  is from a room one zone to the right. }
var
  a, b: TRoomRef;
  tx, ty, d: LongInt;
  haveB: Boolean;
begin
  if not TileWorldRoomAt(tw, pl.Cx, pl.Cy, a) then exit;
  haveB := False;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do
      if (not haveB) and TileWorldRoomAt(tw, ZONE_REGIONS * REGION + tx, ty, b) then
        haveB := True;
  if not haveB then exit;
  d := WorldGraphDistance(tw, a, b, 8000);
  if d >= 0 then
    writeln('zones stitched: spawn reaches zone (1,0) in ', d, ' portals')
  else
    writeln('zones not connected to zone (1,0)');
end;

procedure UpdateStatus;
{ Push the live game state into the HUD panel. }
var
  th: LongInt;
begin
  th := TileWorldThemeAt(tw, pl.Cx, pl.Cy);
  GameUISetStatus([
    'DEPTH ' + IntToStr(depth),
    'ZONE ' + ThemeTable[th].Name,
    'SEED ' + IntToStr(Int64(worldSeed)),
    'TILE ' + IntToStr(pl.Cx) + ' ' + IntToStr(pl.Cy),
    'RES ' + IntToStr(TileWorldRegionCount(tw)) + ' ' +
             IntToStr(WorldResidentCount(wd)),
    'FOES ' + IntToStr(entSet.Monsters) + ' LOOT ' + IntToStr(entSet.Props)
  ]);
end;

procedure UseStairs;
{ Take the stairs under the player, if any. The descent or ascent lands in the same
  region on the next depth, so the stairs there line up with the one just used. }
var
  t: Byte;
  rx, ry: LongInt;
begin
  t := TileAt(tw, pl.Cx, pl.Cy);
  rx := FloorDivTile(pl.Cx);
  ry := FloorDivTile(pl.Cy);
  if t = TILE_STAIRS_DOWN then EnterDepth(depth + 1, arUp, rx, ry)
  else if (t = TILE_STAIRS_UP) and (depth > 0) then EnterDepth(depth - 1, arDown, rx, ry);
end;

begin
  if ParamCount >= 1 then voxPath := ParamStr(1)
  else voxPath := 'content/models/character.vox';
  if ParamCount >= 2 then shotPath := ParamStr(2) else shotPath := '';
  if ParamCount >= 3 then seed := QWord(StrToInt64Def(ParamStr(3), 1337))
  else seed := 1337;

  if not SDL_Init(SDL_INIT_VIDEO) then Die('SDL_Init failed');

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

  win := SDL_CreateWindow('Chasm in the Wood', WIN_W, WIN_H, SDL_WINDOW_OPENGL);
  if win = nil then Die('SDL_CreateWindow failed');
  glctx := SDL_GL_CreateContext(win);
  if glctx = nil then Die('SDL_GL_CreateContext failed');
  SDL_GL_MakeCurrent(win, glctx);
  SDL_GL_SetSwapInterval(1);

  if not LoadGL(TGLGetProcAddr(@SDL_GL_GetProcAddress)) then begin
    writeln(StdErr, 'chasm: could not load OpenGL entry points');
    halt(1);
  end;
  writeln('GL renderer: ', glGetString(GL_RENDERER));

  if not VoxLoad(voxPath, playerModel) then begin
    writeln(StdErr, 'chasm: failed to load ', voxPath);
    halt(1);
  end;

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LESS);
  glEnable(GL_CULL_FACE);
  glCullFace(GL_BACK);
  glFrontFace(GL_CCW);

  if not MeshShaderInit(shader) then begin
    writeln(StdErr, 'chasm: shader init failed');
    halt(1);
  end;

  { Player mesh and its base transform: stand PLAYER_HEIGHT tall, feet at y=0. }
  BuildMesh(playerModel, playerMesh);
  GpuMeshUpload(playerGpu, playerMesh);
  maxDim := playerModel.Sz;
  if maxDim < 1 then maxDim := 1;
  scale := PLAYER_HEIGHT / maxDim;
  playerBase := Mat4Multiply(
    Mat4Multiply(Mat4Translate(0, PLAYER_HEIGHT / 2, 0), Mat4Scale(scale)),
    Mat4Multiply(Mat4RotateX(-pi / 2),
      Mat4Translate(-playerModel.Sx / 2.0, -playerModel.Sy / 2.0,
                    -playerModel.Sz / 2.0)));

  { Content tables, and the placeholder voxel models for their inhabitants. }
  if not ContentLoad('content', gContent) then
    writeln(StdErr, 'chasm: warning: some content tables failed to load');
  writeln('content: ', Length(gContent.Monsters), ' monsters, ',
          Length(gContent.Items), ' items, ', Length(gContent.Species),
          ' species, ', Length(gContent.Classes), ' classes');
  BuildCreatureModel(creatureModel);
  BuildMesh(creatureModel, creatureMesh);
  GpuMeshUpload(creatureGpu, creatureMesh);
  for sz := Low(TSizeClass) to High(TSizeClass) do
    creatureBase[sz] := ModelBase(creatureModel, SIZE_H[sz]);
  BuildPropModel(propModel);
  BuildMesh(propModel, propMesh);
  GpuMeshUpload(propGpu, propMesh);
  propBase := ModelBase(propModel, 0.35);

  { Camera, then the first depth. EnterDepth builds the world from the depth's tiles
    and snaps the camera onto the spawn. }
  CameraInitDiorama(cam, WIN_W / WIN_H);
  cam.Distance := 11.0;
  cam.Pitch := 34 * pi / 180;
  WorldInit(wd);
  worldSeed := seed;
  twInit := False;
  writeln('world seed ', seed);
  EnterDepth(0, arSpawn, 0, 0);
  ReportStitch;
  GameUIInit(WIN_W, WIN_H);

  lightDir := Vec3Normalize(Vec3(0.4, 1.0, 0.55));

  running := True;
  while running do begin
    while SDL_PollEvent(@ev) do begin
      if ev.Etype = SDL_EVENT_QUIT then running := False
      else if ev.Etype = SDL_EVENT_KEY_DOWN then begin
        sc := ev.Key.Scancode;
        case sc of
          SDL_SCANCODE_ESCAPE: running := False;
          SDL_SCANCODE_RETURN: UseStairs;
          SDL_SCANCODE_W, SDL_SCANCODE_UP:    PlayerMove(pl, 0, -1, tw);
          SDL_SCANCODE_S, SDL_SCANCODE_DOWN:  PlayerMove(pl, 0, 1, tw);
          SDL_SCANCODE_A, SDL_SCANCODE_LEFT:  PlayerMove(pl, -1, 0, tw);
          SDL_SCANCODE_D, SDL_SCANCODE_RIGHT: PlayerMove(pl, 1, 0, tw);
          SDL_SCANCODE_Q: cam.Yaw := cam.Yaw - 0.1;
          SDL_SCANCODE_E: cam.Yaw := cam.Yaw + 0.1;
          SDL_SCANCODE_MINUS:  cam.Distance := Min(24.0, cam.Distance * 1.1);
          SDL_SCANCODE_EQUALS: cam.Distance := Max(5.0, cam.Distance * 0.9);
          SDL_SCANCODE_I: GameUITogglePanel(0);
          SDL_SCANCODE_C: GameUITogglePanel(1);
          SDL_SCANCODE_O: GameUITogglePanel(2);
        end;
      end
      else if ev.Etype = SDL_EVENT_MOUSE_BUTTON_DOWN then begin
        mx := round(ev.Button.X); my := round(ev.Button.Y);
        GameUIMouse(0, mx, my, ev.Button.Button - 1, 0);
      end
      else if ev.Etype = SDL_EVENT_MOUSE_BUTTON_UP then begin
        mx := round(ev.Button.X); my := round(ev.Button.Y);
        GameUIMouse(1, mx, my, ev.Button.Button - 1, 0);
      end
      else if ev.Etype = SDL_EVENT_MOUSE_MOTION then begin
        mx := round(ev.Motion.X); my := round(ev.Motion.Y);
        GameUIMouse(2, mx, my, 0, 0);
      end
      else if ev.Etype = SDL_EVENT_MOUSE_WHEEL then begin
        wy := round(ev.Wheel.Y);
        GameUIMouse(3, mx, my, 0, wy);
      end;
    end;

    { Stream chunks for the player's new neighbourhood. }
    WorldStream(wd, pl.Cx, pl.Cy);

    { Repopulate entities when the player crosses into a new region. }
    if (FloorDivTile(pl.Cx) <> lastRx) or (FloorDivTile(pl.Cy) <> lastRy) then
      RebuildEntities;

    desired := TileWorld(pl.Cx, pl.Cy);
    cam.Target.X := cam.Target.X + (desired.X - cam.Target.X) * FOLLOW;
    cam.Target.Z := cam.Target.Z + (desired.Z - cam.Target.Z) * FOLLOW;
    cam.Target.Y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;

    glViewport(0, 0, WIN_W, WIN_H);
    glClearColor(0.05, 0.05, 0.07, 1.0);
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

    MeshShaderBegin(shader, CameraView(cam), CameraProj(cam), lightDir);
    drawn := WorldRender(wd, shader, Mat4Multiply(CameraProj(cam), CameraView(cam)));
    MeshShaderModel(shader, PlayerModelMatrix);
    GpuMeshDraw(playerGpu);

    { Monsters and props: tinted placeholder voxel models, one draw each. }
    for ei := 0 to entSet.Count - 1 do begin
      desired := TileWorld(entSet.List[ei].Cx, entSet.List[ei].Cy);
      MeshShaderTint(shader, entSet.List[ei].R, entSet.List[ei].G,
                     entSet.List[ei].B);
      if entSet.List[ei].Kind = enMonster then begin
        MeshShaderModel(shader, Mat4Multiply(
          Mat4Translate(desired.X, FLOOR_TOP_Y, desired.Z),
          creatureBase[entSet.List[ei].Size]));
        GpuMeshDraw(creatureGpu);
      end else begin
        MeshShaderModel(shader, Mat4Multiply(
          Mat4Translate(desired.X, FLOOR_TOP_Y, desired.Z), propBase));
        GpuMeshDraw(propGpu);
      end;
    end;
    MeshShaderTint(shader, 1.0, 1.0, 1.0);

    { Interface overlay: live status window over the diorama. }
    UpdateStatus;
    GameUIRender;

    if shotPath <> '' then begin
      writeln(TileWorldRegionCount(tw), ' regions, ', WorldResidentCount(wd),
              ' chunks resident, drew ', drawn);
      SaveShot(shotPath);
      running := False;
    end;

    SDL_GL_SwapWindow(win);
  end;

  GameUIFree;
  WorldFree(wd);
  TileWorldFree(tw);
  GpuMeshFree(playerGpu);
  MeshShaderFree(shader);
  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(win);
  SDL_Quit;
end.
