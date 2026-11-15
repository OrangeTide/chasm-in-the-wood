unit voxrender;

{** Draws a voxel mesh with OpenGL 3.3 core.

  Owns one shader program and one vertex-array/buffer set built from a TVoxMesh.
  Lighting is a single directional term plus ambient, enough to read the voxel
  faces as solid form. The caller supplies the model, view, and projection
  matrices each frame. }

{$mode objfpc}{$H+}

interface

uses
  glcore, vecmath, voxmesh;

type
  TVoxRenderer = record
    prog:       GLuint;
    vao, vbo, ebo: GLuint;
    indexCount: GLsizei;
    uModel, uView, uProj, uLightDir: GLint;
  end;

function VoxRendererInit(out r: TVoxRenderer; const mesh: TVoxMesh): boolean;
procedure VoxRendererDraw(const r: TVoxRenderer; const model, view, proj: TMat4;
  const lightDir: TVec3);
procedure VoxRendererFree(var r: TVoxRenderer);

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
  ok: GLint;
  logLen: GLint;
  logBuf: array[0..1023] of AnsiChar;
begin
  sh := glCreateShader(kind);
  glShaderSource(sh, 1, @src, nil);
  glCompileShader(sh);
  glGetShaderiv(sh, GL_COMPILE_STATUS, @ok);
  if ok = GL_FALSE then begin
    glGetShaderInfoLog(sh, SizeOf(logBuf), @logLen, @logBuf[0]);
    writeln(StdErr, 'voxrender: shader compile failed: ', PAnsiChar(@logBuf[0]));
    glDeleteShader(sh);
    CompileShader := 0;
    exit;
  end;
  CompileShader := sh;
end;

function LinkProgram(vs, fs: GLuint): GLuint;
var
  p: GLuint;
  ok: GLint;
  logLen: GLint;
  logBuf: array[0..1023] of AnsiChar;
begin
  p := glCreateProgram();
  glAttachShader(p, vs);
  glAttachShader(p, fs);
  glLinkProgram(p);
  glGetProgramiv(p, GL_LINK_STATUS, @ok);
  if ok = GL_FALSE then begin
    glGetProgramInfoLog(p, SizeOf(logBuf), @logLen, @logBuf[0]);
    writeln(StdErr, 'voxrender: program link failed: ', PAnsiChar(@logBuf[0]));
    glDeleteProgram(p);
    LinkProgram := 0;
    exit;
  end;
  LinkProgram := p;
end;

function VoxRendererInit(out r: TVoxRenderer; const mesh: TVoxMesh): boolean;
var
  vs, fs: GLuint;
  stride: GLsizei;
begin
  VoxRendererInit := false;
  FillChar(r, SizeOf(r), 0);

  vs := CompileShader(GL_VERTEX_SHADER, VERT_SRC);
  if vs = 0 then exit;
  fs := CompileShader(GL_FRAGMENT_SHADER, FRAG_SRC);
  if fs = 0 then begin glDeleteShader(vs); exit; end;
  r.prog := LinkProgram(vs, fs);
  glDeleteShader(vs);
  glDeleteShader(fs);
  if r.prog = 0 then exit;

  r.uModel    := glGetUniformLocation(r.prog, 'uModel');
  r.uView     := glGetUniformLocation(r.prog, 'uView');
  r.uProj     := glGetUniformLocation(r.prog, 'uProj');
  r.uLightDir := glGetUniformLocation(r.prog, 'uLightDir');

  glGenVertexArrays(1, @r.vao);
  glGenBuffers(1, @r.vbo);
  glGenBuffers(1, @r.ebo);

  glBindVertexArray(r.vao);

  glBindBuffer(GL_ARRAY_BUFFER, r.vbo);
  glBufferData(GL_ARRAY_BUFFER, mesh.nverts * SizeOf(TMeshVertex),
    @mesh.verts[0], GL_STATIC_DRAW);

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, r.ebo);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, mesh.nindices * SizeOf(longword),
    @mesh.indices[0], GL_STATIC_DRAW);

  stride := SizeOf(TMeshVertex);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, Pointer(0));
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, Pointer(12));
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, stride, Pointer(24));
  glEnableVertexAttribArray(2);

  glBindVertexArray(0);

  r.indexCount := mesh.nindices;
  VoxRendererInit := true;
end;

procedure VoxRendererDraw(const r: TVoxRenderer; const model, view, proj: TMat4;
  const lightDir: TVec3);
begin
  glUseProgram(r.prog);
  glUniformMatrix4fv(r.uModel, 1, GL_FALSE, @model[0]);
  glUniformMatrix4fv(r.uView, 1, GL_FALSE, @view[0]);
  glUniformMatrix4fv(r.uProj, 1, GL_FALSE, @proj[0]);
  glUniform3f(r.uLightDir, lightDir.x, lightDir.y, lightDir.z);
  glBindVertexArray(r.vao);
  glDrawElements(GL_TRIANGLES, r.indexCount, GL_UNSIGNED_INT, Pointer(0));
  glBindVertexArray(0);
end;

procedure VoxRendererFree(var r: TVoxRenderer);
begin
  if r.vbo <> 0 then glDeleteBuffers(1, @r.vbo);
  if r.ebo <> 0 then glDeleteBuffers(1, @r.ebo);
  if r.vao <> 0 then glDeleteVertexArrays(1, @r.vao);
  if r.prog <> 0 then glDeleteProgram(r.prog);
  FillChar(r, SizeOf(r), 0);
end;

end.
