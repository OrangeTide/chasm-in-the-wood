program chasm;

{** Third-person voxel dungeon.

  Opens an SDL3 window with an OpenGL 3.3 core context, generates a dungeon, builds
  it as a chunked voxel world, and draws the frustum-visible chunks with a player
  voxel model on top. Move the player a tile at a time with WASD or the arrow keys
  (walls block); the diorama camera follows. Q/E orbit, -/= zoom, Escape quits.

  Args: [model.vox] [screenshot.ppm] [seed]. A screenshot path renders one frame
  and exits. The player model defaults to content/models/character.vox. }

{$mode objfpc}{$H+}

uses
  ctypes, sysutils, classes, math,
  sdl3, glcore, vecmath, camera,
  voxfile, voxmesh, gpumesh, meshshader,
  rng, tilemap, worldgen, world, player;

const
  WIN_W = 960;
  WIN_H = 720;
  MAP_W = 48;
  MAP_H = 48;
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
  map: TTileMap;
  wd: TWorld;
  pl: TPlayer;
  lightDir, desired: TVec3;
  voxPath, shotPath: string;
  seed: qword;
  sc: cuint32;
  running: boolean;
  maxDim, drawn: longint;
  scale: single;

procedure Die(const msg: string);
begin
  writeln(StdErr, 'chasm: ', msg, ': ', SDL_GetError);
  halt(1);
end;

function TileWorld(cx, cy: longint): TVec3;
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

procedure SaveShot(const path: string);
var
  pix: array of byte;
  y, stride: longint;
  fs: TFileStream;
  hdr: string;
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

begin
  if ParamCount >= 1 then voxPath := ParamStr(1)
  else voxPath := 'content/models/character.vox';
  if ParamCount >= 2 then shotPath := ParamStr(2) else shotPath := '';
  if ParamCount >= 3 then seed := qword(StrToInt64Def(ParamStr(3), 1337))
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

  { Generate and build the world. }
  GenerateDungeon(map, MAP_W, MAP_H, seed);
  WorldInit(wd);
  WorldBuildFromTileMap(wd, map);
  WorldRemesh(wd);
  writeln('dungeon seed ', seed, ', spawn tile (', map.spawnX, ',', map.spawnY,
          '), ', wd.nchunks, ' chunks');

  PlayerInit(pl, map);

  CameraInitDiorama(cam, WIN_W / WIN_H);
  cam.distance := 11.0;
  cam.pitch := 34 * pi / 180;
  cam.target := TileWorld(pl.cx, pl.cy);
  cam.target.y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;

  lightDir := Vec3Normalize(Vec3(0.4, 1.0, 0.55));

  running := true;
  while running do begin
    while SDL_PollEvent(@ev) do begin
      if ev.etype = SDL_EVENT_QUIT then running := false
      else if ev.etype = SDL_EVENT_KEY_DOWN then begin
        sc := ev.key.scancode;
        case sc of
          SDL_SCANCODE_ESCAPE: running := false;
          SDL_SCANCODE_W, SDL_SCANCODE_UP:    PlayerMove(pl, 0, -1, map);
          SDL_SCANCODE_S, SDL_SCANCODE_DOWN:  PlayerMove(pl, 0, 1, map);
          SDL_SCANCODE_A, SDL_SCANCODE_LEFT:  PlayerMove(pl, -1, 0, map);
          SDL_SCANCODE_D, SDL_SCANCODE_RIGHT: PlayerMove(pl, 1, 0, map);
          SDL_SCANCODE_Q: cam.yaw := cam.yaw - 0.1;
          SDL_SCANCODE_E: cam.yaw := cam.yaw + 0.1;
          SDL_SCANCODE_MINUS:  cam.distance := Min(24.0, cam.distance * 1.1);
          SDL_SCANCODE_EQUALS: cam.distance := Max(5.0, cam.distance * 0.9);
        end;
      end;
    end;

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

    if shotPath <> '' then begin
      writeln('drew ', drawn, ' chunks');
      SaveShot(shotPath);
      running := false;
    end;

    SDL_GL_SwapWindow(win);
  end;

  WorldFree(wd);
  GpuMeshFree(playerGpu);
  MeshShaderFree(shader);
  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(win);
  SDL_Quit;
end.
