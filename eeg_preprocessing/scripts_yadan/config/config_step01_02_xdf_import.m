function cfg = config_step01_02_xdf_import()
% GOAL
%   Define the parameters used to scan XDF streams and build the run-level
%   EEG/GRF import-control table.
% METHOD
%   Keep stream identity, structural QC thresholds, and default import gates
%   in one place so these rules are not duplicated across the two scripts.

%% Step 01 - XDF stream inspection

cfg.eeg.streamName = "LiveAmpSN-102108-1139";
cfg.eeg.nominalSrateHz = 500;
cfg.eeg.minimumChannelCount = 10;
cfg.eeg.minimumDurationSec = 120;

cfg.eeg.absoluteSrateToleranceHz = 2;
cfg.eeg.relativeSrateTolerance = 0.004;

cfg.grf.streamName = "GRF";
cfg.grf.streamType = "Force";
cfg.grf.expectedChannelCount = 8;
cfg.grf.minimumDurationSec = 120;

% Absolute ceiling for timestamp discontinuities.
% The current scanner also computes a stricter stream-specific robust limit:
% min(maximumGapSec, max(minimumRobustGapSec, robustGapFactor * medianDt)).
cfg.timestamp.maximumGapSec = 0.10;
cfg.timestamp.minimumRobustGapSec = 0.020;
cfg.timestamp.robustGapFactor = 10;

cfg.scan.saveEveryNFiles = 5;

%% Step 02 - import table

cfg.import.allowedRunNumbers = [1 2];

% Match only XDF filename suffixes such as:
%   _old.xdf
%   _old1.xdf
%   _old2.xdf
cfg.import.oldFileRegex = '_old\d*\.xdf$';

% These rows remain visible in the table but are disabled by default.
cfg.import.nonWalkingPathWords = [ ...
    "calibration", ...
    "maziarcheck"];

end
