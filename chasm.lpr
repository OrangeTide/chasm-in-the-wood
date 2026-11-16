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
  tilemap, tileworld, themes, worldgraph, world, player, gameui;

const
  WIN_W = 960;
  WIN_H = 720;
  PLAYER_HEIGHT = 1.6;
  FOLLOW = 0.15;

var
  win: PSDL_Window;
  glctx: TSDL_GLContext;
  ev: TSDL_Event;
  shader: TMeshShader;
  playerMesh: TVoxMesh;
  playerGpu: TGpuMesh;
  playerModel: TVoxModel;
  playerBase: TMat4;
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
  c := TileWorld(pl.cx, pl.cy);
  PlayerModelMatrix := Mat4Multiply(Mat4Translate(c.x, FLOOR_TOP_Y, c.z), playerBase);
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
  cam.target := TileWorld(pl.cx, pl.cy);
  cam.target.y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;
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
  WorldStream(wd, pl.cx, pl.cy);
  SnapCamera;
  writeln('depth ', d, ', spawn (', px, ',', py, '), ',
          ThemeTable[TileWorldThemeAt(tw, px, py)].name, ' zone, ',
          TileWorldRegionCount(tw), ' regions, ', WorldResidentCount(wd),
          ' chunks resident');
end;

procedure ReportStitch;
{ Confirm the stitched world graph links zones: report how many portals the spawn room
  is from a room one zone to the right. }
var
  a, b: TRoomRef;
  tx, ty, d: LongInt;
  haveB: Boolean;
begin
  if not TileWorldRoomAt(tw, pl.cx, pl.cy, a) then exit;
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
  th := TileWorldThemeAt(tw, pl.cx, pl.cy);
  GameUISetStatus([
    'DEPTH ' + IntToStr(depth),
    'ZONE ' + ThemeTable[th].name,
    'SEED ' + IntToStr(Int64(worldSeed)),
    'TILE ' + IntToStr(pl.cx) + ' ' + IntToStr(pl.cy),
    'REGIONS ' + IntToStr(TileWorldRegionCount(tw)),
    'CHUNKS ' + IntToStr(WorldResidentCount(wd))
  ]);
end;

procedure UseStairs;
{ Take the stairs under the player, if any. The descent or ascent lands in the same
  region on the next depth, so the stairs there line up with the one just used. }
var
  t: Byte;
  rx, ry: LongInt;
begin
  t := TileAt(tw, pl.cx, pl.cy);
  rx := FloorDivTile(pl.cx);
  ry := FloorDivTile(pl.cy);
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
  maxDim := playerModel.sz;
  if maxDim < 1 then maxDim := 1;
  scale := PLAYER_HEIGHT / maxDim;
  playerBase := Mat4Multiply(
    Mat4Multiply(Mat4Translate(0, PLAYER_HEIGHT / 2, 0), Mat4Scale(scale)),
    Mat4Multiply(Mat4RotateX(-pi / 2),
      Mat4Translate(-playerModel.sx / 2.0, -playerModel.sy / 2.0,
                    -playerModel.sz / 2.0)));

  { Camera, then the first depth. EnterDepth builds the world from the depth's tiles
    and snaps the camera onto the spawn. }
  CameraInitDiorama(cam, WIN_W / WIN_H);
  cam.distance := 11.0;
  cam.pitch := 34 * pi / 180;
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
      if ev.etype = SDL_EVENT_QUIT then running := False
      else if ev.etype = SDL_EVENT_KEY_DOWN then begin
        sc := ev.key.scancode;
        case sc of
          SDL_SCANCODE_ESCAPE: running := False;
          SDL_SCANCODE_RETURN: UseStairs;
          SDL_SCANCODE_W, SDL_SCANCODE_UP:    PlayerMove(pl, 0, -1, tw);
          SDL_SCANCODE_S, SDL_SCANCODE_DOWN:  PlayerMove(pl, 0, 1, tw);
          SDL_SCANCODE_A, SDL_SCANCODE_LEFT:  PlayerMove(pl, -1, 0, tw);
          SDL_SCANCODE_D, SDL_SCANCODE_RIGHT: PlayerMove(pl, 1, 0, tw);
          SDL_SCANCODE_Q: cam.yaw := cam.yaw - 0.1;
          SDL_SCANCODE_E: cam.yaw := cam.yaw + 0.1;
          SDL_SCANCODE_MINUS:  cam.distance := Min(24.0, cam.distance * 1.1);
          SDL_SCANCODE_EQUALS: cam.distance := Max(5.0, cam.distance * 0.9);
        end;
      end
      else if ev.etype = SDL_EVENT_MOUSE_BUTTON_DOWN then begin
        mx := round(ev.button.x); my := round(ev.button.y);
        GameUIMouse(0, mx, my, ev.button.button - 1, 0);
      end
      else if ev.etype = SDL_EVENT_MOUSE_BUTTON_UP then begin
        mx := round(ev.button.x); my := round(ev.button.y);
        GameUIMouse(1, mx, my, ev.button.button - 1, 0);
      end
      else if ev.etype = SDL_EVENT_MOUSE_MOTION then begin
        mx := round(ev.motion.x); my := round(ev.motion.y);
        GameUIMouse(2, mx, my, 0, 0);
      end
      else if ev.etype = SDL_EVENT_MOUSE_WHEEL then begin
        wy := round(ev.wheel.y);
        GameUIMouse(3, mx, my, 0, wy);
      end;
    end;

    { Stream chunks for the player's new neighbourhood. }
    WorldStream(wd, pl.cx, pl.cy);

    desired := TileWorld(pl.cx, pl.cy);
    cam.target.x := cam.target.x + (desired.x - cam.target.x) * FOLLOW;
    cam.target.z := cam.target.z + (desired.z - cam.target.z) * FOLLOW;
    cam.target.y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;

    glViewport(0, 0, WIN_W, WIN_H);
    glClearColor(0.05, 0.05, 0.07, 1.0);
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

    MeshShaderBegin(shader, CameraView(cam), CameraProj(cam), lightDir);
    drawn := WorldRender(wd, shader, Mat4Multiply(CameraProj(cam), CameraView(cam)));
    MeshShaderModel(shader, PlayerModelMatrix);
    GpuMeshDraw(playerGpu);

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
