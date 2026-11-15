unit glcore;

{** OpenGL 3.3 core entry points, loaded at runtime.

  The modern GL functions are not exported by libGL's link interface in a
  portable way, so we resolve each through a proc-address loader (SDL provides
  one) after the context exists. Only the subset the renderer uses is declared.
  Call LoadGL once, passing SDL_GL_GetProcAddress, before any gl* call. }

{$mode objfpc}{$H+}

interface

uses
  ctypes;

type
  GLenum     = cuint32;
  GLbitfield = cuint32;
  GLuint     = cuint32;
  GLint      = cint32;
  GLsizei    = cint32;
  GLfloat    = single;
  GLboolean  = byte;
  GLchar     = AnsiChar;
  GLsizeiptr = PtrInt;
  GLintptr   = PtrInt;

  PGLuint  = ^GLuint;
  PGLint   = ^GLint;
  PGLchar  = ^GLchar;
  PGLfloat = ^GLfloat;

  TGLGetProcAddr = function(const name: PAnsiChar): Pointer; cdecl;

const
  GL_FALSE = 0;
  GL_TRUE  = 1;

  GL_DEPTH_BUFFER_BIT = $00000100;
  GL_COLOR_BUFFER_BIT = $00004000;

  GL_TRIANGLES = $0004;

  GL_LESS       = $0201;
  GL_CULL_FACE  = $0B44;
  GL_DEPTH_TEST = $0B71;
  GL_BACK       = $0405;
  GL_CCW        = $0901;

  GL_ARRAY_BUFFER         = $8892;
  GL_ELEMENT_ARRAY_BUFFER = $8893;
  GL_STATIC_DRAW          = $88E4;

  GL_FLOAT         = $1406;
  GL_UNSIGNED_INT  = $1405;
  GL_UNSIGNED_BYTE = $1401;
  GL_RGB           = $1907;

  GL_VERTEX_SHADER   = $8B31;
  GL_FRAGMENT_SHADER = $8B30;
  GL_COMPILE_STATUS  = $8B81;
  GL_LINK_STATUS     = $8B82;

  GL_VENDOR   = $1F00;
  GL_RENDERER = $1F01;
  GL_VERSION  = $1F02;

var
  { Fixed-pipeline-era calls exported by libGL; still resolved through the loader
    for uniformity. }
  glClearColor: procedure(r, g, b, a: GLfloat); cdecl;
  glClear:      procedure(mask: GLbitfield); cdecl;
  glEnable:     procedure(cap: GLenum); cdecl;
  glDisable:    procedure(cap: GLenum); cdecl;
  glCullFace:   procedure(mode: GLenum); cdecl;
  glFrontFace:  procedure(mode: GLenum); cdecl;
  glDepthFunc:  procedure(func: GLenum); cdecl;
  glViewport:   procedure(x, y: GLint; w, h: GLsizei); cdecl;
  glGetString:  function(name: GLenum): PAnsiChar; cdecl;
  glDrawElements: procedure(mode: GLenum; count: GLsizei; typ: GLenum; const indices: Pointer); cdecl;
  glReadPixels: procedure(x, y: GLint; w, h: GLsizei; format, typ: GLenum; data: Pointer); cdecl;

  { Buffer and vertex-array objects. }
  glGenVertexArrays:    procedure(n: GLsizei; arrays: PGLuint); cdecl;
  glBindVertexArray:    procedure(arr: GLuint); cdecl;
  glDeleteVertexArrays: procedure(n: GLsizei; const arrays: PGLuint); cdecl;
  glGenBuffers:         procedure(n: GLsizei; buffers: PGLuint); cdecl;
  glBindBuffer:         procedure(target: GLenum; buffer: GLuint); cdecl;
  glDeleteBuffers:      procedure(n: GLsizei; const buffers: PGLuint); cdecl;
  glBufferData:         procedure(target: GLenum; size: GLsizeiptr; const data: Pointer; usage: GLenum); cdecl;
  glVertexAttribPointer: procedure(index: GLuint; size: GLint; typ: GLenum; normalized: GLboolean; stride: GLsizei; const offset: Pointer); cdecl;
  glEnableVertexAttribArray: procedure(index: GLuint); cdecl;

  { Shader objects and programs. }
  glCreateShader:     function(shaderType: GLenum): GLuint; cdecl;
  glShaderSource:     procedure(shader: GLuint; count: GLsizei; const str: PPAnsiChar; const length: PGLint); cdecl;
  glCompileShader:    procedure(shader: GLuint); cdecl;
  glGetShaderiv:      procedure(shader: GLuint; pname: GLenum; params: PGLint); cdecl;
  glGetShaderInfoLog: procedure(shader: GLuint; maxLength: GLsizei; length: PGLint; infoLog: PGLchar); cdecl;
  glDeleteShader:     procedure(shader: GLuint); cdecl;
  glCreateProgram:    function: GLuint; cdecl;
  glAttachShader:     procedure(prog, shader: GLuint); cdecl;
  glLinkProgram:      procedure(prog: GLuint); cdecl;
  glGetProgramiv:     procedure(prog: GLuint; pname: GLenum; params: PGLint); cdecl;
  glGetProgramInfoLog: procedure(prog: GLuint; maxLength: GLsizei; length: PGLint; infoLog: PGLchar); cdecl;
  glUseProgram:       procedure(prog: GLuint); cdecl;
  glDeleteProgram:    procedure(prog: GLuint); cdecl;
  glGetUniformLocation: function(prog: GLuint; const name: PAnsiChar): GLint; cdecl;
  glUniformMatrix4fv: procedure(location: GLint; count: GLsizei; transpose: GLboolean; const value: PGLfloat); cdecl;
  glUniform3f:        procedure(location: GLint; v0, v1, v2: GLfloat); cdecl;

function LoadGL(getProc: TGLGetProcAddr): boolean;

implementation

var
  loadOk: boolean;

procedure Bind(var slot: Pointer; getProc: TGLGetProcAddr; const name: PAnsiChar);
var
  p: Pointer;
begin
  p := getProc(name);
  if p = nil then begin
    writeln(StdErr, 'glcore: missing GL entry point ', name);
    loadOk := false;
  end;
  slot := p;
end;

function LoadGL(getProc: TGLGetProcAddr): boolean;
begin
  loadOk := true;
  Bind(Pointer(glClearColor), getProc, 'glClearColor');
  Bind(Pointer(glClear), getProc, 'glClear');
  Bind(Pointer(glEnable), getProc, 'glEnable');
  Bind(Pointer(glDisable), getProc, 'glDisable');
  Bind(Pointer(glCullFace), getProc, 'glCullFace');
  Bind(Pointer(glFrontFace), getProc, 'glFrontFace');
  Bind(Pointer(glDepthFunc), getProc, 'glDepthFunc');
  Bind(Pointer(glViewport), getProc, 'glViewport');
  Bind(Pointer(glGetString), getProc, 'glGetString');
  Bind(Pointer(glDrawElements), getProc, 'glDrawElements');
  Bind(Pointer(glReadPixels), getProc, 'glReadPixels');
  Bind(Pointer(glGenVertexArrays), getProc, 'glGenVertexArrays');
  Bind(Pointer(glBindVertexArray), getProc, 'glBindVertexArray');
  Bind(Pointer(glDeleteVertexArrays), getProc, 'glDeleteVertexArrays');
  Bind(Pointer(glGenBuffers), getProc, 'glGenBuffers');
  Bind(Pointer(glBindBuffer), getProc, 'glBindBuffer');
  Bind(Pointer(glDeleteBuffers), getProc, 'glDeleteBuffers');
  Bind(Pointer(glBufferData), getProc, 'glBufferData');
  Bind(Pointer(glVertexAttribPointer), getProc, 'glVertexAttribPointer');
  Bind(Pointer(glEnableVertexAttribArray), getProc, 'glEnableVertexAttribArray');
  Bind(Pointer(glCreateShader), getProc, 'glCreateShader');
  Bind(Pointer(glShaderSource), getProc, 'glShaderSource');
  Bind(Pointer(glCompileShader), getProc, 'glCompileShader');
  Bind(Pointer(glGetShaderiv), getProc, 'glGetShaderiv');
  Bind(Pointer(glGetShaderInfoLog), getProc, 'glGetShaderInfoLog');
  Bind(Pointer(glDeleteShader), getProc, 'glDeleteShader');
  Bind(Pointer(glCreateProgram), getProc, 'glCreateProgram');
  Bind(Pointer(glAttachShader), getProc, 'glAttachShader');
  Bind(Pointer(glLinkProgram), getProc, 'glLinkProgram');
  Bind(Pointer(glGetProgramiv), getProc, 'glGetProgramiv');
  Bind(Pointer(glGetProgramInfoLog), getProc, 'glGetProgramInfoLog');
  Bind(Pointer(glUseProgram), getProc, 'glUseProgram');
  Bind(Pointer(glDeleteProgram), getProc, 'glDeleteProgram');
  Bind(Pointer(glGetUniformLocation), getProc, 'glGetUniformLocation');
  Bind(Pointer(glUniformMatrix4fv), getProc, 'glUniformMatrix4fv');
  Bind(Pointer(glUniform3f), getProc, 'glUniform3f');
  LoadGL := loadOk;
end;

end.
