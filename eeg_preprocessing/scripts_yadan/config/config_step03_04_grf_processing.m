function cfg = config_step03_04_grf_processing()
% GOAL
%   Define the parameters used for GRF extraction, walking-interval
%   segmentation, gait-event detection, GRF-to-EEG mapping, and gait-cycle QC.
% METHOD
%   Preserve the current working GRF parameters while exposing the values
%   that are scientifically or operationally useful to tune later.

%% Step 03A - walking-interval segmentation

% "auto":
%   use valid GRF markers when available; otherwise use GRF activity.
% "manual":
%   ignore GRF markers and select intervals manually.
cfg.segmentation.mode = "auto";

cfg.segmentation.excludedMarkerWords = [ ...
    "STANDING", ...
    "REST", ...
    "CALIBRATION"];

% Automatic GRF-activity segmentation.
% These values are taken from the current detect_walking_intervals logic.
cfg.segmentation.activityLowQuantile = 0.10;
cfg.segmentation.activityHighQuantile = 0.75;
cfg.segmentation.thresholdFraction = 0.35;
cfg.segmentation.confirmationWindowSec = 2.0;
cfg.segmentation.minimumActiveFraction = 0.75;
cfg.segmentation.maximumInactiveGapSec = 3.0;
cfg.segmentation.minimumWalkingDurationSec = 10.0;
cfg.segmentation.transitionMarginSec = 2.0;

%% Step 03B - GRF gait-event detection

cfg.detection.rightChannels = [1 4 5 8];
cfg.detection.leftChannels  = [2 3 6 7];

cfg.detection.lowpassHz = 15;

cfg.detection.thresholdOn = 0.03;
cfg.detection.thresholdOff = 0.02;

cfg.detection.minimumContactSec = 0.20;
cfg.detection.maximumContactSec = 1.50;
cfg.detection.minimumStrideSec = 0.60;

cfg.detection.qcZoomWindowSec = 15;

%% Step 03C - GRF-to-EEG mapping

cfg.mapping.expectedEEGStreamName = "LiveAmpSN-102108-1139";
cfg.mapping.expectedEEGChannels = 64;
cfg.mapping.expectedAuxiliaryLabels = ["ACC_X", "ACC_Y", "ACC_Z"];
cfg.mapping.targetEEGSrateHz = 500;

cfg.mapping.maximumMappingErrorMs = 5;

cfg.mapping.timestampGapFactor = 10;
cfg.mapping.minimumTimestampGapSec = 0.020;

%% Step 03D - subject-level batch defaults

cfg.batch.forceReprocess = false;
cfg.batch.forceGRFExtraction = false;
cfg.batch.forceGaitDetection = false;
cfg.batch.forceEEGMapping = false;
cfg.batch.forceConcatenation = false;

cfg.batch.concatenateSessions = true;
cfg.batch.allowPartialSubject = false;

%% Step 04 - gait-cycle QC

cfg.cycleQC.excludeFirstAndLastCycle = true;
cfg.cycleQC.minimumStrideSec = 0.60;
cfg.cycleQC.maximumStrideSec = 2.00;
cfg.cycleQC.robustOutlierZ = 3.5;

cfg.cycleQC.expectedEventOrder = ...
    ["RHS", "LTO", "LHS", "RTO", "RHS"];

end
