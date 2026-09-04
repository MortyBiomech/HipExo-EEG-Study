function cfg = config_step11_rhs_epoched_study()
% GOAL
%   Define metadata and output settings for the run-separated RHS STUDY.
%
% METHOD
%   Store STUDY metadata, condition ordering, and output names here.
%   Dataset identities, dataset counts, run coverage, and IC selections are
%   read from the current Step 10 manifest.

%% Processing identity

cfg.processingVersion = ...
    "RHS_epoched_STUDY_dynamic";

%% STUDY metadata

cfg.studyName = ...
    'HipExo_RHS_epoched_run_separated';

cfg.studyFilename = ...
    [cfg.studyName '.study'];

cfg.groupLabel = ...
    'HipExo';

cfg.sharedICASession = ...
    1;

%% Rebuild behavior

cfg.forceRebuild = true;

%% Input / output names

cfg.rhsRootFolderName = ...
    '9_RHS-ERSP-run-separated';

cfg.epochedSetFolderName = ...
    '01_RHS-epoched-sets';

cfg.manifestFileName = ...
    '01_RHS_epoch_manifest.csv';

cfg.studyFolderName = ...
    '02_RHS-epoched-STUDY';

%% Condition order

cfg.conditionOrder = [ ...
    "NoExoPre", ...
    "AquaPlus", ...
    "Aqua", ...
    "Transparent", ...
    "Exo", ...
    "Sport", ...
    "Boost", ...
    "NoExoPost"];

end
