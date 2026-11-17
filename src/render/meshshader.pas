unit meshshader;

{** The shader program that lit voxel meshes are drawn with.

  One directional light plus ambient, enough to read voxel faces as solid form.
  A frame binds the program once with the camera matrices and light direction,
  then draws many meshes, setting only the model matrix per object. The geometry
  lives in gpumesh; this unit owns just the program and its uniforms. }

{$mode objfpc}{$H+}

interface

uses
  glcore, vecmath;

type
  TMeshShader = record
    Prog: GLuint;
    UModel, UView, UProj, ULightDir, UTint: GLint;
    UFogColor, UFogStart, UFogEnd: GLint;
  end;

function MeshShaderInit(out s: TMeshShader): Boolean;
procedure MeshShaderBegin(const s: TMeshShader; const view, proj: TMat4;
  const lightDir: TVec3);
procedure MeshShaderModel(const s: TMeshShader; const model: TMat4);
{ Multiply the mesh's own colours by this tint; reset to white each MeshShaderBegin. }
procedure MeshShaderTint(const s: TMeshShader; r, g, b: Single);
{ Fade fragments toward fogColor by view-space distance, from startD (full colour) to
  endD (full fog). Reset to no fog each MeshShaderBegin. Set startD >= endD for none. }
procedure MeshShaderFog(const s: TMeshShader; r, g, b, startD, endD: Single);
procedure MeshShaderFree(var s: TMeshShader);

implementation

const
  VERT_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'layout(location=0) in vec3 aPos;'#10 +
    'layout(location=1) in vec3 aNormal;'#10 +
    'layout(location=2) in vec3 aColor;'#10 +
    'layout(location=3) in float aEmit;'#10 +
    'uniform mat4 uModel;'#10 +
    'uniform mat4 uView;'#10 +
    'uniform mat4 uProj;'#10 +
    'out vec3 vNormal;'#10 +
    'out vec3 vColor;'#10 +
    'out vec3 vViewPos;'#10 +
    'out float vEmit;'#10 +
    'void main() {'#10 +
    '  vec4 vp = uView * uModel * vec4(aPos, 1.0);'#10 +
    '  vViewPos = vp.xyz;'#10 +
    '  gl_Position = uProj * vp;'#10 +
    '  vNormal = mat3(uModel) * aNormal;'#10 +
    '  vColor = aColor;'#10 +
    '  vEmit = aEmit;'#10 +
    '}'#10;

  FRAG_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'in vec3 vNormal;'#10 +
    'in vec3 vColor;'#10 +
    'in vec3 vViewPos;'#10 +
    'in float vEmit;'#10 +
    'uniform vec3 uLightDir;'#10 +
    'uniform vec3 uTint;'#10 +
    'uniform vec3 uFogColor;'#10 +
    'uniform float uFogStart;'#10 +
    'uniform float uFogEnd;'#10 +
    'out vec4 FragColor;'#10 +
    'void main() {'#10 +
    '  vec3 N = normalize(vNormal);'#10 +
    '  float d = max(dot(N, normalize(uLightDir)), 0.0);'#10 +
    '  float shade = 0.25 + 0.75 * d;'#10 +
    '  float e = clamp(vEmit, 0.0, 1.0);'#10 +
    // An emissive voxel lights itself: fade from the shaded colour to the full colour.
    '  vec3 base = vColor * uTint * mix(shade, 1.0, e);'#10 +
    '  float fog = 0.0;'#10 +
    '  if (uFogEnd > uFogStart)'#10 +
    '    fog = clamp((length(vViewPos) - uFogStart) /'#10 +
    '                (uFogEnd - uFogStart), 0.0, 1.0);'#10 +
    // A glow carries through the dark: emission thins the fog that would swallow it.
    '  fog *= 1.0 - 0.85 * e;'#10 +
    '  FragColor = vec4(mix(base, uFogColor, fog), 1.0);'#10 +
    '}'#10;

function CompileShader(kind: GLenum; const src: PAnsiChar): GLuint;
var
  sh: GLuint;
  ok, logLen: GLint;
  logBuf: array[0..1023] of AnsiChar;
begin
  sh := glCreateShader(kind);
  glShaderSource(sh, 1, @src, nil);
  glCompileShader(sh);
  glGetShaderiv(sh, GL_COMPILE_STATUS, @ok);
  if ok = GL_FALSE then begin
    glGetShaderInfoLog(sh, SizeOf(logBuf), @logLen, @logBuf[0]);
    writeln(StdErr, 'meshshader: compile failed: ', PAnsiChar(@logBuf[0]));
    glDeleteShader(sh);
    CompileShader := 0;
    exit;
  end;
  CompileShader := sh;
end;

function MeshShaderInit(out s: TMeshShader): Boolean;
var
  vs, fs: GLuint;
  ok, logLen: GLint;
  logBuf: array[0..1023] of AnsiChar;
begin
  MeshShaderInit := False;
  FillChar(s, SizeOf(s), 0);

  vs := CompileShader(GL_VERTEX_SHADER, VERT_SRC);
  if vs = 0 then exit;
  fs := CompileShader(GL_FRAGMENT_SHADER, FRAG_SRC);
  if fs = 0 then begin glDeleteShader(vs); exit; end;

  s.Prog := glCreateProgram();
  glAttachShader(s.Prog, vs);
  glAttachShader(s.Prog, fs);
  glLinkProgram(s.Prog);
  glDeleteShader(vs);
  glDeleteShader(fs);

  glGetProgramiv(s.Prog, GL_LINK_STATUS, @ok);
  if ok = GL_FALSE then begin
    glGetProgramInfoLog(s.Prog, SizeOf(logBuf), @logLen, @logBuf[0]);
    writeln(StdErr, 'meshshader: link failed: ', PAnsiChar(@logBuf[0]));
    glDeleteProgram(s.Prog);
    s.Prog := 0;
    exit;
  end;

  s.UModel    := glGetUniformLocation(s.Prog, 'uModel');
  s.UView     := glGetUniformLocation(s.Prog, 'uView');
  s.UProj     := glGetUniformLocation(s.Prog, 'uProj');
  s.ULightDir := glGetUniformLocation(s.Prog, 'uLightDir');
  s.UTint     := glGetUniformLocation(s.Prog, 'uTint');
  s.UFogColor := glGetUniformLocation(s.Prog, 'uFogColor');
  s.UFogStart := glGetUniformLocation(s.Prog, 'uFogStart');
  s.UFogEnd   := glGetUniformLocation(s.Prog, 'uFogEnd');
  MeshShaderInit := True;
end;

procedure MeshShaderBegin(const s: TMeshShader; const view, proj: TMat4;
  const lightDir: TVec3);
begin
  glUseProgram(s.Prog);
  glUniformMatrix4fv(s.UView, 1, GL_FALSE, @view[0]);
  glUniformMatrix4fv(s.UProj, 1, GL_FALSE, @proj[0]);
  glUniform3f(s.ULightDir, lightDir.X, lightDir.Y, lightDir.Z);
  glUniform3f(s.UTint, 1.0, 1.0, 1.0);
  { No fog until a frame asks for it: a zero-width band disables the mix. }
  glUniform3f(s.UFogColor, 0.0, 0.0, 0.0);
  glUniform1f(s.UFogStart, 0.0);
  glUniform1f(s.UFogEnd, 0.0);
end;

procedure MeshShaderModel(const s: TMeshShader; const model: TMat4);
begin
  glUniformMatrix4fv(s.UModel, 1, GL_FALSE, @model[0]);
end;

procedure MeshShaderTint(const s: TMeshShader; r, g, b: Single);
begin
  glUniform3f(s.UTint, r, g, b);
end;

procedure MeshShaderFog(const s: TMeshShader; r, g, b, startD, endD: Single);
begin
  glUniform3f(s.UFogColor, r, g, b);
  glUniform1f(s.UFogStart, startD);
  glUniform1f(s.UFogEnd, endD);
end;

procedure MeshShaderFree(var s: TMeshShader);
begin
  if s.Prog <> 0 then glDeleteProgram(s.Prog);
  FillChar(s, SizeOf(s), 0);
end;

end.
