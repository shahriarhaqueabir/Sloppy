# src/Slop.Frame.ps1
# S.L.O.P. organic frame engine. Pure C# geometry: no WPF types, safe to dot-source headlessly.
# Kept separate from the OpenCode/permission/lifecycle stack on purpose - it only emits path data.
#
# Design notes (from the standalone Slop-Frame demo):
#   * A ring of N points sits on a rounded rectangle. Each point has a spring offset coupled to
#     its neighbours, so disturbances travel around the ring like ripples and settle.
#   * All coordinates are WINDOW space: content size + Margin on every side leaves room for goo.
#   * Outward bulge is tanh-saturated by the margin and every point is hard-clamped inside the
#     window, so an expanding/overshooting silhouette can never be sliced by the window edge.
#   * Path data only. PowerShell/WPF owns Geometry.Parse and the visual tree.
$ErrorActionPreference = 'Stop'

$csSource = @'
using System;
using System.Globalization;
using System.Text;

public sealed class SlopFrame
{
    const int N = 48;   // ~1 ring point per 40-50px at 760x540; 16 cut the corners badly
    public const int Version = 4;   // bump when the type shape or motion behaviour changes; see load guard below
    public const int Idle = 0, Thinking = 1, Alert = 2, Happy = 3;

    public readonly float Margin;          // free space between content rect and window edge
    public float Stroke = 5f;              // stroke thickness used by the Path (edge safety only)
    public float Roundness = 0.22f;        // corner radius = Roundness * min(halfW, halfH) when open
    public float OutLimit;                 // max outward bulge in px (soft-saturating)
    public float InLimit = 6f;             // max inward dent in px
    public float MotionScale = 1f;         // 0 = reduced motion: waves, kicks and pokes are disabled

    float fw, fh;                          // target content size
    float cw, cwv, ch, chv;                // current (spring) size
    float open, openV, openT;              // 0 = blob at origin, 1 = full frame
    float ox, oy;                          // growth origin (the pea), window coords
    bool splashed;

    readonly float[] off = new float[N], vel = new float[N];
    // Static per-instance asymmetry. cos(th) bulges the right side and dents
    // the left, giving a stable left/right area difference at rest; the other
    // harmonics add diagonal/fine character. Travelling waves are dynamic
    // (phase1/phase2 in Step) and stay layered on top of this field.
    readonly float[] asym = new float[N];
    readonly float[] px = new float[N], py = new float[N];          // last built outline (window coords)
    readonly float[] nx = new float[N], ny = new float[N];          // last base outward normals

    int mood;
    float time, acc, phase1, phase2;
    float wx, wy, pwx, pwy, vxS, vyS, pvxS, pvyS, ax, ay;
    bool haveWin;
    readonly Random rng;

    public string Path = "", Highlight = "";
    public float ContentOpacity;
    public bool IsClosed { get { return open < 0.02f && openT == 0f && Math.Abs(openV) < 0.05f; } }

    public SlopFrame(float contentW, float contentH, float margin, int seed)
    {
        Margin = margin; fw = cw = contentW; fh = ch = contentH;
        OutLimit = Math.Max(2f, margin - Stroke * 0.5f - 3f);
        rng = new Random(seed);
        float pa = R() * 6.2831853f, pb = R() * 6.2831853f;
        float k = 2.0f + 0.6f * R();
        for (int i = 0; i < N; i++)
        {
            float th = 6.2831853f * i / N;
            // cos(th) is the lowest basis with a non-zero integral over one
            // side of the ring, so it is what moves the left/right area split.
            asym[i] = k * (float)Math.Cos(th) + 0.5f * (float)Math.Sin(2 * th + pb)
                    + 0.35f * (float)Math.Sin(3 * th + pa);
        }
        ox = margin + contentW * 0.5f; oy = margin + contentH;
        Build();
    }

    // ---------------- API ----------------
    public void SetFrame(float contentW, float contentH) { fw = contentW; fh = contentH; }
    public void SetMood(int m) { mood = m; }
    public void SetMotionScale(float s) { MotionScale = Math.Max(0f, Math.Min(1f, s)); }
    public void Expand(float originX, float originY) { ox = originX; oy = originY; openT = 1f; splashed = false; }
    public void Collapse(float originX, float originY) { ox = originX; oy = originY; openT = 0f; }
    public void Move(float windowLeft, float windowTop)
    {
        wx = windowLeft; wy = windowTop;
        if (!haveWin) { pwx = wx; pwy = wy; haveWin = true; }
    }

    // whole-body wobble
    public void Kick(float strength)
    {
        if (MotionScale <= 0f) return;
        strength *= MotionScale * 0.5f;
        float p1 = R() * 6.283f, p2 = R() * 6.283f;
        for (int i = 0; i < N; i++)
        {
            float th = 6.2831853f * i / N;
            vel[i] += strength * (0.8f * (float)Math.Cos(2 * th + p1) + 0.5f * (float)Math.Cos(3 * th + p2));
        }
    }

    // local dent at a window-space point; ripples spread from there
    public void Poke(float x, float y, float strength)
    {
        if (MotionScale <= 0f) return;
        strength *= MotionScale * 0.5f;
        int best = 0; float bd = 1e9f;
        for (int i = 0; i < N; i++) { float dx = px[i] - x, dy = py[i] - y, d = dx * dx + dy * dy; if (d < bd) { bd = d; best = i; } }
        for (int k = -3; k <= 3; k++) vel[(best + k + N) % N] -= strength * (float)Math.Exp(-k * k * 0.5f);
    }

    public void Update(float dt)
    {
        if (dt > 0.1f) dt = 0.1f;
        if (dt < 1e-4f) return;
        time += dt;

        if (haveWin && MotionScale > 0f)
        {   // window acceleration (smoothed): drag the window and the membrane lags behind
            float vx = (wx - pwx) / dt, vy = (wy - pwy) / dt;
            pwx = wx; pwy = wy;
            vxS += (vx - vxS) * 0.5f; vyS += (vy - vyS) * 0.5f;
            float rax = (vxS - pvxS) / dt, ray = (vyS - pvyS) / dt;
            pvxS = vxS; pvyS = vyS;
            ax += (Clamp(rax, -12000f, 12000f) - ax) * 0.35f;
            ay += (Clamp(ray, -12000f, 12000f) - ay) * 0.35f;
        }

        acc += dt;
        const float h = 1f / 120f;
        while (acc >= h) { Step(h); acc -= h; }
        Build();
    }

    // ---------------- simulation ----------------
    float R() { return (float)rng.NextDouble(); }
    static float Clamp(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
    static string F(float v) { return v.ToString("0.##", CultureInfo.InvariantCulture); }   // never the machine's decimal comma

    void Step(float h)
    {
        // mood -> idle wave amplitude / speed
        float A, w; float five = 0f;
        switch (mood)
        {
            case Thinking: A = 4.0f; w = 1.8f; break;
            case Alert: A = 3.2f; w = 3.2f; five = 1.2f; break;
            case Happy: A = 3.4f; w = 1.4f; break;
            default: A = 1.3f; w = 1.0f; break;
        }
        A *= MotionScale;
        phase1 += h * 0.5f * w; phase2 += h * 0.8f * w;

        // expand / resize springs: near-critically damped (zeta ~= 0.9).
        // The old 150/13 and 190/15 pairs (zeta ~= 0.53) reached full size in
        // ~6 frames with a 130px/frame jump and left an opacity ghost on close.
        // These reach 90% in ~12 frames and settle without overshoot or ripple.
        openV += (40f * (openT - open) - 11.5f * openV) * h; open += openV * h;
        cwv += (44f * (fw - cw) - 12.5f * cwv) * h; cw += cwv * h;
        chv += (44f * (fh - ch) - 12.5f * chv) * h; ch += chv * h;
        if (!splashed && openT == 1f && open > 0.92f) { splashed = true; Kick(70f); }

        // membrane ring
        const float K = 45f, C = 700f, D = 5f, G = 0.06f;
        for (int i = 0; i < N; i++)
        {
            int l = (i + N - 1) % N, r = (i + 1) % N;
            float th = 6.2831853f * i / N;
            float tgt = A * (0.6f * (float)Math.Sin(2 * th + phase1) + 0.4f * (float)Math.Sin(3 * th - phase2)
                           + five * (float)Math.Sin(5 * th + time * 6f));
            float ext = -G * (ax * nx[i] + ay * ny[i]) * MotionScale;
            float a = K * (tgt - off[i]) + C * (off[l] + off[r] - 2f * off[i]) - D * vel[i] + ext;
            vel[i] += a * h;
        }
        for (int i = 0; i < N; i++) off[i] += vel[i] * h;
    }

    // ---------------- geometry ----------------
    float Soft(float o)
    {
        if (o >= 0f) return OutLimit * (float)Math.Tanh(o / OutLimit);
        return -InLimit * (float)Math.Tanh(-o / InLimit);
    }

    // point + outward normal at arc-length u along a rounded rect (start: right-middle, clockwise on screen)
    static void RectPoint(float u, float hw, float hh, float R, out float x, out float y, out float nxo, out float nyo)
    {
        float a = hh - R, b = 2f * hw - 2f * R, c = 2f * hh - 2f * R, q = 1.5707963f * R;
        if (u < a) { x = hw; y = u; nxo = 1; nyo = 0; return; } u -= a;
        if (u < q) { float f = u / R; x = hw - R + R * (float)Math.Cos(f); y = hh - R + R * (float)Math.Sin(f); nxo = (float)Math.Cos(f); nyo = (float)Math.Sin(f); return; } u -= q;
        if (u < b) { x = hw - R - u; y = hh; nxo = 0; nyo = 1; return; } u -= b;
        if (u < q) { float f = 1.5707963f + u / R; x = -hw + R + R * (float)Math.Cos(f); y = hh - R + R * (float)Math.Sin(f); nxo = (float)Math.Cos(f); nyo = (float)Math.Sin(f); return; } u -= q;
        if (u < c) { x = -hw; y = hh - R - u; nxo = -1; nyo = 0; return; } u -= c;
        if (u < q) { float f = 3.1415927f + u / R; x = -hw + R + R * (float)Math.Cos(f); y = -hh + R + R * (float)Math.Sin(f); nxo = (float)Math.Cos(f); nyo = (float)Math.Sin(f); return; } u -= q;
        if (u < b) { x = -hw + R + u; y = -hh; nxo = 0; nyo = -1; return; } u -= b;
        if (u < q) { float f = 4.712389f + u / R; x = hw - R + R * (float)Math.Cos(f); y = -hh + R + R * (float)Math.Sin(f); nxo = (float)Math.Cos(f); nyo = (float)Math.Sin(f); return; } u -= q;
        x = hw; y = -hh + R + u; nxo = 1; nyo = 0;
    }

    void Build()
    {
        float hw = Math.Max(4f, cw * 0.5f), hh = Math.Max(4f, ch * 0.5f);
        float mn = Math.Min(hw, hh);

        // growth: shape scales about the origin; overshoot is soft-limited so it can't leave the window
        float s = open;
        if (s > 1f) { float L = Math.Max(0.004f, (Margin * 0.55f) / Math.Max(hw, hh)); s = 1f + L * (float)Math.Tanh((s - 1f) / L); }
        s = Math.Max(s, 0.035f);
        float ease = Clamp(s / 0.5f, 0f, 1f); ease = ease * ease * (3f - 2f * ease);
        float Rr = (mn * 0.985f) + (Roundness * mn - mn * 0.985f) * ease;       // blob -> rounded frame
        float amp = Clamp((s - 0.05f) / 0.5f, 0f, 1f);

        float cx = Margin + fw * 0.5f, cy = Margin + fh * 0.5f;
        // perimeter = 2*(2hw-2R) + 2*(2hh-2R) + 2*pi*R
        float P = 2f * (2f * hw - 2f * Rr) + 2f * (2f * hh - 2f * Rr) + 6.2831853f * Rr;

        float loX = Stroke * 0.5f + 3f, hiX = fw + 2f * Margin - loX, loY = loX, hiY = fh + 2f * Margin - loY;
        for (int i = 0; i < N; i++)
        {
            float bx, by, nxo, nyo;
            RectPoint(P * i / N, hw, hh, Rr, out bx, out by, out nxo, out nyo);
            nx[i] = nxo; ny[i] = nyo;
            // Route the static field through Soft() too: the inward dent cap
            // then bounds asym + wave together, so a high-amplitude mood cannot
            // push the body into the content clip.
            float o = Soft(off[i] + asym[i]) * amp;
            float x = cx + bx + nxo * o, y = cy + by + nyo * o;
            x = ox + (x - ox) * s; y = oy + (y - oy) * s;               // scale about the pea
            px[i] = Clamp(x, loX, hiX); py[i] = Clamp(y, loY, hiY);      // hard safety: never clipped by the window
        }

        // closed Catmull-Rom -> Bezier
        StringBuilder sb = new StringBuilder(1400);
        sb.Append('M').Append(F(px[0])).Append(',').Append(F(py[0]));
        for (int i = 0; i < N; i++)
        {
            int i0 = (i + N - 1) % N, i1 = i, i2 = (i + 1) % N, i3 = (i + 2) % N;
            // Bezier convex-hull property: if all four control points are inside the
            // safety box, the sampled curve is too. Clamping only the on-curve points
            // (px/py) let the Catmull-Rom tangents overshoot during expansion.
            float c1x = Clamp(px[i1] + (px[i2] - px[i0]) / 6f, loX, hiX);
            float c1y = Clamp(py[i1] + (py[i2] - py[i0]) / 6f, loY, hiY);
            float c2x = Clamp(px[i2] - (px[i3] - px[i1]) / 6f, loX, hiX);
            float c2y = Clamp(py[i2] - (py[i3] - py[i1]) / 6f, loY, hiY);
            sb.Append(" C").Append(F(c1x)).Append(',').Append(F(c1y))
              .Append(' ').Append(F(c2x)).Append(',').Append(F(c2y))
              .Append(' ').Append(F(px[i2])).Append(',').Append(F(py[i2]));
        }
        sb.Append(" Z");
        Path = sb.ToString();

        // glossy rim highlight: open arc along the left/top, inset 5 px
        float aLen = hh - Rr, q = 1.5707963f * Rr, bLen = 2f * hw - 2f * Rr;
        float fLeftMid = (aLen + q + bLen + q + (hh - Rr)) / P, fTopMid = (aLen + q + bLen + q + (2f * hh - 2f * Rr) + q + (hw - Rr)) / P;
        int j0 = (int)Math.Ceiling((fLeftMid + 0.05f) * N), j1 = (int)Math.Floor((fTopMid + 0.07f) * N);
        int cnt = j1 - j0 + 1;
        if (cnt >= 4 && s > 0.5f)
        {
            float[] hx = new float[cnt], hy = new float[cnt];
            for (int k = 0; k < cnt; k++)
            {
                int i = ((j0 + k) % N + N) % N;
                hx[k] = px[i] - nx[i] * 5f * s; hy[k] = py[i] - ny[i] * 5f * s;
            }
            StringBuilder hb = new StringBuilder(500);
            hb.Append('M').Append(F(hx[0])).Append(',').Append(F(hy[0]));
            for (int k = 0; k < cnt - 1; k++)
            {
                int a0 = Math.Max(0, k - 1), a1 = k, a2 = k + 1, a3 = Math.Min(cnt - 1, k + 2);
                hb.Append(" C").Append(F(hx[a1] + (hx[a2] - hx[a0]) / 6f)).Append(',').Append(F(hy[a1] + (hy[a2] - hy[a0]) / 6f))
                  .Append(' ').Append(F(hx[a2] - (hx[a3] - hx[a1]) / 6f)).Append(',').Append(F(hy[a2] - (hy[a3] - hy[a1]) / 6f))
                  .Append(' ').Append(F(hx[a2])).Append(',').Append(F(hy[a2]));
            }
            Highlight = hb.ToString();
        }
        else Highlight = "";

        // Content fades in only once the grown body actually covers the content
        // rect. The old open/0.9 ramp showed chat text at 10% opacity while the
        // blob was still a 66px pea, which read as a flash of floating content.
        ContentOpacity = Clamp((s - 0.90f) / 0.10f, 0f, 1f);
    }
}
'@

$slopFrameType = 'SlopFrame' -as [type]
if ($null -eq $slopFrameType) {
    Add-Type -TypeDefinition $csSource -Language CSharp
} elseif ($null -eq $slopFrameType.GetField('Version') -or
          [int]$slopFrameType.GetField('Version').GetValue($null) -ne 4) {
    # A long-lived pwsh that sourced an older type would silently run stale
    # geometry AND stale spring constants. Fail loudly instead.
    throw 'Stale SlopFrame type (need Version=4) loaded in this session. Restart pwsh before re-sourcing Slop.Frame.ps1.'
}
