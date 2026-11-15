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
    vao, vbo, ebo: GLuint;
    indexCount: GLsizei;
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
  glGenVertexArrays(1, @g.vao);
  glGenBuffers(1, @g.vbo);
  glGenBuffers(1, @g.ebo);

  glBindVertexArray(g.vao);

  glBindBuffer(GL_ARRAY_BUFFER, g.vbo);
  glBufferData(GL_ARRAY_BUFFER, mesh.nverts * SizeOf(TMeshVertex),
    @mesh.verts[0], GL_STATIC_DRAW);

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, g.ebo);
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
  g.indexCount := mesh.nindices;
end;

procedure GpuMeshDraw(const g: TGpuMesh);
begin
  glBindVertexArray(g.vao);
  glDrawElements(GL_TRIANGLES, g.indexCount, GL_UNSIGNED_INT, Pointer(0));
  glBindVertexArray(0);
end;

procedure GpuMeshFree(var g: TGpuMesh);
begin
  if g.vbo <> 0 then glDeleteBuffers(1, @g.vbo);
  if g.ebo <> 0 then glDeleteBuffers(1, @g.ebo);
  if g.vao <> 0 then glDeleteVertexArrays(1, @g.vao);
  FillChar(g, SizeOf(g), 0);
end;

end.
