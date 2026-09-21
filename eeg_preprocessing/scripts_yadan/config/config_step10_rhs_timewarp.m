function cfg = config_step10_rhs_timewarp()
% GOAL
%   Define RHS-to-RHS epoching, gait-cycle QC, and make_timewarp settings.
%
% METHOD
%   Store analysis parameters, condition labels, and output names here.
%   Dataset identities come from the subject-level processing table.
%   Step11 reads the current manual IC review when selecting STUDY components.

%% Processing identity

cfg.processingVersion = ...
    "RHS_epoch_timewarp_dynamic";

%% Recompute / AMICA overlap policy

cfg.forceRecompute = false;

% Supported policies:
%   "annotate_only"       - keep otherwise valid epochs and report overlap.
%   "exclude_any_overlap" - reject any epoch containing >=1 AMICA fitting-mask sample.
cfg.amicaBadSamplePolicy = ...
    "annotate_only";

%% Scientific input requirement

cfg.expectedSamplingRateHz = ...
    500;

%% Epoch / gait landmarks

cfg.epochLimitsSec = ...
    [-1 2.5];

cfg.timewarpEventOrder = { ...
    'RHS', ...
    'LTO', ...
    'LHS', ...
    'RTO', ...
    'RHS'};

cfg.baselineLatencyMs = ...
    0;

%% make_timewarp outlier rules

cfg.maxSTDForAbsolute = ...
    3;

cfg.maxSTDForRelative = ...
    3;

cfg.minimumEpochsForTimewarp = ...
    3;

cfg.lowEpochWarningThreshold = ...
    20;

%% Condition order

conditions = config_analysis_conditions();
cfg.conditionOrder = conditions.Code';

cfg.conditionDisplayOrder = conditions.Display';

%% Input / output names

cfg.rhsRootFolderName = ...
    '9_RHS-ERSP-run-separated';

cfg.epochedSetFolderName = ...
    '01_RHS-epoched-sets';

cfg.manifestFileName = ...
    '01_RHS_epoch_manifest.csv';

cfg.qcFileName = ...
    '01_RHS_epoch_QC.csv';

cfg.recommendedCycleRelativePath = fullfile( ...
    'grf_quality_check', ...
    'GRF_RHS_timewarp_cycles_recommended_all_subjects.csv');

end
