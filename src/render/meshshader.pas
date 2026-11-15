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
    prog: GLuint;
    uModel, uView, uProj, uLightDir: GLint;
  end;

function MeshShaderInit(out s: TMeshShader): boolean;
procedure MeshShaderBegin(const s: TMeshShader; const view, proj: TMat4;
  const lightDir: TVec3);
procedure MeshShaderModel(const s: TMeshShader; const model: TMat4);
procedure MeshShaderFree(var s: TMeshShader);

implementation

const
  VERT_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'layout(location=0) in vec3 aPos;'#10 +
    'layout(location=1) in vec3 aNormal;'#10 +
    'layout(location=2) in vec3 aColor;'#10 +
    'uniform mat4 uModel;'#10 +
    'uniform mat4 uView;'#10 +
    'uniform mat4 uProj;'#10 +
    'out vec3 vNormal;'#10 +
    'out vec3 vColor;'#10 +
    'void main() {'#10 +
    '  gl_Position = uProj * uView * uModel * vec4(aPos, 1.0);'#10 +
    '  vNormal = mat3(uModel) * aNormal;'#10 +
    '  vColor = aColor;'#10 +
    '}'#10;

  FRAG_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'in vec3 vNormal;'#10 +
    'in vec3 vColor;'#10 +
    'uniform vec3 uLightDir;'#10 +
    'out vec4 FragColor;'#10 +
    'void main() {'#10 +
    '  vec3 N = normalize(vNormal);'#10 +
    '  float d = max(dot(N, normalize(uLightDir)), 0.0);'#10 +
    '  float shade = 0.25 + 0.75 * d;'#10 +
    '  FragColor = vec4(vColor * shade, 1.0);'#10 +
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

function MeshShaderInit(out s: TMeshShader): boolean;
var
  vs, fs: GLuint;
  ok, logLen: GLint;
  logBuf: array[0..1023] of AnsiChar;
begin
  MeshShaderInit := false;
  FillChar(s, SizeOf(s), 0);

  vs := CompileShader(GL_VERTEX_SHADER, VERT_SRC);
  if vs = 0 then exit;
  fs := CompileShader(GL_FRAGMENT_SHADER, FRAG_SRC);
  if fs = 0 then begin glDeleteShader(vs); exit; end;

  s.prog := glCreateProgram();
  glAttachShader(s.prog, vs);
  glAttachShader(s.prog, fs);
  glLinkProgram(s.prog);
  glDeleteShader(vs);
  glDeleteShader(fs);

  glGetProgramiv(s.prog, GL_LINK_STATUS, @ok);
  if ok = GL_FALSE then begin
    glGetProgramInfoLog(s.prog, SizeOf(logBuf), @logLen, @logBuf[0]);
    writeln(StdErr, 'meshshader: link failed: ', PAnsiChar(@logBuf[0]));
    glDeleteProgram(s.prog);
    s.prog := 0;
    exit;
  end;

  s.uModel    := glGetUniformLocation(s.prog, 'uModel');
  s.uView     := glGetUniformLocation(s.prog, 'uView');
  s.uProj     := glGetUniformLocation(s.prog, 'uProj');
  s.uLightDir := glGetUniformLocation(s.prog, 'uLightDir');
  MeshShaderInit := true;
end;

procedure MeshShaderBegin(const s: TMeshShader; const view, proj: TMat4;
  const lightDir: TVec3);
begin
  glUseProgram(s.prog);
  glUniformMatrix4fv(s.uView, 1, GL_FALSE, @view[0]);
  glUniformMatrix4fv(s.uProj, 1, GL_FALSE, @proj[0]);
  glUniform3f(s.uLightDir, lightDir.x, lightDir.y, lightDir.z);
end;

procedure MeshShaderModel(const s: TMeshShader; const model: TMat4);
begin
  glUniformMatrix4fv(s.uModel, 1, GL_FALSE, @model[0]);
end;

procedure MeshShaderFree(var s: TMeshShader);
begin
  if s.prog <> 0 then glDeleteProgram(s.prog);
  FillChar(s, SizeOf(s), 0);
end;

end.
