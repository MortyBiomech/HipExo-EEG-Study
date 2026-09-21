function cfg = config_step11_rhs_epoched_study()
% GOAL
%   Define metadata and output settings for the run-separated RHS STUDY.
%
% INPUT
%   None.
%
% OUTPUT
%   cfg - settings used by step11_create_rhs_epoched_study.m.
%
% METHOD
%   Store STUDY metadata, condition ordering, and output names here.
%   Dataset identities and run coverage come from the Step10 manifest.
%   Component selections come from the current identity-bound manual review.

%% Processing identity

cfg.processingVersion = ...
    "RHS_epoched_STUDY_dynamic_reuse";

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

cfg.forceRebuild = false;

%% Input / output names

cfg.rhsRootFolderName = ...
    '9_RHS-ERSP-run-separated';

cfg.epochedSetFolderName = ...
    '01_RHS-epoched-sets';

cfg.manifestFileName = ...
    '01_RHS_epoch_manifest.csv';

cfg.studyFolderName = ...
    '02_RHS-epoched-STUDY';

cfg.datasetInfoCSVName = ...
    '02_RHS_epoched_STUDY_datasetinfo.csv';

%% Condition order

conditions = config_analysis_conditions();
cfg.conditionOrder = conditions.Code';

end
