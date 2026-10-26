# LokoAssist Retreat 2026 poster - preparation files

Poster for the LokoAssist retreat (26-27 Oct 2026). The poster itself is edited as an online
design canvas; this folder holds the figures and the code that makes them.

## Contents

- `make_retreat_q5.py` - makes the Study 2 figure "What goes with a pleasant walk?"
  (within-participant correlation of each rated factor, and of net metabolic cost, with pleasantness).
- `retreat_config.toml` - settings for that figure: white background, printed size, font size,
  axis label, and where the ICNR figure package is.
- `output/figures/` - the figure as PNG, SVG and PDF.
- `output/tables/` - the numbers behind it (r, 95 % CI, df, each participant's r).
- `poster_images/` - the other images used on the poster:
  - `study1_knee_setup.png` - panel c of the Study 1 concept figure (setup only)
  - `study1_sensorimotor_right_ICs_ERSP.png` - right sensorimotor cluster from Figure 3 of the Study 1 paper
    (dipoles, scalp map, ERSP for low/medium/high demand, RM-ANOVA mask)
  - `study1_parieto_occipital_left_ICs_ERSP.png` - left parieto-occipital cluster from Figure 4, same layout
  - `study2_hip_setup.png` - the walking setup illustration (cropped). Note: it shows the breathing mask and
    the EEG cap together, but they are recorded on separate days.

## How the Q5 figure is made

The script reuses the ICNR 2026 package in `../ICNR poster preparation/icnr2026_figures`
(its code `hipexo_figs`, its `config.toml` and its metabolic data) without changing anything there.
The questionnaire exports are read straight from `../../Pilots/PilotTest3` (all participants and
days, including P3_4 day 2, which the ICNR copy does not have).
Run it from anywhere:

    python make_retreat_q5.py

It needs the same Python packages as the ICNR package (see its `requirements.txt`).
If the ICNR folder moves, update `icnr_package` in `retreat_config.toml`.

Centring: ratings are centred per participant-day before the repeated-measures correlation
(Bakdash & Marusich, 2017), so a day-to-day shift in how someone rates is removed rather than
counted as covariation (`centre_per = "participant_day"`; `"participant"` gives the ICNR behaviour).
Each participant's small marker is centred the same way. Net metabolic cost exists for day 1 only.

Discomfort: the intensity item is only asked after "yes", so "no discomfort" is counted as
intensity 0 (`discomfort_none_as_zero`), as in the final ICNR version of this figure.
