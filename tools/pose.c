/* pose: bake a rigged glTF character into a posed OBJ for the voxelizer.
 *
 * The character kits ship in the bind (T) pose, which voxelizes to a scarecrow.
 * This loads a self-contained .glb (mesh + skin + skeleton), retargets one clip
 * from an animation library (the Universal Animation Library, shared rig) by
 * joint name, samples it at a chosen time, skins the mesh on the CPU (linear
 * blend), and writes the posed mesh as an OBJ. The voxelizer then turns that
 * posed OBJ into a .vox like any other source.
 *
 * It reuses the glTF loader and the retargeting animator from the aldeby engine
 * (tools/model.*, tools/anim.*), which already drive these same Quaternius rigs.
 *
 * Usage:
 *   pose <model.glb> <out.obj> <anim.glb> <clip> <time> [<anim2.glb>]
 *
 * model.glb  the character or outfit to pose (its own mesh and skin)
 * out.obj    the posed mesh (an out.mtl is written beside it)
 * anim.glb   an animation library on the same rig (UAL1); its clips are read
 * clip       the clip name to pose, e.g. Armature|Idle_Loop
 * time       seconds into the clip (wrapped into its duration)
 * anim2.glb  optional second library merged in (UAL2), same rig
 */
#include "model.h"
#include "anim.h"
#include "HandmadeMath.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void list_clips(const struct anim_set *set)
{
    fprintf(stderr, "pose: available clips:\n");
    for (int i = 0; i < set->clip_count; i++)
        fprintf(stderr, "    %s\n", set->clips[i].name);
}

/* Derive the .mtl path from the .obj path (replace or append the extension). */
static void mtl_path(const char *obj, char *out, size_t n)
{
    snprintf(out, n, "%s", obj);
    size_t len = strlen(out);
    if (len > 4 && strcmp(out + len - 4, ".obj") == 0)
        strcpy(out + len - 4, ".mtl");
    else
        snprintf(out + len, n - len, ".mtl");
}

int main(int argc, char **argv)
{
    if (argc < 6) {
        fprintf(stderr, "usage: pose <model.glb> <out.obj> <anim.glb> <clip>"
            " <time> [<anim2.glb>]\n");
        return 2;
    }
    const char *modelPath = argv[1];
    const char *outPath   = argv[2];
    const char *animPath  = argv[3];
    const char *clipName  = argv[4];
    float       t         = (float)atof(argv[5]);
    const char *anim2Path = (argc >= 7) ? argv[6] : NULL;

    struct model *m = model_load(modelPath);
    if (!m) {
        fprintf(stderr, "pose: cannot load model %s\n", modelPath);
        return 1;
    }

    struct anim_set *set = anim_load(animPath, NULL, 0);
    if (!set) {
        fprintf(stderr, "pose: cannot load animations %s\n", animPath);
        return 1;
    }
    if (anim2Path)
        anim_append(set, anim2Path, NULL, 0);

    const struct anim_clip *clip = anim_find(set, clipName);
    if (!clip) {
        fprintf(stderr, "pose: no clip '%s' in %s\n", clipName, animPath);
        list_clips(set);
        return 1;
    }

    int nc = m->node_count;
    float *lt = malloc(sizeof(float) * 3 * nc);
    float *lr = malloc(sizeof(float) * 4 * nc);
    float *ls = malloc(sizeof(float) * 3 * nc);
    int   *remap = malloc(sizeof(int) * set->node_count);
    float *jm = malloc(sizeof(float) * 16 * m->joint_count);
    if (!lt || !lr || !ls || !remap || !jm) {
        fprintf(stderr, "pose: out of memory\n");
        return 1;
    }

    /* Start from the bind pose, then let the clip overwrite animated channels. */
    memcpy(lt, m->node_t, sizeof(float) * 3 * nc);
    memcpy(lr, m->node_r, sizeof(float) * 4 * nc);
    memcpy(ls, m->node_s, sizeof(float) * 3 * nc);

    anim_build_remap(set, m, remap);
    anim_sample(clip, t, remap, nc, lt, lr, ls);
    model_pose_from_local(m, lt, lr, ls, jm);

    char mtl[1024];
    mtl_path(outPath, mtl, sizeof mtl);
    const char *mtlBase = strrchr(mtl, '/');
    mtlBase = mtlBase ? mtlBase + 1 : mtl;

    FILE *fo = fopen(outPath, "w");
    FILE *fm = fopen(mtl, "w");
    if (!fo || !fm) {
        fprintf(stderr, "pose: cannot write %s\n", outPath);
        return 1;
    }
    fprintf(fo, "# posed by tools/pose from %s, clip %s @ %.3fs\n",
        modelPath, clipName, t);
    fprintf(fo, "mtllib %s\n", mtlBase);

    long vbase = 0, vtbase = 0;
    for (int pi = 0; pi < m->prim_count; pi++) {
        const struct model_prim *p = &m->prims[pi];

        /* Material: the base-colour texture when the primitive has one, else the
         * flat base colour. The voxelizer samples map_Kd or reads Kd. */
        fprintf(fm, "newmtl mat%d\n", pi);
        if (p->tex[0])
            fprintf(fm, "map_Kd %s\n", p->tex);
        else
            fprintf(fm, "Kd %f %f %f\n",
                p->base_color[0], p->base_color[1], p->base_color[2]);

        fprintf(fo, "usemtl mat%d\n", pi);

        /* Skinned vertex positions. */
        for (uint32_t v = 0; v < p->vertex_count; v++) {
            HMM_Vec4 src = HMM_V4(p->positions[v*3], p->positions[v*3+1],
                p->positions[v*3+2], 1.0f);
            HMM_Vec4 acc = HMM_V4(0, 0, 0, 0);
            float wsum = 0;
            for (int k = 0; k < 4; k++) {
                float wt = p->weights[v*4+k];
                if (wt == 0) continue;
                int ji = p->joints[v*4+k];
                HMM_Mat4 jmat;
                memcpy(&jmat, &jm[ji*16], sizeof jmat);
                HMM_Vec4 c = HMM_MulM4V4(jmat, src);
                acc.X += wt * c.X; acc.Y += wt * c.Y; acc.Z += wt * c.Z;
                wsum += wt;
            }
            if (wsum < 1e-6f) { acc.X = src.X; acc.Y = src.Y; acc.Z = src.Z; }
            fprintf(fo, "v %f %f %f\n", acc.X, acc.Y, acc.Z);
        }
        if (p->uv)
            for (uint32_t v = 0; v < p->vertex_count; v++)
                fprintf(fo, "vt %f %f\n", p->uv[v*2], p->uv[v*2+1]);

        /* Faces, indices made global and 1-based. */
        for (uint32_t i = 0; i + 2 < p->index_count; i += 3) {
            long a = vbase + p->indices[i]   + 1;
            long b = vbase + p->indices[i+1] + 1;
            long c = vbase + p->indices[i+2] + 1;
            if (p->uv) {
                long ta = vtbase + p->indices[i]   + 1;
                long tb = vtbase + p->indices[i+1] + 1;
                long tc = vtbase + p->indices[i+2] + 1;
                fprintf(fo, "f %ld/%ld %ld/%ld %ld/%ld\n", a, ta, b, tb, c, tc);
            } else {
                fprintf(fo, "f %ld %ld %ld\n", a, b, c);
            }
        }
        vbase += p->vertex_count;
        if (p->uv) vtbase += p->vertex_count;
    }
    fclose(fo);
    fclose(fm);

    fprintf(stderr, "pose: %s -> %s (%d prims, clip %s @ %.2fs, dur %.2fs)\n",
        modelPath, outPath, m->prim_count, clipName, t, clip->duration);
    return 0;
}
