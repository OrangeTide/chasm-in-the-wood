unit guigl;
{ The OpenGL canvas: a concrete TCanvas for the toolkit, drawn as a 2D overlay. }
{ Every primitive, text included, is a solid-coloured screen-space rectangle, so }
{ the canvas batches rectangles into one orthographic, alpha-blended pass and     }
{ clips with the scissor box. It carries a small embedded bitmap font.            }

{$mode objfpc}{$H+}

interface

uses
  glcore, gui;

type
  TGLCanvas = class(TCanvas)
  private
    FProg: GLuint;
    FUViewport: GLint;
    FVao, FVbo: GLuint;
    FVerts: array of GLfloat;   { 6 floats per vertex: x, y, r, g, b, a }
    FNverts: LongInt;
    FVw, FVh: LongInt;
    FScale: LongInt;
    procedure PushVertex(x, y: LongInt; r, g, b, a: GLfloat);
    procedure PushQuad(x0, y0, x1, y1: LongInt; c: TColor);
    procedure Flush;
  public
    constructor Create(viewW, viewH: LongInt);
    destructor Destroy; override;
    procedure Resize(viewW, viewH: LongInt);
    procedure BeginFrame;    { set 2D GL state and start a batch }
    procedure EndFrame;      { draw the batch and restore 3D GL state }

    procedure SetClip(const r: TRect); override;
    procedure ClearClip; override;
    procedure FillRect(const r: TRect; c: TColor); override;
    procedure FrameRect(const r: TRect; c: TColor); override;
    procedure HLine(x1, x2, y: LongInt; c: TColor); override;
    procedure VLine(x, y1, y2: LongInt; c: TColor); override;
    procedure DrawText(x, y: LongInt; const s: String; c: TColor); override;
    function  TextWidth(const s: String): LongInt; override;
    function  TextHeight: LongInt; override;
  end;

implementation

{ ---- 5x7 bitmap font, codes 32..90, lowercase folded to uppercase ---- }
{ Each row's low 5 bits are pixels, leftmost column = value 16.             }
const
  FontLo = 32;
  FontHi = 90;
  Font: array[FontLo..FontHi] of array[0..6] of Byte = (
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 32 space }
    (%00100,%00100,%00100,%00100,%00100,%00000,%00100), { 33 ! }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 34 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 35 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 36 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 37 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 38 }
    (%00100,%00100,%01000,%00000,%00000,%00000,%00000), { 39 ' }
    (%00010,%00100,%01000,%01000,%01000,%00100,%00010), { 40 ( }
    (%01000,%00100,%00010,%00010,%00010,%00100,%01000), { 41 ) }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 42 }
    (%00000,%00100,%00100,%11111,%00100,%00100,%00000), { 43 + }
    (%00000,%00000,%00000,%00000,%01100,%00100,%01000), { 44 , }
    (%00000,%00000,%00000,%11111,%00000,%00000,%00000), { 45 - }
    (%00000,%00000,%00000,%00000,%00000,%01100,%01100), { 46 . }
    (%00001,%00001,%00010,%00100,%01000,%10000,%10000), { 47 / }
    (%01110,%10001,%10011,%10101,%11001,%10001,%01110), { 48 0 }
    (%00100,%01100,%00100,%00100,%00100,%00100,%01110), { 49 1 }
    (%01110,%10001,%00001,%00010,%00100,%01000,%11111), { 50 2 }
    (%11111,%00010,%00100,%00010,%00001,%10001,%01110), { 51 3 }
    (%00010,%00110,%01010,%10010,%11111,%00010,%00010), { 52 4 }
    (%11111,%10000,%11110,%00001,%00001,%10001,%01110), { 53 5 }
    (%00110,%01000,%10000,%11110,%10001,%10001,%01110), { 54 6 }
    (%11111,%00001,%00010,%00100,%01000,%01000,%01000), { 55 7 }
    (%01110,%10001,%10001,%01110,%10001,%10001,%01110), { 56 8 }
    (%01110,%10001,%10001,%01111,%00001,%00010,%01100), { 57 9 }
    (%00000,%01100,%01100,%00000,%01100,%01100,%00000), { 58 : }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 59 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 60 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 61 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 62 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 63 }
    (%00000,%00000,%00000,%00000,%00000,%00000,%00000), { 64 }
    (%01110,%10001,%10001,%11111,%10001,%10001,%10001), { 65 A }
    (%11110,%10001,%10001,%11110,%10001,%10001,%11110), { 66 B }
    (%01111,%10000,%10000,%10000,%10000,%10000,%01111), { 67 C }
    (%11110,%10001,%10001,%10001,%10001,%10001,%11110), { 68 D }
    (%11111,%10000,%10000,%11110,%10000,%10000,%11111), { 69 E }
    (%11111,%10000,%10000,%11110,%10000,%10000,%10000), { 70 F }
    (%01111,%10000,%10000,%10111,%10001,%10001,%01111), { 71 G }
    (%10001,%10001,%10001,%11111,%10001,%10001,%10001), { 72 H }
    (%11111,%00100,%00100,%00100,%00100,%00100,%11111), { 73 I }
    (%00111,%00010,%00010,%00010,%00010,%10010,%01100), { 74 J }
    (%10001,%10010,%10100,%11000,%10100,%10010,%10001), { 75 K }
    (%10000,%10000,%10000,%10000,%10000,%10000,%11111), { 76 L }
    (%10001,%11011,%10101,%10101,%10001,%10001,%10001), { 77 M }
    (%10001,%10001,%11001,%10101,%10011,%10001,%10001), { 78 N }
    (%01110,%10001,%10001,%10001,%10001,%10001,%01110), { 79 O }
    (%11110,%10001,%10001,%11110,%10000,%10000,%10000), { 80 P }
    (%01110,%10001,%10001,%10001,%10101,%10010,%01101), { 81 Q }
    (%11110,%10001,%10001,%11110,%10100,%10010,%10001), { 82 R }
    (%01111,%10000,%10000,%01110,%00001,%00001,%11110), { 83 S }
    (%11111,%00100,%00100,%00100,%00100,%00100,%00100), { 84 T }
    (%10001,%10001,%10001,%10001,%10001,%10001,%01110), { 85 U }
    (%10001,%10001,%10001,%10001,%10001,%01010,%00100), { 86 V }
    (%10001,%10001,%10001,%10101,%10101,%11011,%10001), { 87 W }
    (%10001,%10001,%01010,%00100,%01010,%10001,%10001), { 88 X }
    (%10001,%10001,%01010,%00100,%00100,%00100,%00100), { 89 Y }
    (%11111,%00001,%00010,%00100,%01000,%10000,%11111)  { 90 Z }
  );

  VERT_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'layout(location=0) in vec2 aPos;'#10 +
    'layout(location=1) in vec4 aColor;'#10 +
    'uniform vec2 uViewport;'#10 +
    'out vec4 vColor;'#10 +
    'void main() {'#10 +
    '  float nx = aPos.x / uViewport.x * 2.0 - 1.0;'#10 +
    '  float ny = 1.0 - aPos.y / uViewport.y * 2.0;'#10 +
    '  gl_Position = vec4(nx, ny, 0.0, 1.0);'#10 +
    '  vColor = aColor;'#10 +
    '}'#10;

  FRAG_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'in vec4 vColor;'#10 +
    'out vec4 FragColor;'#10 +
    'void main() { FragColor = vColor; }'#10;

function Compile(kind: GLenum; const src: PAnsiChar): GLuint;
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
    writeln(StdErr, 'guigl: shader compile failed: ', PAnsiChar(@logBuf[0]));
    glDeleteShader(sh);
    Compile := 0;
    exit;
  end;
  Compile := sh;
end;

constructor TGLCanvas.Create(viewW, viewH: LongInt);
var
  vs, fs: GLuint;
  stride: GLsizei;
begin
  inherited Create;
  FVw := viewW; FVh := viewH;
  FScale := 2;
  FNverts := 0;
  SetLength(FVerts, 6 * 6 * 256);   { room for 256 quads before a grow }

  vs := Compile(GL_VERTEX_SHADER, VERT_SRC);
  fs := Compile(GL_FRAGMENT_SHADER, FRAG_SRC);
  FProg := glCreateProgram();
  glAttachShader(FProg, vs);
  glAttachShader(FProg, fs);
  glLinkProgram(FProg);
  glDeleteShader(vs);
  glDeleteShader(fs);
  FUViewport := glGetUniformLocation(FProg, 'uViewport');

  glGenVertexArrays(1, @FVao);
  glGenBuffers(1, @FVbo);
  glBindVertexArray(FVao);
  glBindBuffer(GL_ARRAY_BUFFER, FVbo);
  glBufferData(GL_ARRAY_BUFFER, Length(FVerts) * SizeOf(GLfloat), nil, GL_DYNAMIC_DRAW);
  stride := 6 * SizeOf(GLfloat);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, Pointer(0));
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, stride, Pointer(2 * SizeOf(GLfloat)));
  glEnableVertexAttribArray(1);
  glBindVertexArray(0);
end;

destructor TGLCanvas.Destroy;
begin
  if FVbo <> 0 then glDeleteBuffers(1, @FVbo);
  if FVao <> 0 then glDeleteVertexArrays(1, @FVao);
  if FProg <> 0 then glDeleteProgram(FProg);
  inherited Destroy;
end;

procedure TGLCanvas.Resize(viewW, viewH: LongInt);
begin
  FVw := viewW; FVh := viewH;
end;

procedure TGLCanvas.PushVertex(x, y: LongInt; r, g, b, a: GLfloat);
var
  base: LongInt;
begin
  base := FNverts * 6;
  if base + 6 > Length(FVerts) then SetLength(FVerts, Length(FVerts) * 2);
  FVerts[base + 0] := x;
  FVerts[base + 1] := y;
  FVerts[base + 2] := r;
  FVerts[base + 3] := g;
  FVerts[base + 4] := b;
  FVerts[base + 5] := a;
  Inc(FNverts);
end;

procedure TGLCanvas.PushQuad(x0, y0, x1, y1: LongInt; c: TColor);
var
  r, g, b, a: GLfloat;
begin
  a := ((c shr 24) and $FF) / 255.0;
  r := ((c shr 16) and $FF) / 255.0;
  g := ((c shr 8) and $FF) / 255.0;
  b := (c and $FF) / 255.0;
  PushVertex(x0, y0, r, g, b, a);
  PushVertex(x1, y0, r, g, b, a);
  PushVertex(x1, y1, r, g, b, a);
  PushVertex(x0, y0, r, g, b, a);
  PushVertex(x1, y1, r, g, b, a);
  PushVertex(x0, y1, r, g, b, a);
end;

procedure TGLCanvas.Flush;
begin
  if FNverts = 0 then exit;
  glBindVertexArray(FVao);
  glBindBuffer(GL_ARRAY_BUFFER, FVbo);
  glBufferData(GL_ARRAY_BUFFER, FNverts * 6 * SizeOf(GLfloat), @FVerts[0], GL_DYNAMIC_DRAW);
  glDrawArrays(GL_TRIANGLES, 0, FNverts);
  glBindVertexArray(0);
  FNverts := 0;
end;

procedure TGLCanvas.BeginFrame;
begin
  FNverts := 0;
  glUseProgram(FProg);
  glUniform2f(FUViewport, FVw, FVh);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
end;

procedure TGLCanvas.EndFrame;
begin
  Flush;
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_DEPTH_TEST);
  glEnable(GL_CULL_FACE);
end;

procedure TGLCanvas.SetClip(const r: TRect);
begin
  Flush;   { queued quads belong to the previous clip region }
  glEnable(GL_SCISSOR_TEST);
  glScissor(r.Left, FVh - r.Bottom, RectW(r), RectH(r));
end;

procedure TGLCanvas.ClearClip;
begin
  Flush;
  glDisable(GL_SCISSOR_TEST);
end;

procedure TGLCanvas.FillRect(const r: TRect; c: TColor);
begin
  PushQuad(r.Left, r.Top, r.Right, r.Bottom, c);
end;

procedure TGLCanvas.FrameRect(const r: TRect; c: TColor);
begin
  PushQuad(r.Left, r.Top, r.Right, r.Top + 1, c);        { top }
  PushQuad(r.Left, r.Bottom - 1, r.Right, r.Bottom, c);  { bottom }
  PushQuad(r.Left, r.Top, r.Left + 1, r.Bottom, c);      { left }
  PushQuad(r.Right - 1, r.Top, r.Right, r.Bottom, c);    { right }
end;

procedure TGLCanvas.HLine(x1, x2, y: LongInt; c: TColor);
begin
  if x2 < x1 then PushQuad(x2, y, x1 + 1, y + 1, c)
  else PushQuad(x1, y, x2 + 1, y + 1, c);
end;

procedure TGLCanvas.VLine(x, y1, y2: LongInt; c: TColor);
begin
  if y2 < y1 then PushQuad(x, y2, x + 1, y1 + 1, c)
  else PushQuad(x, y1, x + 1, y2 + 1, c);
end;

procedure TGLCanvas.DrawText(x, y: LongInt; const s: String; c: TColor);
var
  i, col, row, cx: LongInt;
  ch: Char;
  bits: Byte;
begin
  cx := x;
  for i := 1 to Length(s) do begin
    ch := UpCase(s[i]);
    if (Ord(ch) >= FontLo) and (Ord(ch) <= FontHi) then
      for row := 0 to 6 do begin
        bits := Font[Ord(ch)][row];
        for col := 0 to 4 do
          if (bits and (16 shr col)) <> 0 then
            PushQuad(cx + col * FScale, y + row * FScale,
                     cx + col * FScale + FScale, y + row * FScale + FScale, c);
      end;
    cx := cx + 6 * FScale;
  end;
end;

function TGLCanvas.TextWidth(const s: String): LongInt;
begin
  TextWidth := Length(s) * 6 * FScale;
end;

function TGLCanvas.TextHeight: LongInt;
begin
  TextHeight := 7 * FScale;
end;

end.
