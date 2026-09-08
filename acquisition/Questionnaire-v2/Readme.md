# Post-condition questionnaire: what it measures and why

**Study:** HipExo-EEG-Study, Lauflabor Locomotion Lab, TU Darmstadt
**Instrument:** post-condition questionnaire v3.8
**Administered:** on a tablet, immediately after each of the eight walking blocks (No_Exo_Pre, exo-1 to exo-6, No_Exo_Post)
**Length:** 25 rating items plus 3 open prompts in an exo block, roughly 2 to 3 minutes; 7 rating items plus 2 open prompts in a no-exo block
**Status:** in pilot use

---

## About this folder

`index.html` is not source code to be built. It is the running questionnaire: a single self-contained HTML file with no dependencies, no build step, and no network requests once loaded. Open it and it works.

**Live form:** <https://mortybiomech.github.io/HipExo-EEG-Study/acquisition/Questionnaire-v2/>

- **On the lab tablet,** open the link above and use "Add to Home Screen" so it launches without an address bar. Voice recording requires the https link; it will not work from a copy opened off the filesystem.
- **Offline,** the file can be saved and opened directly. Everything works except voice recording.
- **Data stays on the device.** Answers are held in browser storage and voice clips in IndexedDB on the tablet itself. Nothing is uploaded, and this page has no server behind it. Export the CSV and the audio from the experimenter screen at the end of each session, then clear the device.
- **To change the instrument,** edit the `CONFIG` block and the `ITEMS` array at the top of the script in `index.html`. Conditions, scale type, randomisation, recording limits and every item's wording live there. Bump `formVersion` with any change to item wording, since that string is written into every exported row and is how a participant's data is later matched to the version they saw.
- **After pushing a change,** hard-reload the tablet or open the link with a query string such as `?v=3.8`, or the browser will serve the cached previous version.

The rest of this document is the rationale: what each item measures, why it is worded as it is, and the literature it comes from. Section 5 lists the known limitations and open decisions; it is published deliberately rather than kept internal.

---

## 1. Purpose

The EEG, EMG, GRF and IMU streams tell us what the body and brain did. They do not tell us what the participant made of it. This questionnaire supplies the subjective side of the human-exoskeleton interaction, in a form that can be entered into the same statistical models as the physiological measures.

The design is organised around one question: **on what basis does a person judge a given assistance mode to be good or bad?** That is the human cost function the project aims to characterise. Every item either measures a candidate term in that function (effort, comfort, control, predictability, safety, stability) or measures the judgement itself (valence, perceived benefit, acceptance, comparison against the previous block).

### 1.1 Design constraints

**Time is not the binding constraint.** Participants rest for around ten minutes between blocks. The form uses two to three minutes of that. Two other limits do bind:

- *Recency.* Perceived exertion is a state measure that decays as the participant recovers. The Borg items therefore sit on the first page and the form must be started promptly after the bout, not partway through the rest.
- *Repetition.* The form is answered eight times in one session. Response quality degrades with tedium long before the rest period runs out, and because every item shares a method, a moment and a mood, adding items inflates the correlations between constructs without adding independent information. The instrument was expanded from 19 to 28 items deliberately and stopped there.

**It must discriminate between conditions.** Measures that sit at ceiling in every condition cannot serve as behavioural correlates of the EEG. Several design choices in section 3 exist purely to protect between-condition variance.

**It must not lead.** Participants are blind to condition and the wording avoids naming the variables we manipulate.

### 1.2 Structure

| Page | Content | Items (exo) | Items (no-exo) |
|---|---|---|---|
| 1 | How hard was it | 2 | 2 |
| 2 | What the device did | 6 | — |
| 3 | You and the device | 9 | — |
| 4 | How it felt | 5 | 5 |
| 5 | Overall | 3 | 1 |
| 6 | In your own words | 3 | 2 |

---

## 2. Constructs measured

### 2.1 Perceived exertion (2 items, every block)

| Item | Scale |
|---|---|
| How hard did your legs work during that walk? | Borg CR10, 0 to 10 with verbal anchors |
| How hard was your breathing during that walk? | Borg CR10, 0 to 10 with verbal anchors |

This is the anchor measure of the instrument. Borg's category-ratio scale is the standard perceptual companion to indirect calorimetry and the established subjective analogue of metabolic cost. Splitting local (legs) from central (breathing) exertion is conventional and matters here because hip assistance may shift one without the other.

Metabolic cost is the term the exoskeleton field has historically optimised, so it is the first candidate term in the human cost function. Whether people actually weight it heavily when judging assistance is an open question this study can address, since we measure both the perception and, through calorimetry, the physiology.

> Borg, G. (1982). Psychophysical bases of perceived exertion. *Medicine & Science in Sports & Exercise*, 14(5), 377-381.
> Borg, G. (1998). *Borg's Perceived Exertion and Pain Scales*. Human Kinetics.
> Sawicki, G. S., Beck, O. N., Kang, I., & Young, A. J. (2020). The exoskeleton expansion: improving walking and running economy. *Journal of NeuroEngineering and Rehabilitation*, 17, 25.

### 2.2 Perception of what the device did (6 items, exo blocks)

| Item | Scale | Role |
|---|---|---|
| Overall, the device (helped / hindered my movements) | -2 strongly worked against to +2 strongly helped | perceived direction |
| How strongly could you feel the device acting on your legs? | continuous, not at all to very strongly | perceptibility check |
| If you could set it yourself, the device should have been | -2 much weaker to +2 much stronger | desired change in magnitude |
| Within each step, what the device did was | phasic / tonic / could not tell | perceived temporal structure |
| The moment in the step when the device acted should have been | -2 much earlier to +2 much later | desired change in timing, shown only after "phasic" |
| I could tell in advance when the device would act. | continuous | predictability |

This page is the most direct probe of the cost function and the most novel part of the instrument.

The **direction** item, new in v3.4, is the summary judgement of the interaction: did the device work with the person or against them, and how strongly. It is a signed five-point scale rather than a set of labelled categories, because direction and magnitude lie on one ordered dimension with "neither helped nor hindered" as its natural midpoint. An earlier proposal used four categories (helping / assisting / nothing / resisting); "helping" and "assisting" are near-synonyms in English and closer still in German, so participants could not have divided them reliably and the variable would have fragmented.

This is now the primary manipulation check for *direction*, and it is stronger for that purpose than the perceived-benefit item in 2.11, because it asks about the device's action rather than about effort and does not depend on remembering a no-exo block from an hour earlier. It is also the item that should most clearly separate the two resistive modes from the four assistive ones.

The magnitude item that follows checks *perceptibility* and is deliberately unsigned. The two are not redundant: a participant can feel the device acting strongly while being unsure whether it helped or hindered, and that state is itself informative. Comparing the absolute value of the direction rating against the felt magnitude is a consistency check within the block. Without a perceptibility check, an absence of difference between conditions would be uninterpretable, because we could not distinguish "this mode felt no different" from "this mode was not perceived at all".

The magnitude and timing items are **just-about-right** items, borrowed from sensory and consumer science. They are signed rather than unsigned: they record the *direction* in which the participant would have changed the device's behaviour, not merely how much they liked it. This is what makes them usable as an error term. A mode wanted "a little weaker" and one wanted "a little stronger" may earn identical liking scores while implying opposite adjustments.

**Sign convention.** Both items are worded as a desired setting ("the device should have been...") rather than as a description of an error ("the strength was..."). Negative means the participant wanted *less* or *earlier*, positive means *more* or *later*, zero means leave it as it was. This matters for two reasons. First, the earlier descriptive wording ("the strength of what the device did was") shared vocabulary with the perceptibility item directly above it, and participants answering quickly would read the second as a rephrasing of the first and answer consistently rather than considering it, inflating the correlation between two items that are meant to be independent. Second, asking for a setting rather than a verdict aligns the item with the acceptance question and with the verbal probe that asks what the participant would change, so the three can be read against each other. Versions up to v3.4 used the opposite sign on both items; the `form_version` column identifies which convention a row follows.

The pattern item was added after a pilot participant reported that a resistive mode felt constant across the cycle rather than peaked. It records the perceived temporal structure of the field and gates the timing question, because an early-versus-late judgement is only interpretable from someone who perceived a discrete event to place within the cycle. It is a dependent variable in its own right.

Predictability is theoretically the most interesting item for the EEG side of the project. An unpredictable assistance profile should generate prediction error, and prediction error has well-characterised cortical correlates. If a mode is judged badly and is also rated unpredictable, that is a specific and testable mechanism rather than a general statement of dislike.

> Ingraham, K. A., Remy, C. D., & Rouse, E. J. (2022). The role of user preference in the customized control of robotic exoskeletons. *Science Robotics*, 7(64), eabj3487.
> Zhang, J., Fiers, P., Witte, K. A., et al. (2017). Human-in-the-loop optimization of exoskeleton assistance during walking. *Science*, 356(6344), 1280-1284.
> Rothman, L., & Parker, M. J. (Eds.) (2009). *Just-About-Right (JAR) Scales: Design, Usage, Benefits and Risks*. ASTM International, MNL63.
> Popper, R., & Kroll, J. J. (2005). Just-about-right scales in consumer research. *Chemosense*, 7(3), 3-6.
> Blakemore, S.-J., Wolpert, D. M., & Frith, C. D. (2002). Abnormalities in the awareness of action. *Trends in Cognitive Sciences*, 6(6), 237-242.
> Friston, K. (2010). The free-energy principle: a unified brain theory? *Nature Reviews Neuroscience*, 11(2), 127-138.

### 2.3 Sense of agency (3 items, exo blocks)

| Item | Role |
|---|---|
| I decided how my legs moved. | agency |
| I was in full control of what my legs did. | agency |
| My legs were moved by something other than me. | reverse-worded control |

Agency is the feeling of authorship over one's own movement. It is directly at stake when a device contributes torque to a joint the person is also driving, and it is a plausible cost term: assistance producing the same metabolic saving may be judged worse if it erodes the sense of authoring one's own gait.

Expanded from one item to three in v3.0. Two positively worded items now permit an internal-consistency estimate rather than a single-item indicator. The third is a reverse-worded control, included to detect acquiescent responding, where a participant agrees with whatever is put in front of them. It is not simply the inverse of the others and should not be averaged with them without checking.

Agency also has a well-characterised neural signature, which makes it one of the more promising bridges between the questionnaire and the EEG.

> Haggard, P. (2017). Sense of agency in the human brain. *Nature Reviews Neuroscience*, 18(4), 196-207.
> Tapal, A., Oren, E., Dar, R., & Eitam, B. (2017). The Sense of Agency Scale: a measure of consciously perceived control over one's mind, body, and the immediate environment. *Frontiers in Psychology*, 8, 1552.

### 2.4 Embodiment (3 items, exo blocks)

| Item | Facet |
|---|---|
| The device felt like a part of my body. | incorporation |
| It felt as if the device belonged to me. | ownership |
| While I was walking, I stopped noticing the device as something separate. | transparency in use |

Whether the exoskeleton is incorporated into the body schema or remains an external object. Distinct from agency: a person can feel fully in control of a device that never stops feeling like a machine strapped to them.

Expanded from one item to three in v3.0, covering three facets of the construct as distinguished in the embodiment literature. The items are condensed from the ownership and incorporation subscales of the published instruments rather than newly written, but they remain a short-form proxy for scales that run to a dozen items or more, and should be described as such.

> Longo, M. R., Schüür, F., Kammers, M. P. M., Tsakiris, M., & Haggard, P. (2008). What is embodiment? A psychometric approach. *Cognition*, 107(3), 978-998.
> Gonzalez-Franco, M., & Peck, T. C. (2018). Avatar embodiment: towards a standardized questionnaire. *Frontiers in Robotics and AI*, 5, 74.
> Botvinick, M., & Cohen, J. (1998). Rubber hands "feel" touch that eyes see. *Nature*, 391, 756.
> de Vignemont, F. (2011). Embodiment, ownership and disownership. *Consciousness and Cognition*, 20(1), 82-93.

### 2.5 Trust and perceived safety (2 items, exo blocks)

| Item |
|---|
| I felt safe letting the device support me. |
| I trusted the device while I was walking. |

Trust governs whether a person will actually rely on an assistive device outside a laboratory, and perceived safety is a documented determinant of acceptance for wearable robots. Expanded from one item to two in v3.0. The two are deliberately not synonyms: the first is about physical safety in the moment, the second is the general trust judgement.

> Jian, J.-Y., Bisantz, A. M., & Drury, C. G. (2000). Foundations for an empirically determined scale of trust in automated systems. *International Journal of Cognitive Ergonomics*, 4(1), 53-71.
> Lee, J. D., & See, K. A. (2004). Trust in automation: designing for appropriate reliance. *Human Factors*, 46(1), 50-80.
> Körber, M. (2019). Theoretical considerations and development of a questionnaire to measure trust in automation. *Proceedings of IEA 2018*, 13-30.
> Bessler, J., Prange-Lasonder, G. B., Schaake, L., et al. (2021). Safety assessment of rehabilitation robots: a review identifying safety skills and current knowledge gaps. *Frontiers in Robotics and AI*, 8, 602878.

### 2.6 Movement restriction (1 item, exo blocks)

> I felt restricted in how I could move.

Kinematic constraint imposed by the device. A direct and separable cost term: a mode may reduce effort while limiting the movements a person would otherwise make.

### 2.7 Naturalness (1 item, every block)

> The walking felt natural.

Deviation from habitual gait. Asked in every block so the no-exo blocks provide a within-participant reference point, which is necessary because participants differ in how they use the top of the scale.

> Poggensee, K. L., & Collins, S. H. (2021). How adaptation, training, and customization contribute to benefits from exoskeleton assistance. *Science Robotics*, 6(58), eabf1078.

### 2.8 Perceived stability (1 item, every block) — new in v3.0

> I felt steady on my feet.
> *(construct label in the data file: `perceived_stability`)*

The felt sense of security on one's feet during the bout. Added in v3.0 because it is arguably a *stronger* candidate term in the cost function than metabolic cost: people weight fall risk heavily, and a hip device acts directly on pelvis and trunk control.

**This is a percept, not a measurement of stability, and the two can dissociate in both directions.** A device may reduce the margin of stability while feeling reassuring because it supports the pelvis, or improve it while feeling precarious because the assistance arrives at an unexpected moment. That dissociation is the point of including the item: mechanical stability is computed independently from the GRF and IMU streams (margin of stability, step width variability, trunk acceleration variability), and crossing the two is more informative than either alone. What a person optimises is presumably the felt quantity rather than the mechanical one.

It is also deliberately separate from the safety item in 2.5. Trusting the device is not the same as feeling secure on one's own feet. Asked in every block so the no-exo blocks anchor the scale.

Two caveats on the wording. The English phrase fuses "not wobbling" with "not feeling at risk"; the fusion is accepted here because the global sense of security is what would enter a cost function, but the item should not be reported as a clean measure of either component. And the item is *adapted from* the balance-confidence literature rather than taken from it: the ABC scale measures confidence about hypothetical future activities and is closer to a trait, whereas this is a state judgement about the bout just completed. It should not be described as an ABC item.

> Hof, A. L., Gazendam, M. G. J., & Sinke, W. E. (2005). The condition for dynamic stability. *Journal of Biomechanics*, 38(1), 1-8.
> Powell, L. E., & Myers, A. M. (1995). The Activities-specific Balance Confidence (ABC) Scale. *Journals of Gerontology Series A*, 50A(1), M28-M34. (source of the construct, not of the item)
> Adkin, A. L., & Carpenter, M. G. (2018). New insights on emotional contributions to human postural control. *Frontiers in Neurology*, 9, 789.

### 2.9 Attentional demand (1 item, every block)

> I had to concentrate on my walking.

A single-item measure of the mental effort required to walk in this mode. Walking is normally automatic; a mode that forces conscious control of it carries a real cost even when metabolic cost falls.

This replaces the full NASA-TLX used in the original draft. The full instrument, six items repeated eight times, is not justified here: the workload subscales are highly intercorrelated in a task this constrained, and the EEG is a more sensitive index of cognitive load than a self-report subscale. This remains the case after the v3.0 expansion; the extra capacity was spent elsewhere.

> Zijlstra, F. R. H. (1993). *Efficiency in work behaviour: a design approach for modern tools*. Delft University Press. (Rating Scale Mental Effort)
> Hart, S. G., & Staveland, L. E. (1988). Development of NASA-TLX: results of empirical and theoretical research. In *Human Mental Workload*, 139-183.
> Hart, S. G. (2006). NASA-Task Load Index: 20 years later. *Proceedings of the Human Factors and Ergonomics Society*, 50(9), 904-908.

### 2.10 Discomfort (1 branching item, every block)

> Do you have any discomfort or pain right now? → body region(s) → intensity

Discomfort is both an outcome and a confound. It accumulates across a long session, it strongly determines whether a device would be accepted in daily use, and pain-related cortical activity contaminates the EEG. Asking it only at baseline, as the original draft did, made accumulation invisible. The branching structure keeps the cost near zero when the answer is no.

> Corlett, E. N., & Bishop, R. P. (1976). A technique for assessing postural discomfort. *Ergonomics*, 19(2), 175-182.

### 2.11 Overall evaluation (4 items)

| Item | Scale | Blocks |
|---|---|---|
| Overall, how did that way of walking feel? | bipolar, very unpleasant to very pleasant | every block |
| Compared with walking without the device, this walk was | -2 much harder to +2 much easier | exo only, new in v3.0 |
| Compared with the previous walk, this one was | -2 much worse to +2 much better | every block except the first |
| If you had to keep walking for another 30 minutes, would you want the device to support you exactly the way it just did? | yes / not sure / no, I would change it | exo only |

These are the dependent variables the other items are meant to explain. The judgement is captured four ways because each has a different failure mode:

- **Valence** is an absolute rating, vulnerable to ceiling effects and to individual differences in scale use. It is one of the few items that needed no change for the resistive conditions: the pleasant-unpleasant axis is direction-neutral, and the negative half is where a resistive mode is expected to land.
- **Perceived benefit versus no device** is new in v3.0 and fills a real gap: the instrument measured absolute exertion and whether the amount of support was right, but never whether the device made walking easier overall. This is the perceptual counterpart of the metabolic saving and can be compared directly against the calorimetry. Its weakness is that it relies on memory of a no-exo block that may be an hour old, so it should be treated as a coarse comparison.
- **Comparison with the previous block** is a relative judgement. Comparative judgements are typically more sensitive than absolute ones and remain informative when absolute ratings do not separate, which is the classical result underlying paired-comparison scaling. Chained across the eight blocks these give a preference ordering.

  It is deliberately *global* rather than broken down per aspect. Three reasons. It is a dependent variable, so decomposing it into the same aspects used to explain it would make the analysis close to circular; the value of the item is that the participant does the weighting, and that weighting is the cost function under investigation. The per-aspect comparisons are in any case recoverable arithmetically, since every aspect is rated absolutely in every block. And aspect-specific recall across a fifteen-minute gap is largely reconstruction, whereas a global affective comparison survives the delay. The *reason* behind the comparison is collected in the participant's own terms by the third verbal probe rather than by a supplied checklist, which would contaminate that probe.
- **Acceptance** frames the judgement as a decision with a consequence rather than a rating, which tends to sharpen responses. The "no, I would change it" option pairs with the verbal probe that follows.

> Thurstone, L. L. (1927). A law of comparative judgment. *Psychological Review*, 34(4), 273-286.
> David, H. A. (1988). *The Method of Paired Comparisons* (2nd ed.). Griffin.
> Davis, F. D. (1989). Perceived usefulness, perceived ease of use, and user acceptance of information technology. *MIS Quarterly*, 13(3), 319-340.

### 2.12 Structured verbal probe (3 prompts, written or spoken) — new in v3.0

| Prompt | Blocks |
|---|---|
| What did you notice about the device during that walk? | exo blocks |
| Before we start with the device: is anything uncomfortable or distracting right now? | No_Exo_Pre only |
| Now that the device is off again, does anything feel different from before? | No_Exo_Post only |
| If you could change one thing about how it supported you, what would it be? | exo blocks |
| How did this walk compare with the previous one? | every block except the first |

Each prompt can be typed or answered by voice; audio is stored on the tablet and transcribed later. The first prompt takes three forms, one per block type, and they are not cosmetic variants of one question:

- **In exo blocks** it collects reflections on the interaction, which is the primary purpose of the probe.
- **In No_Exo_Pre** it collects apparatus discomfort *before the device is introduced*. The participant is already wearing the cap, the EMG sensors and the harness, and may be unused to the treadmill. Anything uncomfortable at that point is present in every subsequent block too. Without this baseline, a later complaint about pressure or distraction first surfaces in an exo block and will be attributed to the exoskeleton by default. The three answers share an `item_id`, so they are one variable in the data file; the block type distinguishes them.
- **In No_Exo_Post** it collects aftereffects. Changes in how walking feels once the device is removed are of interest in their own right and cannot be asked anywhere else in the protocol.

This replaces the single free-text box in earlier versions and is the largest change in v3.0. It was added after a pilot in which the participant volunteered detailed and specific reflections when asked verbally, and wrote nothing at all in the text box. Verbal report is not a supplement here but the primary channel for anything the fixed scales do not anticipate, and it does not suffer from the scale fatigue that limits how many rating items can be added.

The prompts are fixed and asked in the same order in every block and for every participant, which is what makes the responses comparable across conditions rather than anecdotal. The second prompt is the most valuable of the three, because it asks for a *direction of change* in the participant's own terms and can be read against the signed amount and timing items from page 2.

The prompts deliberately do not list examples such as timing, comfort or effort. Naming them would raise the response rate but contaminate the content, and we could then no longer tell whether a participant mentioned timing because they noticed it or because we suggested it.

**Procedural note.** In practice the experimenter asks each prompt aloud and the participant answers into the tablet. The experimenter's wording must be identical across blocks and participants, and the experimenter should not follow up, prompt, or react while the participant is speaking.

> Ericsson, K. A., & Simon, H. A. (1993). *Protocol Analysis: Verbal Reports as Data* (revised ed.). MIT Press.
> Braun, V., & Clarke, V. (2006). Using thematic analysis in psychology. *Qualitative Research in Psychology*, 3(2), 77-101.
> Patton, M. Q. (2015). *Qualitative Research and Evaluation Methods* (4th ed.). Sage. (standardised open-ended interview format)

---

## 3. Measurement design decisions

**Continuous lines rather than 7-point Likert scales.** With healthy young adults, agency and trust items ceiling at the top of a 7-point scale in every condition and the between-condition variance we need disappears. Continuous visual analogue lines recover some of it. Two details: the marker is invisible until first touched, so there is no midpoint default pulling responses toward the centre, and no numeric value is displayed, so participants cannot arithmetically reproduce their previous block's answer.

**Blinding.** The participant sees "Block 3 of 8" and never the condition code. The experimenter sets the condition on a separate screen.

**Item order randomisation.** Item order within each page is shuffled using a seed derived from participant ID and block number, so the order is randomised but exactly reproducible, and the realised position of every item is written to the output file. This matters more in v3.0 than before, because page 3 now contains several items measuring the same construct and fixed adjacency would encourage answering by position rather than by content. A gating item and the item it reveals always move together.

**Direction-neutral wording (v3.3).** Two of the six exo conditions are resistive. Every item that previously referred to the device's "support" now refers to what the device *did*, and the magnitude scale runs too weak to too strong rather than too little to too much. This matters for two reasons. Asking how much *support* was felt during a resistive block is either answered as zero, which is true and uninformative, or silently reinterpreted, and there is no way afterwards to tell which happened. It also removes a demand characteristic: describing the device as supportive in every question primes an expectation of help in the two conditions where none is given. The trade-off is that the wording is slightly more cumbersome; that is accepted in exchange for items that mean the same thing in all six conditions.

Direction is not lost by this change. It is captured by the perceived-benefit item in 2.11 (much harder to much easier), which is the item that should separate assistive from resistive modes perceptually, and by the signed strength and timing judgements.

**Conditional items.** The timing question appears only when temporal structure was perceived; device items do not appear in no-exo blocks; the comparison items do not appear in the first block. All of these produce missing-by-design cells, which must be modelled as conditional rather than imputed.

**Why the expansion stopped at 28 items.** The limiting resource is not the rest period but the number of distinct judgements a person can make reliably about one walking bout, repeated eight times. Beyond roughly this point participants begin answering the scale rather than the experience, and because all items share a method, a moment and a mood, further items inflate inter-construct correlations without adding independent information. Each additional dependent variable also adds to the multiple-comparison burden, which with six exo conditions grows faster than the information does.

> Couper, M. P., Tourangeau, R., Conrad, F. G., & Singer, E. (2006). Evaluating the effectiveness of visual analog scales. *Social Science Computer Review*, 24(2), 227-245.
> Reips, U.-D., & Funke, F. (2008). Interval-level measurement with visual analogue scales in internet-based research: VAS Generator. *Behavior Research Methods*, 40(3), 699-704.
> Preston, C. C., & Colman, A. M. (2000). Optimal number of response categories in rating scales. *Acta Psychologica*, 104(1), 1-15.
> Podsakoff, P. M., MacKenzie, S. B., Lee, J.-Y., & Podsakoff, N. P. (2003). Common method biases in behavioral research. *Journal of Applied Psychology*, 88(5), 879-903.
> Weijters, B., Cabooter, E., & Schillewaert, N. (2010). The effect of rating scale format on response styles. *International Journal of Research in Marketing*, 27(3), 236-247.

---

## 4. Output

Long-format CSV, one row per item, carrying participant ID, block number, condition code, XDF filename, item ID, construct label, presented position, response value, and response latency relative to the start of the block. Voice recordings are named to the same convention (`P09__b3__exo-5__probe_change.webm`) and appear as rows with their filename and duration. Everything stays on the tablet until exported; nothing is transmitted.

---

## 5. Open points for discussion

1. **Two constructs remain single-item.** Attentional demand and perceived stability are each measured with one item, as are restriction and naturalness. For attentional demand this is deliberate, for the reason in section 2.9. For perceived stability it is provisional: if the pilots show it separating conditions, it is the next candidate for expansion.
2. **Internal consistency has not yet been estimated.** Agency, embodiment and trust now have enough items to compute it, but this requires pilot data. The scales should be reported as short-form proxies until that is done, not as validated instruments.
3. **The verbal probe changes the analysis workload.** Three recordings per block across eight blocks is 24 clips per participant. Transcription and coding need a plan, including who codes, whether a second coder assesses reliability, and how the qualitative themes will be related to the rating scales.
4. **German translation.** The German wording is a working translation and has not been back-translated. Published German versions exist for Borg and should be substituted before running German-speaking participants. One item needs attention specifically: the German rendering of "I felt steady on my feet" uses *sicher*, which carries both "safe" and "steady" and therefore blurs the distinction from the safety item in 2.5 that the English keeps apart. A native speaker should choose between alternatives such as *Ich hatte einen sicheren Stand* and *Ich fühlte mich beim Gehen stabil*.
5. **Ethics amendment for audio.** Voice recordings are personal data and are far less deidentifiable than Likert responses. Capture, storage, transcription and deletion must be covered by the approval and the consent form before further use. Recording can be disabled in the form's configuration in the meantime.
6. **Sample size for the questionnaire side.** The comparative and acceptance items give ordinal data with eight observations per participant. The number of participants needed to fit a preference model is a separate calculation from the EEG power analysis and has not yet been done.