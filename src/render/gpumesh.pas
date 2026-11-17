unit gpumesh;

{** A mesh resident on the GPU.

  Uploads a TVoxMesh into a vertex array plus vertex and index buffers, and draws
  the indexed triangles. It carries no shader of its own; the caller binds a
  program (see meshshader) and sets the per-object model matrix before drawing.
  This split lets the floor, the player, and later props share one program while
  each keeps its own buffers. }

{$mode objfpc}{$H+}

interface

uses
  glcore, voxmesh;

type
  TGpuMesh = record
    Vao, Vbo, Ebo: GLuint;
    IndexCount: GLsizei;
  end;

procedure GpuMeshUpload(out g: TGpuMesh; const mesh: TVoxMesh);
procedure GpuMeshDraw(const g: TGpuMesh);
procedure GpuMeshFree(var g: TGpuMesh);

implementation

procedure GpuMeshUpload(out g: TGpuMesh; const mesh: TVoxMesh);
var
  stride: GLsizei;
begin
  FillChar(g, SizeOf(g), 0);
  glGenVertexArrays(1, @g.Vao);
  glGenBuffers(1, @g.Vbo);
  glGenBuffers(1, @g.Ebo);

  glBindVertexArray(g.Vao);

  glBindBuffer(GL_ARRAY_BUFFER, g.Vbo);
  glBufferData(GL_ARRAY_BUFFER, mesh.Nverts * SizeOf(TMeshVertex),
    @mesh.Verts[0], GL_STATIC_DRAW);

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, g.Ebo);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, mesh.Nindices * SizeOf(LongWord),
    @mesh.Indices[0], GL_STATIC_DRAW);

  stride := SizeOf(TMeshVertex);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, Pointer(0));
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, Pointer(12));
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, stride, Pointer(24));
  glEnableVertexAttribArray(2);
  glVertexAttribPointer(3, 1, GL_FLOAT, GL_FALSE, stride, Pointer(36));
  glEnableVertexAttribArray(3);

  glBindVertexArray(0);
  g.IndexCount := mesh.Nindices;
end;

procedure GpuMeshDraw(const g: TGpuMesh);
begin
  glBindVertexArray(g.Vao);
  glDrawElements(GL_TRIANGLES, g.IndexCount, GL_UNSIGNED_INT, Pointer(0));
  glBindVertexArray(0);
end;

procedure GpuMeshFree(var g: TGpuMesh);
begin
  if g.Vbo <> 0 then glDeleteBuffers(1, @g.Vbo);
  if g.Ebo <> 0 then glDeleteBuffers(1, @g.Ebo);
  if g.Vao <> 0 then glDeleteVertexArrays(1, @g.Vao);
  FillChar(g, SizeOf(g), 0);
end;

end.
