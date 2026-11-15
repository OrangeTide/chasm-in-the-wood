program chasm;

{** Third-person voxel scene.

  Opens an SDL3 window with an OpenGL 3.3 core context and draws a grid floor with
  a player voxel model on it. Move the player a cell at a time with WASD or the
  arrow keys; the diorama camera follows by easing its target toward the player.
  Q and E orbit the view, - and = zoom, Escape quits. A second argument renders one
  frame to that PPM path and exits, for a headless render check.

  The player model is content/models/character.vox by default. }

{$mode objfpc}{$H+}

uses
  ctypes, sysutils, classes, math,
  sdl3, glcore, vecmath, camera,
  voxfile, voxmesh, gpumesh, meshshader,
  grid, player;

const
  WIN_W = 960;
  WIN_H = 720;
  GRID_W = 16;
  GRID_H = 16;
  PLAYER_HEIGHT = 1.6;   { world units, feet on the floor }
  FOLLOW = 0.15;         { camera target easing per frame }

var
  window: PSDL_Window;
  glctx: TSDL_GLContext;
  ev: TSDL_Event;
  shader: TMeshShader;
  playerMesh, floorMesh: TVoxMesh;
  playerGpu, floorGpu: TGpuMesh;
  playerModel: TVoxModel;
  playerBase, floorModel: TMat4;
  cam: TCamera;
  g: TGrid;
  pl: TPlayer;
  lightDir, desired: TVec3;
  voxPath, shotPath: string;
  sc: cuint32;
  running: boolean;

procedure Die(const msg: string);
begin
  writeln(StdErr, 'chasm: ', msg, ': ', SDL_GetError);
  halt(1);
end;

procedure SaveShot(const path: string);
{ Read the back buffer and write it as a binary PPM, rows flipped to top-down. }
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

function PlayerModelMatrix: TMat4;
{ Place the centred, floor-standing base at the player's current cell. }
var
  c: TVec3;
begin
  c := GridCellCenter(g, pl.cx, pl.cy);
  PlayerModelMatrix := Mat4Multiply(Mat4Translate(c.x, 0, c.z), playerBase);
end;

var
  maxDim: longint;
  scale: single;
begin
  if ParamCount >= 1 then voxPath := ParamStr(1)
  else voxPath := 'content/models/character.vox';
  if ParamCount >= 2 then shotPath := ParamStr(2) else shotPath := '';

  if not SDL_Init(SDL_INIT_VIDEO) then Die('SDL_Init failed');

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

  window := SDL_CreateWindow('Chasm in the Wood', WIN_W, WIN_H, SDL_WINDOW_OPENGL);
  if window = nil then Die('SDL_CreateWindow failed');

  glctx := SDL_GL_CreateContext(window);
  if glctx = nil then Die('SDL_GL_CreateContext failed');
  SDL_GL_MakeCurrent(window, glctx);
  SDL_GL_SetSwapInterval(1);

  if not LoadGL(TGLGetProcAddr(@SDL_GL_GetProcAddress)) then begin
    writeln(StdErr, 'chasm: could not load OpenGL entry points');
    halt(1);
  end;
  writeln('GL renderer: ', glGetString(GL_RENDERER));
  writeln('GL version:  ', glGetString(GL_VERSION));

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

  { Player mesh, scaled to stand PLAYER_HEIGHT tall with feet at y=0. }
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

  { Floor mesh. }
  GridInit(g, GRID_W, GRID_H);
  GridBuildFloor(g, floorMesh);
  GpuMeshUpload(floorGpu, floorMesh);
  floorModel := Mat4Identity;

  PlayerInit(pl, g);

  CameraInitDiorama(cam, WIN_W / WIN_H);
  cam.distance := 9.0;
  cam.pitch := 32 * pi / 180;
  cam.target := GridCellCenter(g, pl.cx, pl.cy);
  cam.target.y := PLAYER_HEIGHT / 2;

  lightDir := Vec3Normalize(Vec3(0.4, 1.0, 0.6));

  running := true;
  while running do begin
    while SDL_PollEvent(@ev) do begin
      if ev.etype = SDL_EVENT_QUIT then running := false
      else if ev.etype = SDL_EVENT_KEY_DOWN then begin
        sc := ev.key.scancode;
        case sc of
          SDL_SCANCODE_ESCAPE: running := false;
          SDL_SCANCODE_W, SDL_SCANCODE_UP:    PlayerMove(pl, 0, -1, g);
          SDL_SCANCODE_S, SDL_SCANCODE_DOWN:  PlayerMove(pl, 0, 1, g);
          SDL_SCANCODE_A, SDL_SCANCODE_LEFT:  PlayerMove(pl, -1, 0, g);
          SDL_SCANCODE_D, SDL_SCANCODE_RIGHT: PlayerMove(pl, 1, 0, g);
          SDL_SCANCODE_Q: cam.yaw := cam.yaw - 0.1;
          SDL_SCANCODE_E: cam.yaw := cam.yaw + 0.1;
          SDL_SCANCODE_MINUS:  cam.distance := Min(20.0, cam.distance * 1.1);
          SDL_SCANCODE_EQUALS: cam.distance := Max(4.0, cam.distance * 0.9);
        end;
      end;
    end;

    { Ease the camera target toward the player cell. }
    desired := GridCellCenter(g, pl.cx, pl.cy);
    cam.target.x := cam.target.x + (desired.x - cam.target.x) * FOLLOW;
    cam.target.z := cam.target.z + (desired.z - cam.target.z) * FOLLOW;
    cam.target.y := PLAYER_HEIGHT / 2;

    glViewport(0, 0, WIN_W, WIN_H);
    glClearColor(0.08, 0.09, 0.12, 1.0);
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

    MeshShaderBegin(shader, CameraView(cam), CameraProj(cam), lightDir);
    MeshShaderModel(shader, floorModel);
    GpuMeshDraw(floorGpu);
    MeshShaderModel(shader, PlayerModelMatrix);
    GpuMeshDraw(playerGpu);

    if shotPath <> '' then begin
      SaveShot(shotPath);
      running := false;
    end;

    SDL_GL_SwapWindow(window);
  end;

  GpuMeshFree(playerGpu);
  GpuMeshFree(floorGpu);
  MeshShaderFree(shader);
  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(window);
  SDL_Quit;
end.
