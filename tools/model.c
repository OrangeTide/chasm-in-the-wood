/* model.c : glTF model loading for the renderer (see doc/rendering.md).
 *
 * This is the single translation unit that defines CGLTF_IMPLEMENTATION, so
 * the header-only cgltf loader is compiled exactly once here.
 */
#include "model.h"

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

#include "HandmadeMath.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int
model_probe(const void *data, size_t len, struct model_info *out)
{
    cgltf_options options = {0};
    cgltf_data *gltf = NULL;

    if (cgltf_parse(&options, data, len, &gltf) != cgltf_result_success)
        return -1;

    if (cgltf_validate(gltf) != cgltf_result_success) {
        cgltf_free(gltf);
        return -1;
    }

    if (out) {
        out->nodes      = gltf->nodes_count;
        out->meshes     = gltf->meshes_count;
        out->skins      = gltf->skins_count;
        out->animations = gltf->animations_count;
    }

    cgltf_free(gltf);
    return 0;
}

/****************************************************************
 * Loading
 ****************************************************************/

/* strdup without depending on POSIX feature-test macros. NULL-safe. */
static char *
str_dup(const char *s)
{
    if (!s)
        return NULL;
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p)
        memcpy(p, s, n);
    return p;
}

/* Read a whole file into a malloc'd buffer. Returns the buffer (caller frees)
 * and stores its length; NULL on failure. */
static void *
read_file(const char *path, size_t *len_out)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long n = ftell(f);
    if (n < 0) {
        fclose(f);
        return NULL;
    }
    rewind(f);
    void *buf = malloc((size_t)n);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *len_out = (size_t)n;
    return buf;
}

/* Extract one primitive's skin geometry into m->prims[slot]. Returns 0 on
 * success, -1 if a required attribute is missing or an allocation fails. */
static int
load_prim(struct model_prim *p, const cgltf_primitive *src)
{
    memset(p, 0, sizeof *p);
    if (src->type != cgltf_primitive_type_triangles || !src->indices)
        return -1;

    const cgltf_accessor *pos = NULL, *nrm = NULL, *jnt = NULL, *wgt = NULL;
    const cgltf_accessor *col = NULL, *uvs = NULL;
    for (cgltf_size a = 0; a < src->attributes_count; a++) {
        const cgltf_attribute *at = &src->attributes[a];
        switch (at->type) {
        case cgltf_attribute_type_position: pos = at->data; break;
        case cgltf_attribute_type_normal:   nrm = at->data; break;
        case cgltf_attribute_type_texcoord:
            if (at->index == 0) uvs = at->data;   /* TEXCOORD_0 only */
            break;
        case cgltf_attribute_type_joints:
            if (at->index == 0) jnt = at->data;   /* JOINTS_0 (primary 4) only */
            break;
        case cgltf_attribute_type_weights:
            if (at->index == 0) wgt = at->data;   /* WEIGHTS_0 only; the shader
                                                   * skins with 4 influences */
            break;
        case cgltf_attribute_type_color:
            if (at->index == 0) col = at->data;   /* COLOR_0 only */
            break;
        default: break;
        }
    }
    if (!pos || !nrm || !jnt || !wgt)
        return -1;

    /* Material base color factor (glTF pbrMetallicRoughness). Multiplies the
     * vertex color; defaults to white when the primitive has no material. */
    p->base_color[0] = p->base_color[1] = p->base_color[2] = p->base_color[3]
        = 1.0f;
    if (src->material && src->material->has_pbr_metallic_roughness) {
        memcpy(p->base_color,
            src->material->pbr_metallic_roughness.base_color_factor,
            sizeof p->base_color);
        /* Base-color texture: keep just the image's file basename. The renderer
         * loads it from the staged texture directory (the GLB keeps images as
         * external URIs; see doc/rendering.md). "" means untextured. */
        const cgltf_texture *bt = src->material->pbr_metallic_roughness
            .base_color_texture.texture;
        if (bt && bt->image && bt->image->uri) {
            const char *u = bt->image->uri;
            const char *slash = strrchr(u, '/');
            snprintf(p->tex, sizeof p->tex, "%s", slash ? slash + 1 : u);
        }
    }

    uint32_t vc = (uint32_t)pos->count;
    uint32_t ic = (uint32_t)src->indices->count;
    p->vertex_count = vc;
    p->index_count = ic;
    p->positions = malloc(sizeof(float) * 3 * vc);
    p->normals   = malloc(sizeof(float) * 3 * vc);
    p->joints    = malloc(sizeof(uint8_t) * 4 * vc);
    p->weights   = malloc(sizeof(float) * 4 * vc);
    p->colors    = col ? malloc(sizeof(float) * 4 * vc) : NULL;
    p->uv        = uvs ? malloc(sizeof(float) * 2 * vc) : NULL;
    p->indices   = malloc(sizeof(uint32_t) * ic);
    if (!p->positions || !p->normals || !p->joints || !p->weights ||
        !p->indices || (col && !p->colors) || (uvs && !p->uv))
        return -1;

    for (uint32_t i = 0; i < vc; i++) {
        cgltf_accessor_read_float(pos, i, &p->positions[i * 3], 3);
        cgltf_accessor_read_float(nrm, i, &p->normals[i * 3], 3);
        cgltf_accessor_read_float(wgt, i, &p->weights[i * 4], 4);
        if (uvs)
            cgltf_accessor_read_float(uvs, i, &p->uv[i * 2], 2);
        cgltf_uint j4[4] = {0, 0, 0, 0};
        cgltf_accessor_read_uint(jnt, i, j4, 4);
        for (int k = 0; k < 4; k++)
            p->joints[i * 4 + k] = (uint8_t)j4[k];
        if (col) {
            /* COLOR_0 may be vec3 or vec4; read_float fills the available
             * components, so seed alpha = 1 for the vec3 case. */
            p->colors[i * 4 + 3] = 1.0f;
            cgltf_accessor_read_float(col, i, &p->colors[i * 4], 4);
        }
    }
    cgltf_accessor_unpack_indices(src->indices, p->indices,
        sizeof(uint32_t), ic);
    return 0;
}

struct model *
model_load(const char *path)
{
    size_t len = 0;
    void *buf = read_file(path, &len);
    if (!buf) {
        fprintf(stderr, "model_load: cannot read %s\n", path);
        return NULL;
    }

    cgltf_options options = {0};
    cgltf_data *gltf = NULL;
    if (cgltf_parse(&options, buf, len, &gltf) != cgltf_result_success) {
        fprintf(stderr, "model_load: cannot parse %s\n", path);
        free(buf);
        return NULL;
    }
    /* Self-contained .glb: the binary chunk is embedded, so no base path. */
    if (cgltf_load_buffers(&options, gltf, NULL) != cgltf_result_success) {
        fprintf(stderr, "model_load: cannot load buffers for %s\n", path);
        cgltf_free(gltf);
        free(buf);
        return NULL;
    }

    struct model *m = calloc(1, sizeof *m);
    if (!m)
        goto fail;

    /* Node hierarchy (all nodes): parent links and local TRS. */
    m->node_count = (int)gltf->nodes_count;
    m->node_parent = malloc(sizeof(int) * m->node_count);
    m->node_t = malloc(sizeof(float) * 3 * m->node_count);
    m->node_r = malloc(sizeof(float) * 4 * m->node_count);
    m->node_s = malloc(sizeof(float) * 3 * m->node_count);
    m->node_names = calloc((size_t)m->node_count, sizeof(char *));
    if (!m->node_parent || !m->node_t || !m->node_r || !m->node_s ||
        !m->node_names)
        goto fail;
    for (int i = 0; i < m->node_count; i++) {
        const cgltf_node *n = &gltf->nodes[i];
        m->node_parent[i] = n->parent
            ? (int)(n->parent - gltf->nodes) : -1;
        if (n->has_matrix)
            fprintf(stderr, "model_load: node %d uses a matrix transform; "
                "TRS animation may be wrong\n", i);
        /* cgltf fills translation/scale/rotation with identity defaults. */
        memcpy(&m->node_t[i * 3], n->translation, sizeof(float) * 3);
        memcpy(&m->node_r[i * 4], n->rotation, sizeof(float) * 4);
        memcpy(&m->node_s[i * 3], n->scale, sizeof(float) * 3);
        m->node_names[i] = str_dup(n->name);
    }

    /* Skin: joint palette (node per slot) and inverse bind matrices. */
    if (gltf->skins_count > 0) {
        const cgltf_skin *sk = &gltf->skins[0];
        m->joint_count = (int)sk->joints_count;
        if (m->joint_count > MODEL_MAX_JOINTS) {
            fprintf(stderr, "model_load: %d joints exceeds MODEL_MAX_JOINTS "
                "(%d)\n", m->joint_count, MODEL_MAX_JOINTS);
            goto fail;
        }
        m->joint_nodes = malloc(sizeof(int) * m->joint_count);
        m->inverse_bind = malloc(sizeof(float) * 16 * m->joint_count);
        if (!m->joint_nodes || !m->inverse_bind)
            goto fail;
        for (int j = 0; j < m->joint_count; j++) {
            m->joint_nodes[j] = (int)(sk->joints[j] - gltf->nodes);
            cgltf_accessor_read_float(sk->inverse_bind_matrices, (cgltf_size)j,
                &m->inverse_bind[j * 16], 16);
        }
    }

    /* Geometry: one model_prim per triangle primitive across all meshes. */
    int prim_total = 0;
    for (cgltf_size mi = 0; mi < gltf->meshes_count; mi++)
        prim_total += (int)gltf->meshes[mi].primitives_count;
    m->prims = calloc((size_t)(prim_total > 0 ? prim_total : 1),
        sizeof *m->prims);
    if (!m->prims)
        goto fail;
    for (cgltf_size mi = 0; mi < gltf->meshes_count; mi++) {
        const cgltf_mesh *mesh = &gltf->meshes[mi];
        for (cgltf_size pi = 0; pi < mesh->primitives_count; pi++) {
            if (load_prim(&m->prims[m->prim_count],
                    &mesh->primitives[pi]) == 0)
                m->prim_count++;
        }
    }
    if (m->prim_count == 0) {
        fprintf(stderr, "model_load: no skinned triangle primitives in %s\n",
            path);
        goto fail;
    }

    cgltf_free(gltf);
    free(buf);
    return m;

fail:
    if (m)
        model_free(m);
    cgltf_free(gltf);
    free(buf);
    return NULL;
}

void
model_free(struct model *m)
{
    if (!m)
        return;
    for (int i = 0; i < m->prim_count; i++) {
        free(m->prims[i].positions);
        free(m->prims[i].normals);
        free(m->prims[i].joints);
        free(m->prims[i].weights);
        free(m->prims[i].colors);
        free(m->prims[i].uv);
        free(m->prims[i].indices);
    }
    free(m->prims);
    free(m->joint_nodes);
    free(m->inverse_bind);
    free(m->node_parent);
    free(m->node_t);
    free(m->node_r);
    free(m->node_s);
    if (m->node_names) {
        for (int i = 0; i < m->node_count; i++)
            free(m->node_names[i]);
        free(m->node_names);
    }
    free(m);
}

/****************************************************************
 * Posing
 ****************************************************************/

/* Local transform of a node from the given local TRS arrays: T * R * S. */
static HMM_Mat4
node_local(const float *lt, const float *lr, const float *ls, int i)
{
    HMM_Mat4 t = HMM_Translate(HMM_V3(lt[i*3], lt[i*3+1], lt[i*3+2]));
    HMM_Quat q = HMM_Q(lr[i*4], lr[i*4+1], lr[i*4+2], lr[i*4+3]);
    HMM_Mat4 r = HMM_QToM4(q);
    HMM_Mat4 s = HMM_Scale(HMM_V3(ls[i*3], ls[i*3+1], ls[i*3+2]));
    return HMM_MulM4(t, HMM_MulM4(r, s));
}

/* Resolve a node's world matrix, memoizing up the parent chain. */
static HMM_Mat4
node_world(const struct model *m, const float *lt, const float *lr,
    const float *ls, int i, HMM_Mat4 *world, char *done)
{
    if (done[i])
        return world[i];
    HMM_Mat4 local = node_local(lt, lr, ls, i);
    int p = m->node_parent[i];
    world[i] = (p < 0) ? local
        : HMM_MulM4(node_world(m, lt, lr, ls, p, world, done), local);
    done[i] = 1;
    return world[i];
}

static void
pose_impl(const struct model *m, const float *lt, const float *lr,
    const float *ls, float *out)
{
    HMM_Mat4 *world = malloc(sizeof(HMM_Mat4) * m->node_count);
    char *done = calloc((size_t)m->node_count, 1);
    if (!world || !done) {
        /* Degrade to identity rather than crash. */
        for (int j = 0; j < m->joint_count; j++) {
            HMM_Mat4 id = HMM_M4D(1.0f);
            memcpy(&out[j * 16], &id, sizeof id);
        }
        free(world);
        free(done);
        return;
    }

    for (int i = 0; i < m->node_count; i++)
        node_world(m, lt, lr, ls, i, world, done);

    for (int j = 0; j < m->joint_count; j++) {
        HMM_Mat4 ibm;
        memcpy(&ibm, &m->inverse_bind[j * 16], sizeof ibm);
        HMM_Mat4 jm = HMM_MulM4(world[m->joint_nodes[j]], ibm);
        memcpy(&out[j * 16], &jm, sizeof jm);
    }

    free(world);
    free(done);
}

void
model_pose_joint_matrices(const struct model *m, float *out)
{
    pose_impl(m, m->node_t, m->node_r, m->node_s, out);
}

void
model_pose_from_local(const struct model *m, const float *lt, const float *lr,
    const float *ls, float *out)
{
    pose_impl(m, lt, lr, ls, out);
}
