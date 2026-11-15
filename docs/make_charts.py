"""Render the portfolio charts for the 5G customer analytics project.

All figures are RESCALED versions of the original results (counts scaled, rates slightly
perturbed). Relative patterns are preserved. Usage: python make_charts.py <output_dir>
"""
import sys, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter, FuncFormatter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

SURF, INK, INK2, MUTED, GRID, AXIS = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"
BLUE, ORANGE, AQUA, GRAY = "#2a78d6", "#eb6834", "#1baf7a", "#b9b8b0"
SEQ = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]

plt.rcParams.update({
    "font.family": ["Segoe UI", "DejaVu Sans"], "font.size": 11,
    "figure.facecolor": SURF, "axes.facecolor": SURF, "savefig.facecolor": SURF,
    "axes.edgecolor": AXIS, "axes.labelcolor": INK2, "text.color": INK,
    "xtick.color": MUTED, "ytick.color": INK2,
    "axes.spines.top": False, "axes.spines.right": False,
})

def title(ax, t, sub):
    ax.set_title(t, loc="left", fontsize=14, fontweight="bold", color=INK, pad=28)
    ax.text(0, 1.02, sub, transform=ax.transAxes, fontsize=10, color=INK2, va="bottom")

def save(fig, name):
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, name), dpi=200)
    plt.close(fig)

months = ["M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10", "M11"]

# 1) 5G adoption gap
dev = [.272, .276, .277, .282, .290, .295, .300, .309, .316, .327, .344]
prv = [.281, .280, .285, .293, .299, .304, .314, .323, .335, .343, .348]
usr = [.181, .175, .176, .181, .185, .183, .185, .189, .195, .206, .214]
fig, ax = plt.subplots(figsize=(9, 4.6))
for ys, c, lab, mk, dy in [(prv, BLUE, "5G provisioned", "o", 0.008), (dev, AQUA, "Has 5G device", "s", -0.008), (usr, ORANGE, "Actually uses 5G", "D", 0)]:
    ax.plot(months, ys, color=c, lw=2, marker=mk, ms=6, markeredgecolor=SURF, markeredgewidth=1.5)
    ax.text(10.25, ys[-1] + dy, f"{lab}  {ys[-1]:.0%}", va="center", fontsize=10, color=INK2)
ax.set_xlim(-0.3, 13.2); ax.set_ylim(0.1, 0.42)
ax.yaxis.set_major_formatter(PercentFormatter(1, decimals=0))
ax.grid(axis="y", color=GRID, lw=0.8); ax.set_axisbelow(True)
ax.set_ylabel("Share of active subscribers"); ax.set_xlabel("Month")
title(ax, "34% of subscribers have a 5G phone, but only 21% use 5G", "Both brands, postpaid individual + prepaid (~43M active subscribers)")
save(fig, "01_5g_adoption_gap.png")

# 2) churn 5G vs non-5G
fig, ax = plt.subplots(figsize=(9, 4.4))
groups = ["Mass & mid value", "High Value (top ARPU band)"]
non5g = [.0231, .0376]; g5 = [.0040, .0054]
x = range(2); w = 0.34
b1 = ax.bar([i - w / 2 for i in x], non5g, w, color=GRAY, label="Non-5G user", edgecolor=SURF, linewidth=2, zorder=2)
b2 = ax.bar([i + w / 2 for i in x], g5, w, color=BLUE, label="5G user", edgecolor=SURF, linewidth=2, zorder=2)
for bars in (b1, b2):
    for b in bars:
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 0.0007, f"{b.get_height():.2%}", ha="center", fontsize=10, color=INK2)
ax.set_xticks(list(x), groups); ax.tick_params(axis="x", colors=INK2)
ax.yaxis.set_major_formatter(PercentFormatter(1, decimals=1)); ax.set_ylim(0, 0.043)
ax.grid(axis="y", color=GRID, lw=0.8); ax.set_axisbelow(True)
ax.set_ylabel("Monthly churn rate"); ax.legend(frameon=False, loc="upper left")
title(ax, "5G users churn ~6-7x less than non-5G users",
      "Brand A postpaid individual, latest month - from the High Value routine report with the new 5G parameter")
save(fig, "02_hv_churn_5g_vs_non5g.png")

# 3) provisioning gap
fig, ax = plt.subplots(figsize=(9, 3.9))
rows = [("Brand A Postpaid", .955, "70K"), ("Brand B Postpaid", .862, "264K"), ("Brand A Prepaid", .865, "495K"), ("Brand B Prepaid", .466, "1,650K")][::-1]
ax.barh([r[0] for r in rows], [1] * 4, color="#eeede8", height=0.6, zorder=1)
ax.barh([r[0] for r in rows], [r[1] for r in rows], color=[ORANGE if r[1] < .6 else BLUE for r in rows], height=0.6, zorder=2)
for i, r in enumerate(rows):
    ax.text(r[1] - 0.01, i, f"{r[1]:.0%}", va="center", ha="right", fontsize=10, color="#ffffff", fontweight="bold")
    ax.text(1.01, i, f"{r[2]} not provisioned", va="center", fontsize=10, color=INK2)
ax.set_xlim(0, 1.32); ax.set_xticks([0, .25, .5, .75, 1]); ax.xaxis.set_major_formatter(PercentFormatter(1, decimals=0))
ax.tick_params(axis="y", length=0); ax.spines["bottom"].set_bounds(0, 1)
ax.set_xlabel("% of 5G-device users with 5G provisioning")
title(ax, "~2.5M customers own a 5G phone but are not provisioned", "Half of Brand B prepaid 5G-device users cannot use 5G yet")
save(fig, "03_provisioning_gap.png")

# 4) priority matrix
aon = ["0-6 months", "6-12 months", "1-3 years", "3-5 years", "> 5 years"]
arpu = ["Band 1\n(lowest)", "Band 2", "Band 3", "Band 4\n(highest)"]
mat = [[7.8, 6.5, 2.6, 1.6], [4.7, 8.3, 2.2, 1.0], [11.7, 17.0, 4.8, 2.1], [8.6, 13.5, 4.4, 2.0], [45.2, 69.6, 25.6, 16.3]]
fig, ax = plt.subplots(figsize=(8.6, 4.9)); vmax = 70
col = lambda v: SEQ[min(int(v / vmax * (len(SEQ) - 1) + 0.5), len(SEQ) - 1)]
for i, row in enumerate(mat):
    for j, v in enumerate(row):
        ax.add_patch(plt.Rectangle((j, len(mat) - 1 - i), 0.96, 0.92, color=col(v)))
        ax.text(j + 0.48, len(mat) - 1 - i + 0.46, f"{v:.1f}K", ha="center", va="center", fontsize=11,
                color="#ffffff" if SEQ.index(col(v)) >= 3 else INK)
ax.add_patch(plt.Rectangle((2, 0), 1.96, 0.92, fill=False, ec=ORANGE, lw=2.5))
ax.text(4.02, 0.46, "Wave 1\n42K", va="center", fontsize=10, color=INK, fontweight="bold")
ax.set_xlim(0, 4.7); ax.set_ylim(0, len(mat))
ax.set_xticks([j + 0.48 for j in range(4)], arpu); ax.set_yticks([len(mat) - 1 - i + 0.46 for i in range(len(mat))], aon)
for s in ax.spines.values(): s.set_visible(False)
ax.tick_params(length=0); ax.set_xlabel("ARPU band"); ax.set_ylabel("Age on network")
title(ax, "Who to provision first: ~256K postpaid customers ready for 5G today",
      "5G device + no provisioning + most-used cell site already has 5G (both brands, postpaid)")
save(fig, "04_provisioning_priority_matrix.png")

# 5) coverage gap by region
po = {"Bangkok East": 210, "Central-West": 167, "Bangkok West": 152, "East": 108, "South": 112, "North": 115, "Northeast 1": 90, "Northeast 2": 83}
pp = {"Bangkok East": 219, "Central-West": 199, "North": 186, "East": 158, "South": 174, "Northeast 1": 142, "Bangkok West": 133, "Northeast 2": 121}
regions = sorted(po, key=lambda r: po[r] + pp[r])
fig, ax = plt.subplots(figsize=(9, 4.6))
ax.barh(regions, [po[r] for r in regions], color=BLUE, height=0.62, label="Postpaid", edgecolor=SURF, linewidth=2, zorder=2)
ax.barh(regions, [pp[r] for r in regions], left=[po[r] for r in regions], color=AQUA, height=0.62, label="Prepaid", edgecolor=SURF, linewidth=2, zorder=2)
for i, r in enumerate(regions):
    ax.text(po[r] + pp[r] + 6, i, f"{po[r]+pp[r]}K", va="center", fontsize=10, color=INK2)
ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:.0f}K")); ax.set_xlim(0, 490)
ax.tick_params(axis="y", length=0); ax.grid(axis="x", color=GRID, lw=0.8); ax.set_axisbelow(True)
ax.legend(frameon=False, loc="lower right"); ax.set_xlabel("5G-device users whose most-used cell site has no 5G")
title(ax, "~2.4M 5G-device users live where 5G is not yet built", "Where to add 5G sites - ranked down to sub-district level in the analysis")
save(fig, "05_coverage_gap_by_region.png")

# 6) traffic-share anomaly
a = [.542, .550, .494, .496, .450, .476, .485, .485, .572, .621, .599]
b = [.402, .407, .393, .401, .386, .290, .187, .162, .182, .174, .178]
fig, ax = plt.subplots(figsize=(9, 4.4))
ax.plot(months, a, color=BLUE, lw=2, marker="o", ms=6, markeredgecolor=SURF, markeredgewidth=1.5)
ax.plot(months, b, color=ORANGE, lw=2, marker="D", ms=6, markeredgecolor=SURF, markeredgewidth=1.5)
ax.text(10.25, a[-1], f"Brand A  {a[-1]:.0%}", va="center", fontsize=10, color=INK2)
ax.text(10.25, b[-1], f"Brand B  {b[-1]:.0%}", va="center", fontsize=10, color=INK2)
ax.axvspan(4.6, 6.4, color="#f6c9c8", alpha=0.5, zorder=0)
ax.text(5.5, 0.72, "Flagged to Network\n& DWH teams", ha="center", fontsize=9.5, color=INK2)
ax.set_xlim(-0.3, 12.2); ax.set_ylim(0, 0.8); ax.yaxis.set_major_formatter(PercentFormatter(1, decimals=0))
ax.grid(axis="y", color=GRID, lw=0.8); ax.set_axisbelow(True)
ax.set_ylabel("% of 5G users' data carried on 5G"); ax.set_xlabel("Month")
title(ax, "Monitoring caught a sudden drop in Brand B 5G traffic share",
      "Postpaid individual 5G users - Brand B fell from 39% (M5) to 16% (M8) while Brand A kept rising")
save(fig, "06_5g_traffic_anomaly.png")
print("done")
