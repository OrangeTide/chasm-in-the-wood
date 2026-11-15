program chasm;

{** Voxel renderer tech demo.

  Opens an SDL3 window with an OpenGL 3.3 core context, loads a MagicaVoxel model
  (content/models/character.vox by default, or a path given as the first argument),
  greedy-meshes it, and draws it under a fixed three-quarter diorama camera. This
  is the foundation for the third-person dungeon view; movement and a follow camera
  come later. Press Escape or close the window to quit. }

{$mode objfpc}{$H+}

uses
  ctypes, sysutils, classes,
  sdl3, glcore, vecmath, camera,
  voxfile, voxmesh, voxrender;

const
  WIN_W = 960;
  WIN_H = 720;

var
  window: PSDL_Window;
  glctx: TSDL_GLContext;
  ev: TSDL_Event;
  model: TVoxModel;
  mesh: TVoxMesh;
  renderer: TVoxRenderer;
  cam: TCamera;
  modelMat, rotMat, scaleMat: TMat4;
  lightDir: TVec3;
  voxPath, shotPath: string;
  maxDim: longint;
  scale: single;
  running: boolean;

procedure Die(const msg: string);
begin
  writeln(StdErr, 'chasm: ', msg, ': ', SDL_GetError);
  halt(1);
end;

procedure SaveShot(const path: string);
{ Read the back buffer and write it as a binary PPM, rows flipped to top-down.
  Doubles as a headless render check. }
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
  { Optional second arg: render one frame to this PPM path and exit. }
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

  writeln('GL vendor:   ', glGetString(GL_VENDOR));
  writeln('GL renderer: ', glGetString(GL_RENDERER));
  writeln('GL version:  ', glGetString(GL_VERSION));

  if not VoxLoad(voxPath, model) then begin
    writeln(StdErr, 'chasm: failed to load ', voxPath);
    halt(1);
  end;
  writeln('loaded ', voxPath, ': ', model.sx, 'x', model.sy, 'x', model.sz,
          ', ', VoxSolidCount(model), ' voxels');

  BuildMesh(model, mesh);
  writeln('meshed: ', mesh.nverts, ' vertices, ', mesh.nindices div 3, ' triangles');

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LESS);
  glEnable(GL_CULL_FACE);
  glCullFace(GL_BACK);
  glFrontFace(GL_CCW);

  if not VoxRendererInit(renderer, mesh) then begin
    writeln(StdErr, 'chasm: renderer init failed');
    halt(1);
  end;

  { Model transform: centre the voxel grid at the origin, stand its z-up data up
    into the y-up world, and scale the longest axis to two world units. }
  maxDim := model.sx;
  if model.sy > maxDim then maxDim := model.sy;
  if model.sz > maxDim then maxDim := model.sz;
  if maxDim < 1 then maxDim := 1;
  scale := 2.0 / maxDim;
  rotMat := Mat4RotateX(-pi / 2);
  scaleMat := Mat4Scale(scale);
  modelMat := Mat4Multiply(Mat4Multiply(scaleMat, rotMat),
                Mat4Translate(-model.sx / 2.0, -model.sy / 2.0, -model.sz / 2.0));

  CameraInitDiorama(cam, WIN_W / WIN_H);
  lightDir := Vec3Normalize(Vec3(0.4, 1.0, 0.6));

  running := true;
  while running do begin
    while SDL_PollEvent(@ev) do begin
      if ev.etype = SDL_EVENT_QUIT then running := false
      else if (ev.etype = SDL_EVENT_KEY_DOWN) and
              (ev.key.scancode = SDL_SCANCODE_ESCAPE) then running := false;
    end;

    glViewport(0, 0, WIN_W, WIN_H);
    glClearColor(0.08, 0.09, 0.12, 1.0);
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

    VoxRendererDraw(renderer, modelMat, CameraView(cam), CameraProj(cam), lightDir);

    if shotPath <> '' then begin
      SaveShot(shotPath);
      running := false;
    end;

    SDL_GL_SwapWindow(window);
  end;

  VoxRendererFree(renderer);
  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(window);
  SDL_Quit;
end.
