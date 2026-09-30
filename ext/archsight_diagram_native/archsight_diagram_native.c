/*
 * Native kernels for the edge-routing hot loops (see lib/archsight/diagram/native.rb
 * for the Ruby side, which packs the inputs and unpacks the results).
 *
 * Every function here is a line-for-line port of its pure-Ruby reference
 * in lib/archsight/diagram/edge_router/path_metrics.rb and lib/archsight/diagram/edge_router.rb,
 * and must produce *identical* results -- not just close ones: routes are
 * chosen by strict `<` comparisons between float scores, and ties between
 * equally long candidates are common, so a last-ulp difference would
 * change which route gets drawn. That rules out FMA contraction (see
 * extconf.rb) and means every Ruby `sum` is reproduced with the same
 * Kahan-Babuska compensated summation Ruby's Array#sum / Enumerable#sum
 * use, nested the same way.
 *
 * Data crosses the Ruby/C boundary as packed binary strings, once per
 * call:
 *   points   -- native-endian doubles, x,y interleaved, every path back to back
 *   offsets  -- int32 per path + 1, each path's first point index (CSR style)
 *   table    -- doubles, BOX_STRIDE per obstacle box (see load_boxes)
 */
#include <ruby.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

/* ---- Kahan-Babuska summation, as Ruby's Array#sum / Enumerable#sum ---- */

typedef struct {
    double f, c;
} kb_sum;

static inline void
kb_add(kb_sum *s, double x)
{
    double t = s->f + x;

    if (fabs(s->f) >= fabs(x))
        s->c += ((s->f - t) + x);
    else
        s->c += ((x - t) + s->f);
    s->f = t;
}

static inline double
kb_value(const kb_sum *s)
{
    return s->f + s->c;
}

/* ---- packed-input access ---- */

typedef struct {
    const double *pts;     /* x,y interleaved */
    const int32_t *off;    /* npaths + 1 point offsets */
    long npaths;
    double *bbox;          /* lo_x, hi_x, lo_y, hi_y per path */
} paths_t;

static const void *
packed(VALUE str, long elem_size, long *count, const char *name)
{
    StringValue(str);
    long len = RSTRING_LEN(str);
    if (len % elem_size != 0)
        rb_raise(rb_eArgError, "%s: byte length %ld is not a multiple of %ld", name, len, elem_size);
    *count = len / elem_size;
    return RSTRING_PTR(str);
}

/* Validates the CSR offsets against the point buffer, so a malformed
 * input raises instead of reading out of bounds. Raises before anything
 * is allocated. */
static void
load_paths(paths_t *p, VALUE points, VALUE offsets)
{
    long ndoubles, noff;
    p->pts = packed(points, sizeof(double), &ndoubles, "points");
    p->off = packed(offsets, sizeof(int32_t), &noff, "offsets");
    if (ndoubles % 2 != 0)
        rb_raise(rb_eArgError, "points: odd number of coordinates");
    if (noff < 1 || p->off[0] != 0)
        rb_raise(rb_eArgError, "offsets: must start with 0");
    for (long i = 1; i < noff; i++)
        if (p->off[i] < p->off[i - 1])
            rb_raise(rb_eArgError, "offsets: not monotonic at %ld", i);
    if (p->off[noff - 1] != ndoubles / 2)
        rb_raise(rb_eArgError, "offsets: last offset %d != point count %ld", p->off[noff - 1], ndoubles / 2);
    p->npaths = noff - 1;
    p->bbox = NULL;
}

#define PX(p, i) ((p)->pts[2 * (long)(i)])
#define PY(p, i) ((p)->pts[2 * (long)(i) + 1])

/* PathMetrics.bounding_box. Only called for paths with >= 1 point: Ruby's
 * `minmax` of an empty path is nil and every caller would raise, so the
 * kernels reject one up front (see require_nonempty). */
static void
compute_bboxes(paths_t *p)
{
    p->bbox = ALLOC_N(double, 4 * (p->npaths > 0 ? p->npaths : 1));
    for (long k = 0; k < p->npaths; k++) {
        int32_t a = p->off[k], b = p->off[k + 1];
        double lo_x = PX(p, a), hi_x = lo_x, lo_y = PY(p, a), hi_y = lo_y;
        for (int32_t i = a + 1; i < b; i++) {
            double x = PX(p, i), y = PY(p, i);
            if (x < lo_x) lo_x = x;
            if (x > hi_x) hi_x = x;
            if (y < lo_y) lo_y = y;
            if (y > hi_y) hi_y = y;
        }
        double *bb = p->bbox + 4 * k;
        bb[0] = lo_x; bb[1] = hi_x; bb[2] = lo_y; bb[3] = hi_y;
    }
}

/* ---- PathMetrics ports ---- */

static inline int
close_p(double v1, double v2, double eps)
{
    return fabs(v1 - v2) <= eps;
}

/* [[a1, a2].min, [b1, b2].min].max etc. -- Array#min/#max keep the first
 * of two equal elements, which only matters for signed zeros and can't
 * change the resulting difference. */
static inline double
interval_overlap(double a1, double a2, double b1, double b2)
{
    double amin = a1 < a2 ? a1 : a2, amax = a1 > a2 ? a1 : a2;
    double bmin = b1 < b2 ? b1 : b2, bmax = b1 > b2 ? b1 : b2;
    double lo = amin > bmin ? amin : bmin;
    double hi = amax < bmax ? amax : bmax;
    double d = hi - lo;
    return d > 0.0 ? d : 0.0;
}

static inline double
collinear_overlap(double ax1, double ay1, double ax2, double ay2,
                  double bx1, double by1, double bx2, double by2, double eps)
{
    if (close_p(ax1, ax2, eps) && close_p(bx1, bx2, eps) && close_p(ax1, bx1, eps))
        return interval_overlap(ay1, ay2, by1, by2);
    if (close_p(ay1, ay2, eps) && close_p(by1, by2, eps) && close_p(ay1, by1, eps))
        return interval_overlap(ax1, ax2, bx1, bx2);
    return 0.0;
}

static inline int
segments_cross_p(double x1, double y1, double x2, double y2,
                 double x3, double y3, double x4, double y4)
{
    double denominator = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4));
    if (fabs(denominator) < 1e-9)
        return 0;

    double t = (((x1 - x3) * (y3 - y4)) - ((y1 - y3) * (x3 - x4))) / denominator;
    double u = (((x1 - x3) * (y1 - y2)) - ((y1 - y3) * (x1 - x2))) / denominator;

    return t > 1e-6 && t < 1.0 - 1e-6 && u > 1e-6 && u < 1.0 - 1e-6;
}

/* Liang-Barsky, as PathMetrics.segment_crosses_box?. `p[i] == 0.0` is
 * Float#zero? (true for -0.0 too), `q[i] < 0.0` is Float#negative?. */
static inline int
segment_crosses_box_p(double x1, double y1, double x2, double y2, const double *box)
{
    double dx = x2 - x1, dy = y2 - y1;
    double t0 = 0.0, t1 = 1.0;
    double p[4] = { -dx, dx, -dy, dy };
    double q[4] = { x1 - box[0], box[2] - x1, y1 - box[1], box[3] - y1 };

    for (int i = 0; i < 4; i++) {
        if (p[i] == 0.0) {
            if (q[i] < 0.0)
                return 0;
        } else {
            double t = q[i] / p[i];
            if (p[i] < 0.0) {
                if (t > t0) t0 = t;
            } else {
                if (t < t1) t1 = t;
            }
            if (t0 > t1)
                return 0;
        }
    }
    return 1;
}

/* PathMetrics.nearby_paths's per-sibling test. */
static inline int
bbox_near(const double *a, const double *o, double margin)
{
    return o[0] - margin <= a[1] && o[1] + margin >= a[0] && o[2] - margin <= a[3] && o[3] + margin >= a[2];
}

/* ---- obstacle box tables ---- */

/* A box table is BOX_STRIDE doubles per box, in the order ObstacleMap
 * holds them: left, top, right, bottom (Box's cached bounds) and x, y,
 * width, height (what Box#overlap_on computes from -- recomputing it from
 * the bounds could round differently). `excluded` is packed int32 box
 * indices to skip: the few ancestor boxes an ObstacleMap#excluding list
 * leaves out, so the full table can be packed once per render and shared
 * by every edge. */
#define BOX_STRIDE 8
enum { BX_LEFT, BX_TOP, BX_RIGHT, BX_BOTTOM, BX_X, BX_Y, BX_W, BX_H };

typedef struct {
    const double *b;
    long n;
    const int32_t *excluded;
    long nexcluded;
    unsigned char *skip; /* n flags, allocated by boxes_alloc_skip */
} boxes_t;

/* Validates only -- raises before anything is allocated. */
static void
load_boxes(boxes_t *bx, VALUE table, VALUE excluded)
{
    long ndoubles;
    bx->b = packed(table, sizeof(double), &ndoubles, "table");
    if (ndoubles % BOX_STRIDE != 0)
        rb_raise(rb_eArgError, "table: expected %d doubles per box", BOX_STRIDE);
    bx->n = ndoubles / BOX_STRIDE;
    bx->excluded = packed(excluded, sizeof(int32_t), &bx->nexcluded, "excluded");
    for (long i = 0; i < bx->nexcluded; i++)
        if (bx->excluded[i] < 0 || bx->excluded[i] >= bx->n)
            rb_raise(rb_eArgError, "excluded: index %d out of range", bx->excluded[i]);
    bx->skip = NULL;
}

static void
boxes_alloc_skip(boxes_t *bx)
{
    bx->skip = ALLOC_N(unsigned char, bx->n > 0 ? bx->n : 1);
    memset(bx->skip, 0, bx->n > 0 ? bx->n : 1);
    for (long i = 0; i < bx->nexcluded; i++)
        bx->skip[bx->excluded[i]] = 1;
}

#define BOX(bx, j) ((bx)->b + BOX_STRIDE * (long)(j))

/* ---- Kernels.crossing_counts: PathMetrics.crossing_count per path ---- */

/*
 * crossing_counts(points, offsets, table, excluded) -> packed int32 per path
 *
 * How many (segment, box) pairs each path draws through, for one edge's
 * candidate paths against the table's boxes minus `excluded`.
 */
static VALUE
rb_crossing_counts(VALUE self, VALUE points, VALUE offsets, VALUE table, VALUE excluded)
{
    paths_t p;
    boxes_t bx;
    load_paths(&p, points, offsets);
    load_boxes(&bx, table, excluded);

    VALUE out = rb_str_new(NULL, (long)sizeof(int32_t) * p.npaths);
    int32_t *counts = (int32_t *)RSTRING_PTR(out);

    /* No Ruby calls (and so no possible raise/longjmp) from here on, so
     * the scratch buffers can't leak. */
    boxes_alloc_skip(&bx);
    long *relevant = ALLOC_N(long, bx.n > 0 ? bx.n : 1);

    for (long k = 0; k < p.npaths; k++) {
        int32_t a = p.off[k], b = p.off[k + 1];
        int32_t count = 0;

        if (bx.n > bx.nexcluded && b > a) {
            /* nearby_obstacles: the whole path's bounding box first ... */
            double lo_x = PX(&p, a), hi_x = lo_x, lo_y = PY(&p, a), hi_y = lo_y;
            for (int32_t i = a + 1; i < b; i++) {
                double x = PX(&p, i), y = PY(&p, i);
                if (x < lo_x) lo_x = x;
                if (x > hi_x) hi_x = x;
                if (y < lo_y) lo_y = y;
                if (y > hi_y) hi_y = y;
            }
            long nrel = 0;
            for (long j = 0; j < bx.n; j++) {
                const double *o = BOX(&bx, j);
                if (!bx.skip[j] && o[BX_LEFT] <= hi_x && o[BX_RIGHT] >= lo_x && o[BX_TOP] <= hi_y && o[BX_BOTTOM] >= lo_y)
                    relevant[nrel++] = j;
            }

            /* ... then each segment's own bounding box, then Liang-Barsky. */
            for (int32_t i = a; i + 1 < b; i++) {
                double x1 = PX(&p, i), y1 = PY(&p, i), x2 = PX(&p, i + 1), y2 = PY(&p, i + 1);
                double slo_x = x1 < x2 ? x1 : x2, shi_x = x1 < x2 ? x2 : x1;
                double slo_y = y1 < y2 ? y1 : y2, shi_y = y1 < y2 ? y2 : y1;
                for (long r = 0; r < nrel; r++) {
                    const double *o = BOX(&bx, relevant[r]);
                    if (o[BX_LEFT] <= shi_x && o[BX_RIGHT] >= slo_x && o[BX_TOP] <= shi_y && o[BX_BOTTOM] >= slo_y &&
                        segment_crosses_box_p(x1, y1, x2, y2, o))
                        count++;
                }
            }
        }
        counts[k] = count;
    }

    xfree(relevant);
    xfree(bx.skip);
    return out;
}

/* ---- Kernels.path_lengths: Geometry.path_length per path ---- */

/*
 * path_lengths(points, offsets) -> packed double per path
 *
 * `points.each_cons(2).sum { |a, b| Math.hypot(...) }`: one Kahan-Babuska
 * accumulator per path, as Enumerable#sum. A path with fewer than two
 * points sums nothing (Ruby's Integer 0; the caller restores that).
 */
static VALUE
rb_path_lengths(VALUE self, VALUE points, VALUE offsets)
{
    paths_t p;
    load_paths(&p, points, offsets);

    VALUE out = rb_str_new(NULL, (long)sizeof(double) * p.npaths);
    double *lengths = (double *)RSTRING_PTR(out);

    for (long k = 0; k < p.npaths; k++) {
        kb_sum sum = { 0.0, 0.0 };
        for (int32_t i = p.off[k]; i + 1 < p.off[k + 1]; i++)
            kb_add(&sum, hypot(PX(&p, i + 1) - PX(&p, i), PY(&p, i + 1) - PY(&p, i)));
        lengths[k] = kb_value(&sum);
    }
    return out;
}

/* ---- Kernels.path_turns: Geometry.turn_count per path ---- */

/*
 * path_turns(points, offsets) -> packed int32 per path
 *
 * The interior points where the two adjoining segments aren't collinear:
 * |(x2 - x1) * (y3 - y2) - (y2 - y1) * (x3 - x2)| > 1e-6, the very
 * expression (and operation order, no fused multiply-add) `Geometry.turn_count`
 * evaluates. A path with fewer than three points has none.
 */
static VALUE
rb_path_turns(VALUE self, VALUE points, VALUE offsets)
{
    paths_t p;
    load_paths(&p, points, offsets);

    VALUE out = rb_str_new(NULL, (long)sizeof(int32_t) * p.npaths);
    int32_t *turns = (int32_t *)RSTRING_PTR(out);

    for (long k = 0; k < p.npaths; k++) {
        int32_t count = 0;
        for (int32_t i = p.off[k]; i + 2 < p.off[k + 1]; i++) {
            double x1 = PX(&p, i), y1 = PY(&p, i);
            double x2 = PX(&p, i + 1), y2 = PY(&p, i + 1);
            double x3 = PX(&p, i + 2), y3 = PY(&p, i + 2);
            if (fabs(((x2 - x1) * (y3 - y2)) - ((y2 - y1) * (x3 - x2))) > 1e-6)
                count++;
        }
        turns[k] = count;
    }
    return out;
}

/* ---- Kernels.bridge_scan: BridgePath.bridge_candidates's obstacle scans ---- */

/* Box#overlap_on(axis, other) > 0 (overlaps_x? / overlaps_y?), with its
 * `gap:` default of 0.0 kept in the sum. */
static inline int
overlaps_on(double size_a, double pos_a, double size_o, double pos_o)
{
    return (((size_a + size_o) / 2.0) + 0.0 - fabs(pos_a - pos_o)) > 0.0;
}

/*
 * bridge_scan(a, b, table, excluded) -> packed 8 doubles
 *
 * a, b: BOX_STRIDE doubles each, the route's two endpoint boxes. Returns
 *   [0..3] BridgePath.stub_length's smallest `gap_to` a facing obstacle
 *          for exit sides left, right, top, bottom -- +Infinity when no
 *          obstacle faces that side (Ruby then uses BRIDGE_STUB as is);
 *   [4..7] min top, max bottom, min left, max right over
 *          `[a, b] + nearby_obstacles(a, b, obstacles)`.
 */
static VALUE
rb_bridge_scan(VALUE self, VALUE a_str, VALUE b_str, VALUE table, VALUE excluded)
{
    long na, nb;
    const double *a = packed(a_str, sizeof(double), &na, "a");
    const double *b = packed(b_str, sizeof(double), &nb, "b");
    if (na != BOX_STRIDE || nb != BOX_STRIDE)
        rb_raise(rb_eArgError, "a, b: expected %d doubles each", BOX_STRIDE);
    boxes_t bx;
    load_boxes(&bx, table, excluded);

    VALUE out = rb_str_new(NULL, (long)sizeof(double) * 8);
    double *r = (double *)RSTRING_PTR(out);

    /* No Ruby calls (and so no possible raise/longjmp) from here on. */
    boxes_alloc_skip(&bx);

    double gap_left = INFINITY, gap_right = INFINITY, gap_top = INFINITY, gap_bottom = INFINITY;

    /* nearby_obstacles's span (strict test below), and the extremes
     * starting from `[a, b]` themselves. */
    double lo_x = a[BX_LEFT] < b[BX_LEFT] ? a[BX_LEFT] : b[BX_LEFT];
    double hi_x = a[BX_RIGHT] > b[BX_RIGHT] ? a[BX_RIGHT] : b[BX_RIGHT];
    double lo_y = a[BX_TOP] < b[BX_TOP] ? a[BX_TOP] : b[BX_TOP];
    double hi_y = a[BX_BOTTOM] > b[BX_BOTTOM] ? a[BX_BOTTOM] : b[BX_BOTTOM];
    double min_top = lo_y, max_bottom = hi_y, min_left = lo_x, max_right = hi_x;

    for (long j = 0; j < bx.n; j++) {
        if (bx.skip[j])
            continue;
        const double *o = BOX(&bx, j);

        /* stub_length: facing_obstacle? / gap_to, per exit side. */
        int over_y = overlaps_on(a[BX_H], a[BX_Y], o[BX_H], o[BX_Y]);
        int over_x = overlaps_on(a[BX_W], a[BX_X], o[BX_W], o[BX_X]);
        if (o[BX_RIGHT] <= a[BX_LEFT] && over_y) {
            double g = a[BX_LEFT] - o[BX_RIGHT];
            if (g < gap_left) gap_left = g;
        }
        if (o[BX_LEFT] >= a[BX_RIGHT] && over_y) {
            double g = o[BX_LEFT] - a[BX_RIGHT];
            if (g < gap_right) gap_right = g;
        }
        if (o[BX_BOTTOM] <= a[BX_TOP] && over_x) {
            double g = a[BX_TOP] - o[BX_BOTTOM];
            if (g < gap_top) gap_top = g;
        }
        if (o[BX_TOP] >= a[BX_BOTTOM] && over_x) {
            double g = o[BX_TOP] - a[BX_BOTTOM];
            if (g < gap_bottom) gap_bottom = g;
        }

        /* nearby_obstacles (strict) -> the bridge loop's extremes. */
        if (o[BX_LEFT] < hi_x && o[BX_RIGHT] > lo_x && o[BX_TOP] < hi_y && o[BX_BOTTOM] > lo_y) {
            if (o[BX_TOP] < min_top) min_top = o[BX_TOP];
            if (o[BX_BOTTOM] > max_bottom) max_bottom = o[BX_BOTTOM];
            if (o[BX_LEFT] < min_left) min_left = o[BX_LEFT];
            if (o[BX_RIGHT] > max_right) max_right = o[BX_RIGHT];
        }
    }

    r[0] = gap_left; r[1] = gap_right; r[2] = gap_top; r[3] = gap_bottom;
    r[4] = min_top; r[5] = max_bottom; r[6] = min_left; r[7] = max_right;

    xfree(bx.skip);
    return out;
}

/* ---- Kernels.rect_overlap_counts: LabelPlacer#label_overlap_score ---- */

/* LabelPlacer.rects_intersect?(q, o): strict on every side, so rectangles
 * that merely share an edge don't count. `q` and `o` both start with
 * left, top, right, bottom. */
static inline int
rects_intersect_p(const double *q, const double *o)
{
    return q[0] < o[2] && q[2] > o[0] && q[1] < o[3] && q[3] > o[1];
}

/*
 * rect_overlap_counts(queries, table, placed) -> packed int32 per query
 *
 * queries, placed: 4 doubles (left, top, right, bottom) per rectangle;
 * table: node boxes, BOX_STRIDE doubles each. Each count is how many node
 * boxes plus how many placed rectangles that query intersects.
 */
static VALUE
rb_rect_overlap_counts(VALUE self, VALUE queries, VALUE table, VALUE placed)
{
    long nq, nt, np;
    const double *q = packed(queries, sizeof(double), &nq, "queries");
    const double *t = packed(table, sizeof(double), &nt, "table");
    const double *pl = packed(placed, sizeof(double), &np, "placed");
    if (nq % 4 != 0 || np % 4 != 0)
        rb_raise(rb_eArgError, "queries, placed: expected 4 doubles per rectangle");
    if (nt % BOX_STRIDE != 0)
        rb_raise(rb_eArgError, "table: expected %d doubles per box", BOX_STRIDE);
    nq /= 4; np /= 4; nt /= BOX_STRIDE;

    VALUE out = rb_str_new(NULL, (long)sizeof(int32_t) * nq);
    int32_t *counts = (int32_t *)RSTRING_PTR(out);

    for (long i = 0; i < nq; i++) {
        const double *qi = q + 4 * i;
        int32_t count = 0;
        for (long j = 0; j < nt; j++)
            count += rects_intersect_p(qi, t + BOX_STRIDE * j);
        for (long j = 0; j < np; j++)
            count += rects_intersect_p(qi, pl + 4 * j);
        counts[i] = count;
    }
    return out;
}

/* ---- Kernels.path_rect_hits: LabelPlacer#path_hit_counts ---- */

/*
 * path_rect_hits(points, offsets, rects, own) -> packed int32 per rect
 *
 * rects: 4 doubles (left, top, right, bottom) per rectangle. Each count
 * is how many paths -- all but path index `own` (-1 for none) -- have a
 * segment crossing that rectangle: the segment's bounding box touching it
 * (inclusive), then Liang-Barsky, as LabelPlacer#path_hits?.
 */
static VALUE
rb_path_rect_hits(VALUE self, VALUE points, VALUE offsets, VALUE rects, VALUE own_v)
{
    paths_t p;
    long nr;
    load_paths(&p, points, offsets);
    const double *r = packed(rects, sizeof(double), &nr, "rects");
    if (nr % 4 != 0)
        rb_raise(rb_eArgError, "rects: expected 4 doubles per rectangle");
    nr /= 4;
    long own = NUM2LONG(own_v);

    VALUE out = rb_str_new(NULL, (long)sizeof(int32_t) * nr);
    int32_t *counts = (int32_t *)RSTRING_PTR(out);

    for (long j = 0; j < nr; j++) {
        const double *rj = r + 4 * j;
        int32_t count = 0;
        for (long k = 0; k < p.npaths; k++) {
            if (k == own)
                continue;
            for (int32_t i = p.off[k]; i + 1 < p.off[k + 1]; i++) {
                double x1 = PX(&p, i), y1 = PY(&p, i), x2 = PX(&p, i + 1), y2 = PY(&p, i + 1);
                double slo_x = x1 < x2 ? x1 : x2, shi_x = x1 < x2 ? x2 : x1;
                double slo_y = y1 < y2 ? y1 : y2, shi_y = y1 < y2 ? y2 : y1;
                if (shi_x >= rj[0] && slo_x <= rj[2] && shi_y >= rj[1] && slo_y <= rj[3] &&
                    segment_crosses_box_p(x1, y1, x2, y2, rj)) {
                    count++;
                    break;
                }
            }
        }
        counts[j] = count;
    }
    return out;
}

/* ---- EdgeRouter.select_best, shared by Kernels.refine and Kernels.select_best ---- */

typedef struct {
    double edge_epsilon, crossing_penalty, overlap_tie_tolerance, line_overlap_penalty, line_crossing_penalty;
} params_t;

/* params: [edge_epsilon, crossing_penalty, overlap_tie_tolerance,
 *          line_overlap_penalty, line_crossing_penalty] */
static void
load_params(params_t *pr, VALUE params)
{
    Check_Type(params, T_ARRAY);
    if (RARRAY_LEN(params) != 5)
        rb_raise(rb_eArgError, "params: expected 5 values");
    pr->edge_epsilon = NUM2DBL(rb_ary_entry(params, 0));
    pr->crossing_penalty = NUM2DBL(rb_ary_entry(params, 1));
    pr->overlap_tie_tolerance = NUM2DBL(rb_ary_entry(params, 2));
    pr->line_overlap_penalty = NUM2DBL(rb_ary_entry(params, 3));
    pr->line_crossing_penalty = NUM2DBL(rb_ary_entry(params, 4));
}

/* The `sibling_paths` a candidate is scored against, in order: either
 * every path in `paths` (Kernels.select_best), or -- when `choice` is set
 * -- each edge's currently chosen path in `paths` except edge `skip`'s own
 * (Kernels.refine, whose candidates and siblings share one buffer). */
typedef struct {
    const paths_t *paths;
    const int32_t *choice;
    long slots;     /* paths->npaths, or the edge count when `choice` is set */
    long skip;      /* excluded slot, or -1 */
    long *relevant; /* scratch, `slots` long */
} siblings_t;

static inline long
sibling_count(const siblings_t *s)
{
    return s->slots - (s->skip >= 0 ? 1 : 0);
}

/* PathMetrics.nearby_paths: writes the surviving siblings' path indices
 * (into s->paths) to s->relevant, in sibling order. */
static long
gather_relevant(siblings_t *s, const double *cand_bb, double margin)
{
    long n = 0;
    for (long k = 0; k < s->slots; k++) {
        if (k == s->skip)
            continue;
        long other = s->choice ? s->choice[k] : k;
        if (bbox_near(cand_bb, s->paths->bbox + 4 * other, margin))
            s->relevant[n++] = other;
    }
    return n;
}

/* PathMetrics.overlap_length -- the three nested `sum`s (path segments,
 * siblings, sibling segments) each get their own Kahan-Babuska
 * accumulator, finalized before being added to the enclosing one, exactly
 * as the Ruby blocks return their own sums. */
static double
overlap_length(const paths_t *p, long cand, siblings_t *s, double eps)
{
    if (sibling_count(s) == 0)
        return 0.0;
    long nrel = gather_relevant(s, p->bbox + 4 * cand, eps);
    if (nrel == 0)
        return 0.0;

    const paths_t *q = s->paths;
    kb_sum outer = { 0.0, 0.0 };
    for (int32_t i = p->off[cand]; i + 1 < p->off[cand + 1]; i++) {
        double ax1 = PX(p, i), ay1 = PY(p, i), ax2 = PX(p, i + 1), ay2 = PY(p, i + 1);
        kb_sum mid = { 0.0, 0.0 };
        for (long r = 0; r < nrel; r++) {
            long other = s->relevant[r];
            kb_sum inner = { 0.0, 0.0 };
            for (int32_t j = q->off[other]; j + 1 < q->off[other + 1]; j++)
                kb_add(&inner, collinear_overlap(ax1, ay1, ax2, ay2,
                                                 PX(q, j), PY(q, j), PX(q, j + 1), PY(q, j + 1), eps));
            kb_add(&mid, kb_value(&inner));
        }
        kb_add(&outer, kb_value(&mid));
    }
    return kb_value(&outer);
}

/* PathMetrics.crossing_edges_count. */
static long
crossing_edges_count(const paths_t *p, long cand, siblings_t *s)
{
    if (sibling_count(s) == 0)
        return 0;
    long nrel = gather_relevant(s, p->bbox + 4 * cand, 0.0);

    const paths_t *q = s->paths;
    long count = 0;
    for (int32_t i = p->off[cand]; i + 1 < p->off[cand + 1]; i++) {
        double ax1 = PX(p, i), ay1 = PY(p, i), ax2 = PX(p, i + 1), ay2 = PY(p, i + 1);
        for (long r = 0; r < nrel; r++) {
            long other = s->relevant[r];
            for (int32_t j = q->off[other]; j + 1 < q->off[other + 1]; j++)
                count += segments_cross_p(ax1, ay1, ax2, ay2, PX(q, j), PY(q, j), PX(q, j + 1), PY(q, j + 1));
        }
    }
    return count;
}

/* EdgeRouter.select_best over candidates [lo, hi) of `p` (with their
 * `crossing`/`length` scores, indexed the same way) against `s`. Returns
 * the chosen candidate's index, or -1 if none scored below infinity
 * (only possible with NaN input; Ruby would return nil). */
static long
select_best(const paths_t *p, long lo, long hi, const int32_t *crossing, const double *length,
            siblings_t *s, const params_t *pr)
{
    int32_t min_crossing = crossing[lo];
    double best_primary = (crossing[lo] * pr->crossing_penalty) + length[lo];
    for (long c = lo + 1; c < hi; c++) {
        double primary = (crossing[c] * pr->crossing_penalty) + length[c];
        if (crossing[c] < min_crossing) min_crossing = crossing[c];
        if (primary < best_primary) best_primary = primary;
    }

    long best = -1;
    double best_score = INFINITY;
    for (long c = lo; c < hi; c++) {
        double primary = (crossing[c] * pr->crossing_penalty) + length[c];
        if (!(crossing[c] == min_crossing || primary <= best_primary + pr->overlap_tie_tolerance))
            continue;
        if (primary >= best_score)
            continue;

        double score = (overlap_length(p, c, s, pr->edge_epsilon) * pr->line_overlap_penalty) +
                       ((double)crossing_edges_count(p, c, s) * pr->line_crossing_penalty) +
                       primary;
        if (!(score < best_score))
            continue;

        best_score = score;
        best = c;
    }
    return best;
}

/* Raises unless every path in `p` has at least one point (Ruby's
 * `bounding_box` of an empty path would raise too). */
static void
require_nonempty(const paths_t *p, const char *name)
{
    for (long k = 0; k < p->npaths; k++)
        if (p->off[k + 1] == p->off[k])
            rb_raise(rb_eArgError, "%s: path %ld has no points", name, k);
}

/* Array#!= between two candidates' point lists. */
static int
same_points(const paths_t *p, long a, long b)
{
    if (a == b)
        return 1;
    int32_t na = p->off[a + 1] - p->off[a], nb = p->off[b + 1] - p->off[b];
    if (na != nb)
        return 0;
    for (long i = 0; i < 2L * na; i++)
        if (p->pts[2L * p->off[a] + i] != p->pts[2L * p->off[b] + i])
            return 0;
    return 1;
}

/* ---- Kernels.select_best: EdgeRouter.select_best for one edge ---- */

/*
 * select_best(points, offsets, crossings, lengths, sibling_points, sibling_offsets, params)
 *   -> Integer index of the chosen candidate, or nil
 *
 * points/offsets: the edge's scored candidates, in order;
 * crossings: int32 per candidate; lengths: double per candidate;
 * sibling_points/sibling_offsets: the sibling paths, in order;
 * params: as for refine.
 */
static VALUE
rb_select_best(VALUE self, VALUE points, VALUE offsets, VALUE crossings, VALUE lengths,
               VALUE sibling_points, VALUE sibling_offsets, VALUE params)
{
    paths_t cand, sib;
    params_t pr;
    long ncross, nlen;
    load_paths(&cand, points, offsets);
    load_paths(&sib, sibling_points, sibling_offsets);
    const int32_t *crossing = packed(crossings, sizeof(int32_t), &ncross, "crossings");
    const double *length = packed(lengths, sizeof(double), &nlen, "lengths");
    load_params(&pr, params);

    if (cand.npaths < 1)
        rb_raise(rb_eArgError, "offsets: no candidates");
    if (ncross != cand.npaths || nlen != cand.npaths)
        rb_raise(rb_eArgError, "crossings/lengths: expected %ld entries", cand.npaths);
    require_nonempty(&cand, "offsets");
    require_nonempty(&sib, "sibling_offsets");

    /* No Ruby calls (and so no possible raise/longjmp) from here on, so
     * the scratch buffers can't leak. */
    compute_bboxes(&cand);
    compute_bboxes(&sib);
    siblings_t s = { &sib, NULL, sib.npaths, -1, ALLOC_N(long, sib.npaths > 0 ? sib.npaths : 1) };

    long best = select_best(&cand, 0, cand.npaths, crossing, length, &s, &pr);

    xfree(s.relevant);
    xfree(sib.bbox);
    xfree(cand.bbox);
    return best < 0 ? Qnil : LONG2NUM(best);
}

/* ---- Kernels.refine: EdgeRouting#refine_line_overlap! ---- */

/*
 * refine(points, offsets, edge_offsets, crossings, lengths, choices, rounds, params)
 *   -> packed int32, the chosen global candidate index per edge
 *
 * points/offsets: every edge's scored candidates, edge by edge;
 * edge_offsets: int32 per edge + 1, each edge's first candidate index;
 * crossings: int32 per candidate; lengths: double per candidate;
 * choices: int32 per edge, its current (global) candidate index;
 * params: [edge_epsilon, crossing_penalty, overlap_tie_tolerance,
 *          line_overlap_penalty, line_crossing_penalty].
 */
static VALUE
rb_refine(VALUE self, VALUE points, VALUE offsets, VALUE edge_offsets, VALUE crossings,
          VALUE lengths, VALUE choices, VALUE rounds, VALUE params)
{
    paths_t cand;
    params_t pr;
    long neo, ncross, nlen, nchoice;
    load_paths(&cand, points, offsets);
    const int32_t *edge_off = packed(edge_offsets, sizeof(int32_t), &neo, "edge_offsets");
    const int32_t *crossing = packed(crossings, sizeof(int32_t), &ncross, "crossings");
    const double *length = packed(lengths, sizeof(double), &nlen, "lengths");
    const int32_t *initial = packed(choices, sizeof(int32_t), &nchoice, "choices");
    long nrounds = NUM2LONG(rounds);
    load_params(&pr, params);

    long ncand = cand.npaths;
    long nedges = neo - 1;
    if (neo < 1 || edge_off[0] != 0 || edge_off[neo - 1] != ncand)
        rb_raise(rb_eArgError, "edge_offsets: must span 0..%ld", ncand);
    for (long e = 0; e < nedges; e++)
        if (edge_off[e + 1] <= edge_off[e])
            rb_raise(rb_eArgError, "edge_offsets: edge %ld has no candidates", e);
    if (ncross != ncand || nlen != ncand)
        rb_raise(rb_eArgError, "crossings/lengths: expected %ld entries", ncand);
    if (nchoice != nedges)
        rb_raise(rb_eArgError, "choices: expected %ld entries", nedges);
    for (long e = 0; e < nedges; e++)
        if (initial[e] < edge_off[e] || initial[e] >= edge_off[e + 1])
            rb_raise(rb_eArgError, "choices: edge %ld's choice is not one of its own candidates", e);
    require_nonempty(&cand, "offsets");

    VALUE out = rb_str_new((const char *)initial, (long)sizeof(int32_t) * nedges);
    int32_t *choice = (int32_t *)RSTRING_PTR(out);

    /* No Ruby calls (and so no possible raise/longjmp) from here on, so
     * the scratch buffers can't leak. */
    compute_bboxes(&cand);
    siblings_t s = { &cand, choice, nedges, -1, ALLOC_N(long, nedges > 0 ? nedges : 1) };

    for (long round = 0; round < nrounds; round++) {
        int changed = 0;
        for (long e = 0; e < nedges; e++) {
            s.skip = e;
            long picked = select_best(&cand, edge_off[e], edge_off[e + 1], crossing, length, &s, &pr);
            if (picked < 0)
                continue; /* NaN scores only; keep the current route */
            if (!same_points(&cand, picked, choice[e]))
                changed = 1;
            choice[e] = (int32_t)picked;
        }
        if (!changed)
            break;
    }

    xfree(s.relevant);
    xfree(cand.bbox);
    return out;
}

void
Init_archsight_diagram_native(void)
{
    VALUE archsight = rb_define_module("Archsight");
    VALUE diagram = rb_define_module_under(archsight, "Diagram");
    VALUE native = rb_define_module_under(diagram, "Native");
    VALUE kernels = rb_define_module_under(native, "Kernels");

    rb_define_module_function(kernels, "crossing_counts", rb_crossing_counts, 4);
    rb_define_module_function(kernels, "path_lengths", rb_path_lengths, 2);
    rb_define_module_function(kernels, "path_turns", rb_path_turns, 2);
    rb_define_module_function(kernels, "bridge_scan", rb_bridge_scan, 4);
    rb_define_module_function(kernels, "rect_overlap_counts", rb_rect_overlap_counts, 3);
    rb_define_module_function(kernels, "path_rect_hits", rb_path_rect_hits, 4);
    rb_define_module_function(kernels, "select_best", rb_select_best, 7);
    rb_define_module_function(kernels, "refine", rb_refine, 8);
}
