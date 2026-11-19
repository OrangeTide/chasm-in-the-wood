/* model.h : glTF model loading for the renderer (see doc/rendering.md).
 *
 * Wraps cgltf. Loads a self-contained .glb (as delivered through the asset
 * pipeline) into plain CPU-side arrays: skinned geometry, the skin's inverse
 * bind matrices, and the node hierarchy needed to pose the skeleton. The
 * renderer (gfx.c) owns all GL; this module never touches it.
 */
#ifndef MODEL_H
#define MODEL_H

#include <stddef.h>
#include <stdint.h>

/* Skinning fits in a single joint palette; every vertex references up to four
 * joints. Keep this in sync with the shader's u_joint[] length. */
#define MODEL_MAX_JOINTS 128

/* Top-level structure counts from a parsed glTF/GLB. */
struct model_info {
    size_t nodes;
    size_t meshes;
    size_t skins;
    size_t animations;
};

/* One drawable primitive: indexed triangles with per-vertex skin data. Arrays
 * are tightly packed; positions/normals are 3 floats, joints/weights 4 each. */
struct model_prim {
    float    *positions;    /* 3 * vertex_count */
    float    *normals;      /* 3 * vertex_count */
    uint8_t  *joints;       /* 4 * vertex_count, indices into the joint palette */
    float    *weights;      /* 4 * vertex_count */
    float    *colors;       /* 4 * vertex_count from COLOR_0, or NULL if absent */
    float    *uv;           /* 2 * vertex_count from TEXCOORD_0, or NULL */
    float     base_color[4];/* material pbr baseColorFactor (1,1,1,1 if none) */
    char      tex[64];      /* base-color texture file basename, "" if untextured */
    uint32_t *indices;      /* index_count */
    uint32_t  vertex_count;
    uint32_t  index_count;
};

/* A loaded model: geometry plus the skeleton that skins it. Node transforms
 * start at the bind (rest) pose; animation later overwrites node TRS in place
 * before re-posing. */
struct model {
    struct model_prim *prims;
    int                prim_count;

    /* Skin: the joints that drive the mesh, in palette order. */
    int    joint_count;
    int   *joint_nodes;     /* [joint_count] node index per palette slot */
    float *inverse_bind;    /* [16 * joint_count] column-major mat4 per joint */

    /* Full node hierarchy. The TRS arrays hold the immutable bind (rest) pose;
     * animation samples into separate local-TRS buffers (see anim.h) that are
     * fed to model_pose_from_local. Quaternions are (x, y, z, w). */
    int    node_count;
    int   *node_parent;     /* [node_count], -1 for a root */
    float *node_t;          /* [3 * node_count] bind translation */
    float *node_r;          /* [4 * node_count] bind rotation quaternion */
    float *node_s;          /* [3 * node_count] bind scale */
    char **node_names;      /* [node_count], may hold NULL entries */
};

/* Parse a glTF or GLB blob already resident in memory and fill out with its
 * top-level counts. The blob must be self-contained. Returns 0 on success,
 * -1 on a parse or validation failure. */
int model_probe(const void *data, size_t len, struct model_info *out);

/* Load a self-contained .glb from disk into a fully owned struct model.
 * Returns NULL on failure. Free with model_free. */
struct model *model_load(const char *path);

void model_free(struct model *m);

/* Write joint_count column-major skinning matrices (16 floats each) into out,
 * from the model's bind-pose TRS. This yields the identity for every joint
 * (the mesh renders as authored). out must hold at least 16 * m->joint_count
 * floats. */
void model_pose_joint_matrices(const struct model *m, float *out);

/* Same, but from caller-supplied local TRS arrays (lt: 3*node_count,
 * lr: 4*node_count, ls: 3*node_count) rather than the bind pose. This is how
 * an animated (or blended) pose is turned into the joint palette. */
void model_pose_from_local(const struct model *m, const float *lt,
    const float *lr, const float *ls, float *out);

#endif /* MODEL_H */
