"""Q5 'What goes with a pleasant walk?' for the LokoAssist Retreat 2026 poster.

    python make_retreat_q5.py

Built on the ICNR 2026 poster figure (Q5_poster_judgement_drivers). The ICNR package (its code,
config.toml and metabolic data) is reused in place and not changed. Set in retreat_config.toml:
questionnaire exports read from the pilot folders (all participants and days), white background,
a wide format for the Current Status column, discomfort "none" counted as intensity 0, and
centring per participant-day (or per participant, as in the ICNR figure).

Writes output/figures/<out_name>.(png|svg|pdf) and output/tables/<out_name>.csv next to this script.
"""
from __future__ import annotations

import sys
import warnings
from pathlib import Path

try:
    import tomllib  # Python >= 3.11
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

import numpy as np
import pandas as pd
from matplotlib import colors as matplotlib_colors
from matplotlib.lines import Line2D

HERE = Path(__file__).resolve().parent
SETTINGS = tomllib.loads((HERE / "retreat_config.toml").read_text(encoding="utf-8-sig"))
PACKAGE_DIR = (HERE / SETTINGS["paths"]["icnr_package"]).resolve()
OUTPUT_DIR = (HERE / SETTINGS["paths"]["output_dir"]).resolve()
if not (PACKAGE_DIR / "hipexo_figs").is_dir():
    raise SystemExit(f"ICNR figure package not found at {PACKAGE_DIR}; check [paths] icnr_package "
                     "in retreat_config.toml")
sys.path.insert(0, str(PACKAGE_DIR))

from hipexo_figs import figs  # noqa: E402
from hipexo_figs import plotting as P  # noqa: E402
from hipexo_figs import questionnaire as Q  # noqa: E402
from hipexo_figs.config import load_config  # noqa: E402
from hipexo_figs.fileio import write_csv  # noqa: E402
from hipexo_figs.ids import ParticipantMap  # noqa: E402
from hipexo_figs.stats import rmcorr  # noqa: E402

Q5 = SETTINGS["q5"]
BACKGROUND = Q5["background"]
SIZE_CM = Q5["size_cm"]
FONT_PT = Q5["font_pt"]
X_LABEL = Q5["x_label"]
OUT_NAME = Q5["out_name"]

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except (AttributeError, ValueError):
        pass
warnings.showwarning = lambda m, *a, **k: print(f"WARNING: {m}", file=sys.stderr)


# ----------------------------------------------------------------------------- discomfort 'none' = 0
_read_exports = Q.read_exports


def _read_exports_none_as_zero(cfg, pmap):
    df = _read_exports(cfg, pmap)
    none = df[(df["item_id"] == "discomfort") & (df["value"].astype(str).str.strip().str.lower() == "none")]
    have = set(df.loc[df["item_id"] == "discomfort_intensity", "block_start"])
    add = none[~none["block_start"].isin(have)].copy()
    if len(add):
        add["item_id"], add["value"] = "discomfort_intensity", "0"
        add["item_type"] = "vas"
        df = pd.concat([df, add], ignore_index=True)
        print(f"questionnaire: discomfort 'none' counted as intensity 0 in {len(add)} blocks")
    return df


if Q5.get("discomfort_none_as_zero", True):
    Q.read_exports = _read_exports_none_as_zero


# ----------------------------------------------------------------------------- centring unit
CENTRE_PER = Q5.get("centre_per", "participant_day")
if CENTRE_PER not in ("participant_day", "participant"):
    raise SystemExit(f"retreat_config.toml: centre_per must be 'participant_day' or 'participant', "
                     f"not '{CENTRE_PER}'")


def _centring_unit(d: pd.DataFrame) -> pd.Series:
    """The set each rating is centred within before the repeated-measures correlation
    (Bakdash & Marusich, 2017). Per participant-day, a day-to-day shift in how someone rates
    is removed instead of being counted as covariation."""
    if CENTRE_PER == "participant":
        return d["participant"].astype(str)
    return d["participant"].astype(str) + "_day" + d["day"].astype("Int64").astype(str)


# ----------------------------------------------------------------------------- the figure
def judgement_drivers_retreat(scores, summary, cfg):
    f = cfg["figures"]
    groups = f.get("judgement_groups", {})
    colours = f.get("judgement_group_colors", ["#1baf7a", "#4a3aa7", "#eb6834"])
    labels = {**cfg["questionnaire"]["construct_labels"], **f.get("judgement_poster_labels", {})}
    rows, table = [], []
    for gi, (gname, members) in enumerate(groups.items()):
        colour = colours[gi % len(colours)]
        items = []
        for c in members:
            d = figs._driver_data(scores, summary, cfg, c)
            if d is None or d.empty:
                continue
            d = d.assign(unit=_centring_unit(d))
            res = rmcorr(d, "x", "target", subject="unit")
            res["k_participants"] = d["participant"].nunique()
            if not np.isfinite(res["r"]) or res["df"] < figs._min_df(cfg):
                continue
            per = {}
            for pid, g in d.groupby("participant"):
                # each participant's own value, centred the same way as the pooled one
                rp = rmcorr(g, "x", "target", subject="unit")
                if len(g) >= 4 and np.isfinite(rp["r"]):
                    per[pid] = float(rp["r"])
            items.append((c, res, per))
            table.append({"group": gname, "candidate": c, "label": labels.get(c, c),
                          **{k: v for k, v in res.items() if k != "intercepts"},
                          **{f"r_{pid}": v for pid, v in per.items()}})
        if not items:
            continue
        items.sort(key=lambda it: (it[0] == "metabolic", -it[1]["r"]))
        rows.append(("header", gname, colour, None, None))
        for c, res, per in items:
            rows.append(("item" if c != "metabolic" else "measured", labels.get(c, c), colour, res, per))

    size = f["font_size_pt"]
    bg = BACKGROUND
    parts = figs._participants(scores)
    markers = P.participant_style(parts, cfg)
    fig = P.figure(SIZE_CM)
    ax = fig.add_subplot()
    ax.grid(False)
    ys, y = {}, 0.0
    for i, r in enumerate(rows):
        if r[0] == "header" and i > 0:
            y += 0.45
        ys[i] = y
        y += 1.0
    ymax = y - 1.0

    for xv in (-0.5, 0.5):
        ax.axvline(xv, color=f["grid"], lw=1.0, zorder=0)
    ax.axvline(0, color=f["ink_secondary"], lw=1.2, zorder=0)

    def tint(hex_colour, a):
        rgb = np.array(matplotlib_colors.to_rgb(hex_colour))
        base = np.array(matplotlib_colors.to_rgb(bg))
        return tuple(a * rgb + (1 - a) * base)

    for i, (kind, text, colour, res, per) in enumerate(rows):
        yy = ys[i]
        if kind == "header":
            ax.text(-0.02, yy, text.upper(), color=colour, fontsize=0.8 * size, fontweight="semibold",
                    ha="right", va="center", transform=ax.get_yaxis_transform())
            continue
        ax.plot([res["ci_low"], res["ci_high"]], [yy, yy], color=tint(colour, 0.28), lw=0.62 * size,
                solid_capstyle="round", zorder=1)
        ax.plot(res["r"], yy, "o", ms=0.62 * size, mfc=colour, mec=bg, mew=2.0, zorder=3)
        yp = yy + 0.38
        placed = []
        for pid, rp in sorted(per.items(), key=lambda kv: kv[1]):
            if placed and rp - placed[-1] < 0.025:
                rp = placed[-1] + 0.025
            placed.append(rp)
            ax.plot(rp, yp, ls="none", marker=markers[pid], ms=0.46 * size, mfc=f["ink_secondary"],
                    mec=bg, mew=1.0, zorder=4)
        ax.text(1.03, yy, f"{res['r']:+.2f}".replace("-", "−"), transform=ax.get_yaxis_transform(),
                ha="left", va="center", fontsize=0.85 * size, color=f["ink"])
    item_idx = [i for i, r in enumerate(rows) if r[0] != "header"]
    ax.set_yticks([ys[i] for i in item_idx])
    ax.set_yticklabels([rows[i][1] + (" (measured, day 1)" if rows[i][0] == "measured" else "")
                        for i in item_idx])
    for lab, i in zip(ax.get_yticklabels(), item_idx):
        lab.set_va("center")
        if rows[i][0] == "measured":
            lab.set_style("italic")
    ax.set_xlim(-1.0, 1.0)
    ax.set_xticks([-1, -0.5, 0, 0.5, 1])
    ax.xaxis.set_major_formatter(P.signed)
    ax.spines["left"].set_visible(False)
    ax.spines["bottom"].set_color(f["ink_secondary"])
    ax.tick_params(axis="y", length=0, pad=10)
    ax.set_xlabel(X_LABEL)
    box = dict(facecolor=bg, edgecolor="none", pad=2)
    ax.text(-0.97, -0.95, "← less pleasant", transform=ax.transData, ha="left", va="bottom",
            fontsize=0.75 * size, color=f["ink_secondary"], bbox=box)
    ax.text(0.97, -0.95, "more pleasant →", transform=ax.transData, ha="right", va="bottom",
            fontsize=0.75 * size, color=f["ink_secondary"], bbox=box)
    ax.set_ylim(ymax + 0.85, -1.15)
    handles = [Line2D([], [], ls="none", marker="o", ms=0.62 * size, mfc=f["ink_secondary"], mec=bg,
                      label="all (r$_{rm}$)"),
               Line2D([], [], color=tint(f["ink_secondary"], 0.28), lw=0.45 * size, solid_capstyle="butt",
                      label="95 % CI")]
    handles += [Line2D([], [], ls="none", marker=markers[p], ms=0.46 * size, mfc=f["ink_secondary"], mec=bg,
                       mew=1.0, label=p) for p in parts]
    ax.legend(handles=handles, loc="upper center", bbox_to_anchor=(0.5, -0.135), ncol=len(handles),
              fontsize=0.8 * size, handlelength=2.0, handletextpad=0.6, columnspacing=1.6, frameon=False)
    return fig, pd.DataFrame(table)


def main() -> int:
    cfg = load_config(PACKAGE_DIR / "config.toml")
    qdir = SETTINGS["paths"].get("questionnaire_dir")
    if qdir:
        cfg["paths"]["questionnaire_dir"] = (HERE / qdir).resolve()
        cfg["questionnaire"]["file_glob"] = SETTINGS["paths"].get("questionnaire_glob", "postcond_*.csv")
        print(f"questionnaire: reading {cfg['questionnaire']['file_glob']} under {cfg['paths']['questionnaire_dir']}")
    cfg["figures"]["background"] = BACKGROUND
    cfg["figures"]["font_size_pt"] = FONT_PT
    out = OUTPUT_DIR
    cfg["paths"]["output_dir"] = out
    (out / "figures").mkdir(parents=True, exist_ok=True)
    (out / "tables").mkdir(parents=True, exist_ok=True)
    P.setup_style(cfg)
    pmap = ParticipantMap(cfg["paths"]["participants_file"])
    from hipexo_figs.metabolic import analyse_folder
    summary, _ = analyse_folder(cfg, pmap)
    _, scores = Q.load(cfg, pmap, summary)
    fig, table = judgement_drivers_retreat(scores, summary, cfg)
    paths = P.save(fig, OUT_NAME, cfg)
    write_csv(table, out / "tables" / f"{OUT_NAME}.csv")
    for p in paths:
        print(f"wrote {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
