/* anim.h : skeletal animation clips, retargeted onto a model by joint name.
 *
 * Clips come from a separate glTF (the Universal Animation Library) whose
 * skeleton shares joint names with the character. anim_load reads a chosen
 * subset of clips; a remap built from matching node names lets a clip drive
 * any model on the same rig. Sampling writes absolute TRS into the target
 * model's node arrays, which model_pose_joint_matrices then turns into the
 * joint palette. See doc/rendering.md.
 */
#ifndef ANIM_H
#define ANIM_H

#include "model.h"

enum { ANIM_T = 0, ANIM_R = 1, ANIM_S = 2 };     /* animated TRS path */
enum { ANIM_LINEAR = 0, ANIM_STEP = 1 };          /* keyframe interpolation */

/* One animated property of one source node: a keyframe track. */
struct anim_channel {
    int    node;        /* source-skeleton node index (into anim_set names) */
    int    path;        /* ANIM_T / ANIM_R / ANIM_S */
    int    interp;      /* ANIM_LINEAR / ANIM_STEP */
    int    comps;       /* 3 for T/S, 4 for R */
    int    key_count;
    float *times;       /* [key_count] seconds, ascending */
    float *values;      /* [key_count * comps] */
};

struct anim_clip {
    char                *name;
    float                duration;      /* seconds */
    struct anim_channel *channels;
    int                  channel_count;
};

/* A loaded set of clips plus the source skeleton's node names, so a clip can
 * be remapped onto a target model. */
struct anim_set {
    int                node_count;
    char             **node_names;      /* [node_count], may hold NULL */
    struct anim_clip  *clips;
    int                clip_count;
};

/* Load the named clips from a self-contained .glb animation library. Only
 * clips whose name is in wanted[] are kept (pass NULL/0 to load all). Returns
 * NULL on failure. Free with anim_free. */
struct anim_set *anim_load(const char *path, const char *const *wanted,
    int wanted_count);

/* Merge the named clips from a second .glb library into `set`. The two
 * libraries must be authored on the same skeleton (UAL1 and UAL2 are), since
 * each incoming channel's source node is translated by joint NAME into `set`'s
 * node table, appending any name the set does not already know. One remap then
 * drives every clip in the set, whichever file it came from. Call BEFORE
 * anim_build_remap: the node table may grow, which changes the remap size.
 * Returns the number of clips appended, or -1 on failure. */
int anim_append(struct anim_set *set, const char *path,
    const char *const *wanted, int wanted_count);

void anim_free(struct anim_set *set);

/* Find a loaded clip by exact name, or NULL. */
const struct anim_clip *anim_find(const struct anim_set *set, const char *name);

/* Fill remap[set->node_count] with, for each source node, the target model
 * node index sharing its name (or -1). Build once per (set, target) pair. */
void anim_build_remap(const struct anim_set *set, const struct model *target,
    int *remap);

/* Sample clip at time t (seconds; wrapped into [0, duration)) into the local
 * TRS arrays lt (3*node_count), lr (4*node_count), ls (3*node_count), through
 * remap. Only channels the clip animates are written, so pre-fill the arrays
 * with the bind pose first (memcpy from model node_t/r/s). node_count bounds
 * the target arrays. */
void anim_sample(const struct anim_clip *clip, float t, const int *remap,
    int node_count, float *lt, float *lr, float *ls);

/* Blend two local poses A and B into out, weight w in [0,1] (0 = A, 1 = B):
 * lerp T/S, slerp R. All arrays are node_count-sized; out may alias a or b. */
void anim_blend(int node_count, const float *at, const float *ar,
    const float *as, const float *bt, const float *br, const float *bs,
    float w, float *ot, float *or_, float *os);

#endif /* ANIM_H */
