function cfg = config_bids_standardization()
% GOAL
%   Configure the mandatory canonical data-entry layer:
%       XDF -> BIDS -> run-separated EEGLAB .set
%
% SCIENTIFIC / DATA-MANAGEMENT POLICY
%   1. BIDS is the canonical standardized raw EEG layer.
%   2. Every downstream EEG analysis must start from an EEGLAB .set that
%      was created from the corresponding BIDS EEG recording.
%   3. The source XDF remains immutable timing provenance for LSL/GRF only.
%   4. No resampling is allowed in the BIDS -> run-separated EEGLAB step,
%      because GRF events are mapped by source-XDF EEG sample identity.
%   5. Participant labels are canonicalized as sub-01, sub-02, ... . The
%      original acquisition identity is retained only in the manifest.
%
% IMPORTANT BEMOBIL DETAIL
%   bemobil_bids2set merges runs within a session by design. HipExo needs
%   run-separated EEG for GRF/LSL mapping, so the canonical analysis input
%   is created recording-by-recording from the exported BIDS EEG files.
%   An optional BeMoBIL merged mirror can still be generated for comparison,
%   but it is never used as the Step 03 EEG source.

cfg.processingVersion = "HipExo_BIDS_first_v3_2026-08-29";

%% Canonical participant identity
cfg.subjectLabelWidth = 2;          % 1 -> sub-01, 10 -> sub-10
cfg.originalSubjectPrefix = "sub-Pilot";

%% XDF -> BIDS
cfg.cleanKnownSessionsBeforeExport = false;
cfg.overwrite = 'on';
cfg.otherDataTypes = {};

%% BIDS -> EEGLAB canonical recording mirror
cfg.createRunSeparatedEEGLAB = true;
cfg.cleanRunSeparatedEEGLABBeforeConvert = false;

% BrainVision reader policy is automatic. Step 02B starts EEGLAB first,
% then prefers pop_loadbv (bva-io) when available and otherwise falls back
% to pop_fileio + FieldTrip/FileIO. bva-io is therefore recommended but is
% not a hard dependency when FieldTrip/FileIO is available.

% CRITICAL: do not resample at this stage. The BIDS-derived .set must keep
% one-to-one sample identity with the EEG samples exported from the source
% XDF. Resampling belongs later in the processing pipeline if scientifically
% required.
cfg.resampleDuringBidsToEEGLAB = false;

% Use a BIDS-derivative-like filename without pretending the .set itself is
% raw BIDS data. Example:
%   sub-01_ses-day2Exo1Sport_task-Default_run-001_desc-bidsraw_eeg.set
cfg.runSeparatedDescLabel = 'bidsraw';

% Optional compatibility/reference output. bemobil_bids2set merges runs and
% sessions according to its own convention, so this output is not used by
% Step 03 and is disabled by default.
cfg.createBemobilMergedMirror = false;
cfg.bemobilMergedMirrorFolderName = '2_raw-EEGLAB_bemobil-merged-reference';
cfg.bemobilMergedTargetSrateHz = 500;

%% BIDS metadata
cfg.metadata.bidsVersion = '1.11.1';
cfg.metadata.datasetName = 'HipExo-EEG';
cfg.metadata.license = 'n/a';
cfg.metadata.authors = {'n/a'};
cfg.metadata.acknowledgements = 'n/a';
cfg.metadata.funding = {'n/a'};
cfg.metadata.referencesAndLinks = {'n/a'};
cfg.metadata.datasetDOI = 'n/a';

cfg.metadata.institutionName = 'TU Darmstadt';
cfg.metadata.institutionDepartmentName = 'n/a';
cfg.metadata.institutionAddress = 'Darmstadt, Germany';
cfg.metadata.taskDescription = ...
    'EEG recorded during treadmill walking with hip-exoskeleton conditions.';

cfg.metadata.participantColumns = {'nr', 'age', 'sex', 'handedness'};

%% Validation / release gates
cfg.requireBidsStructureAuditPass = true;
cfg.requireRunSeparatedEEGLABPass = true;
cfg.runExternalBidsValidator = false;
cfg.warnOnPlaceholderPublicationMetadata = true;

end
