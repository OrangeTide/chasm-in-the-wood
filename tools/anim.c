/* anim.c : skeletal animation clips, retargeted onto a model by joint name.
 *
 * Uses the cgltf reader (implemented in model.c) to read animation channels
 * from a glTF library; does not define CGLTF_IMPLEMENTATION itself.
 */
#include "anim.h"

#include "cgltf.h"
#include "HandmadeMath.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

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

static void *
read_file(const char *path, size_t *len_out)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long n = ftell(f);
    if (n < 0) { fclose(f); return NULL; }
    rewind(f);
    void *buf = malloc((size_t)n);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *len_out = (size_t)n;
    return buf;
}

static int
name_wanted(const char *name, const char *const *wanted, int wanted_count)
{
    if (!wanted || wanted_count == 0)
        return 1;
    if (!name)
        return 0;
    for (int i = 0; i < wanted_count; i++)
        if (wanted[i] && strcmp(name, wanted[i]) == 0)
            return 1;
    return 0;
}

/* Load one channel's keyframes from its cgltf sampler. Returns 0 on success. */
static int
load_channel(struct anim_channel *ch, const cgltf_animation_channel *src,
    const cgltf_data *gltf)
{
    memset(ch, 0, sizeof *ch);
    if (src->target_path == cgltf_animation_path_type_translation)
        ch->path = ANIM_T;
    else if (src->target_path == cgltf_animation_path_type_rotation)
        ch->path = ANIM_R;
    else if (src->target_path == cgltf_animation_path_type_scale)
        ch->path = ANIM_S;
    else
        return -1;      /* weights and unknowns are ignored */

    ch->node = (int)(src->target_node - gltf->nodes);
    ch->comps = ch->path == ANIM_R ? 4 : 3;

    const cgltf_animation_sampler *s = src->sampler;
    int cubic = s->interpolation == cgltf_interpolation_type_cubic_spline;
    ch->interp = s->interpolation == cgltf_interpolation_type_step
        ? ANIM_STEP : ANIM_LINEAR;   /* cubic is approximated as linear */

    ch->key_count = (int)s->input->count;
    ch->times = malloc(sizeof(float) * ch->key_count);
    ch->values = malloc(sizeof(float) * ch->key_count * ch->comps);
    if (!ch->times || !ch->values)
        return -1;

    int stride = cubic ? 3 : 1;   /* cubic output: in-tangent, value, out */
    int voff = cubic ? 1 : 0;
    for (int k = 0; k < ch->key_count; k++) {
        cgltf_accessor_read_float(s->input, (cgltf_size)k, &ch->times[k], 1);
        cgltf_accessor_read_float(s->output, (cgltf_size)(k * stride + voff),
            &ch->values[k * ch->comps], (cgltf_size)ch->comps);
    }
    return 0;
}

static int
load_clip(struct anim_clip *clip, const cgltf_animation *src,
    const cgltf_data *gltf)
{
    memset(clip, 0, sizeof *clip);
    clip->name = str_dup(src->name);
    clip->channels = calloc(src->channels_count, sizeof *clip->channels);
    if (!clip->channels)
        return -1;

    for (cgltf_size c = 0; c < src->channels_count; c++) {
        struct anim_channel *ch = &clip->channels[clip->channel_count];
        if (load_channel(ch, &src->channels[c], gltf) != 0)
            continue;
        if (ch->key_count > 0) {
            float last = ch->times[ch->key_count - 1];
            if (last > clip->duration)
                clip->duration = last;
        }
        clip->channel_count++;
    }
    return 0;
}

struct anim_set *
anim_load(const char *path, const char *const *wanted, int wanted_count)
{
    size_t len = 0;
    void *buf = read_file(path, &len);
    if (!buf) {
        fprintf(stderr, "anim_load: cannot read %s\n", path);
        return NULL;
    }

    cgltf_options options = {0};
    cgltf_data *gltf = NULL;
    if (cgltf_parse(&options, buf, len, &gltf) != cgltf_result_success ||
        cgltf_load_buffers(&options, gltf, NULL) != cgltf_result_success) {
        fprintf(stderr, "anim_load: cannot parse %s\n", path);
        cgltf_free(gltf);
        free(buf);
        return NULL;
    }

    struct anim_set *set = calloc(1, sizeof *set);
    if (!set)
        goto fail;

    set->node_count = (int)gltf->nodes_count;
    set->node_names = calloc((size_t)set->node_count, sizeof(char *));
    if (!set->node_names)
        goto fail;
    for (int i = 0; i < set->node_count; i++)
        set->node_names[i] = str_dup(gltf->nodes[i].name);

    set->clips = calloc(gltf->animations_count > 0 ? gltf->animations_count : 1,
        sizeof *set->clips);
    if (!set->clips)
        goto fail;
    for (cgltf_size a = 0; a < gltf->animations_count; a++) {
        if (!name_wanted(gltf->animations[a].name, wanted, wanted_count))
            continue;
        if (load_clip(&set->clips[set->clip_count], &gltf->animations[a],
                gltf) == 0)
            set->clip_count++;
    }

    cgltf_free(gltf);
    free(buf);
    return set;

fail:
    anim_free(set);
    cgltf_free(gltf);
    free(buf);
    return NULL;
}

/* The index of joint `name` in the set's node table, appending it when the set
 * has not seen it. Returns -1 if the name is missing or memory runs out. */
static int
set_node_index(struct anim_set *set, const char *name)
{
    if (!name)
        return -1;
    for (int i = 0; i < set->node_count; i++)
        if (set->node_names[i] && strcmp(set->node_names[i], name) == 0)
            return i;

    char **grown = realloc(set->node_names,
        sizeof(char *) * (size_t)(set->node_count + 1));
    if (!grown)
        return -1;
    set->node_names = grown;
    set->node_names[set->node_count] = str_dup(name);
    if (!set->node_names[set->node_count])
        return -1;
    return set->node_count++;
}

int
anim_append(struct anim_set *set, const char *path,
    const char *const *wanted, int wanted_count)
{
    if (!set)
        return -1;

    size_t len = 0;
    void *buf = read_file(path, &len);
    if (!buf) {
        fprintf(stderr, "anim_append: cannot read %s\n", path);
        return -1;
    }

    cgltf_options options = {0};
    cgltf_data *gltf = NULL;
    if (cgltf_parse(&options, buf, len, &gltf) != cgltf_result_success ||
        cgltf_load_buffers(&options, gltf, NULL) != cgltf_result_success) {
        fprintf(stderr, "anim_append: cannot parse %s\n", path);
        cgltf_free(gltf);
        free(buf);
        return -1;
    }

    /* Count the take first, so the clip array grows exactly once and the
     * pointers anim_find already handed out stay valid for the whole merge. */
    int take = 0;
    for (cgltf_size a = 0; a < gltf->animations_count; a++)
        if (name_wanted(gltf->animations[a].name, wanted, wanted_count))
            take++;

    int added = 0;
    int *xlat = NULL;
    if (take == 0)
        goto done;

    struct anim_clip *grown = realloc(set->clips,
        sizeof *set->clips * (size_t)(set->clip_count + take));
    if (!grown) {
        added = -1;
        goto done;
    }
    set->clips = grown;

    /* Translate the incoming skeleton's node indices into this set's table by
     * name, so the merged clips share the set's single remap. */
    xlat = malloc(sizeof(int) * (gltf->nodes_count ? gltf->nodes_count : 1));
    if (!xlat) {
        added = -1;
        goto done;
    }
    for (cgltf_size i = 0; i < gltf->nodes_count; i++)
        xlat[i] = set_node_index(set, gltf->nodes[i].name);

    for (cgltf_size a = 0; a < gltf->animations_count && added < take; a++) {
        if (!name_wanted(gltf->animations[a].name, wanted, wanted_count))
            continue;
        struct anim_clip *clip = &set->clips[set->clip_count + added];
        if (load_clip(clip, &gltf->animations[a], gltf) != 0)
            continue;
        for (int c = 0; c < clip->channel_count; c++) {
            int src = clip->channels[c].node;
            clip->channels[c].node =
                (src >= 0 && src < (int)gltf->nodes_count) ? xlat[src] : -1;
        }
        added++;
    }
    set->clip_count += added;

done:
    free(xlat);
    cgltf_free(gltf);
    free(buf);
    return added;
}

void
anim_free(struct anim_set *set)
{
    if (!set)
        return;
    for (int c = 0; c < set->clip_count; c++) {
        for (int i = 0; i < set->clips[c].channel_count; i++) {
            free(set->clips[c].channels[i].times);
            free(set->clips[c].channels[i].values);
        }
        free(set->clips[c].channels);
        free(set->clips[c].name);
    }
    free(set->clips);
    if (set->node_names) {
        for (int i = 0; i < set->node_count; i++)
            free(set->node_names[i]);
        free(set->node_names);
    }
    free(set);
}

const struct anim_clip *
anim_find(const struct anim_set *set, const char *name)
{
    for (int c = 0; c < set->clip_count; c++)
        if (set->clips[c].name && strcmp(set->clips[c].name, name) == 0)
            return &set->clips[c];
    return NULL;
}

void
anim_build_remap(const struct anim_set *set, const struct model *target,
    int *remap)
{
    for (int i = 0; i < set->node_count; i++) {
        remap[i] = -1;
        const char *nm = set->node_names[i];
        if (!nm)
            continue;
        for (int j = 0; j < target->node_count; j++) {
            if (target->node_names[j] &&
                strcmp(nm, target->node_names[j]) == 0) {
                remap[i] = j;
                break;
            }
        }
    }
}

/* Locate the keyframe segment for time t and its interpolation factor.
 * Sets *i0 and *i1 to the bracketing keys and *f to [0,1]. */
static void
find_segment(const struct anim_channel *ch, float t, int *i0, int *i1,
    float *f)
{
    if (ch->key_count <= 1 || t <= ch->times[0]) {
        *i0 = *i1 = 0;
        *f = 0.0f;
        return;
    }
    if (t >= ch->times[ch->key_count - 1]) {
        *i0 = *i1 = ch->key_count - 1;
        *f = 0.0f;
        return;
    }
    int i = 0;
    while (i + 1 < ch->key_count && ch->times[i + 1] <= t)
        i++;
    *i0 = i;
    *i1 = i + 1;
    float span = ch->times[i + 1] - ch->times[i];
    *f = span > 0.0f ? (t - ch->times[i]) / span : 0.0f;
    if (ch->interp == ANIM_STEP)
        *f = 0.0f;
}

void
anim_sample(const struct anim_clip *clip, float t, const int *remap,
    int node_count, float *lt, float *lr, float *ls)
{
    if (clip->duration > 0.0f) {
        t = fmodf(t, clip->duration);
        if (t < 0.0f)
            t += clip->duration;
    }

    for (int c = 0; c < clip->channel_count; c++) {
        const struct anim_channel *ch = &clip->channels[c];
        if (ch->node < 0)
            continue;           /* a merged clip whose joint name did not map */
        int tn = remap[ch->node];
        if (tn < 0 || tn >= node_count)
            continue;

        int i0, i1;
        float f;
        find_segment(ch, t, &i0, &i1, &f);
        const float *a = &ch->values[i0 * ch->comps];
        const float *b = &ch->values[i1 * ch->comps];

        if (ch->path == ANIM_R) {
            HMM_Quat qa = HMM_Q(a[0], a[1], a[2], a[3]);
            HMM_Quat qb = HMM_Q(b[0], b[1], b[2], b[3]);
            HMM_Quat q = HMM_SLerp(qa, f, qb);
            float *dst = &lr[tn * 4];
            dst[0] = q.X; dst[1] = q.Y; dst[2] = q.Z; dst[3] = q.W;
        } else {
            float *dst = (ch->path == ANIM_T) ? &lt[tn * 3] : &ls[tn * 3];
            for (int k = 0; k < 3; k++)
                dst[k] = a[k] + (b[k] - a[k]) * f;
        }
    }
}

void
anim_blend(int node_count, const float *at, const float *ar, const float *as,
    const float *bt, const float *br, const float *bs, float w,
    float *ot, float *or_, float *os)
{
    for (int i = 0; i < node_count; i++) {
        for (int k = 0; k < 3; k++) {
            ot[i*3+k] = at[i*3+k] + (bt[i*3+k] - at[i*3+k]) * w;
            os[i*3+k] = as[i*3+k] + (bs[i*3+k] - as[i*3+k]) * w;
        }
        HMM_Quat qa = HMM_Q(ar[i*4], ar[i*4+1], ar[i*4+2], ar[i*4+3]);
        HMM_Quat qb = HMM_Q(br[i*4], br[i*4+1], br[i*4+2], br[i*4+3]);
        HMM_Quat q = HMM_SLerp(qa, w, qb);
        or_[i*4] = q.X; or_[i*4+1] = q.Y; or_[i*4+2] = q.Z; or_[i*4+3] = q.W;
    }
}
