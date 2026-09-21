function step10_rhs_ICA_reuse_v7_fastlean()
% GOAL
%   Create run-separated RHS-to-RHS EEG epochs and gait-landmark latency
%   matrices for time-warped ERSP analysis.
%
% INPUT
%   Step08 subject-level processing table
%   Step 08 ICA-QC-approved preprocessed_and_ICA datasets.
%   Current subject-level raw combined EEG with gait events.
%   Step 04 GRF_RHS_timewarp_cycles_recommended_all_subjects.csv.
%
% APPROACH
%   1. Read continuous shared-ICA sources that passed Step08 QC.
%   2. Load one continuous preprocessed_and_ICA dataset per subject.
%   3. Synchronize the latest gait events from the current raw combined EEG.
%   4. Separate the continuous data logically by condition and run.
%   5. Find RHS events as candidate gait-cycle anchors.
%   6. Keep only gait cycles recommended by the Step 04 gait-cycle QC.
%   7. Verify the complete gait-event sequence:
%      RHS -> LTO -> LHS -> RTO -> next RHS.
%   8. Epoch the EEG around RHS, with RHS at time zero.
%   9. Run EEGLAB make_timewarp() on the accepted gait cycles.
%  10. Store the five gait-event latencies for each accepted cycle.
%  11. Save one RHS-epoched dataset per condition and run.
%
% OUTPUT
%   9_RHS-ERSP-run-separated/01_RHS-epoched-sets/*
%   9_RHS-ERSP-run-separated/01_RHS_epoch_manifest.csv
%   9_RHS-ERSP-run-separated/01_RHS_epoch_QC.csv
%
% USED BY
%   step11_create_rhs_epoched_study.m

clear;
clc;

%% Settings and paths

thisFile = mfilename('fullpath');
if isempty(thisFile)
    error('Could not resolve the current Step file path.');
end
scriptsRoot = fileparts(fileparts(thisFile));

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step10_rhs_timewarp();

processingVersion = cfg.processingVersion;
amicaBadSamplePolicy = string(cfg.amicaBadSamplePolicy);
allowedAMICABadSamplePolicies = ["annotate_only", "exclude_any_overlap"];
assert(isscalar(amicaBadSamplePolicy) && ...
    ismember(amicaBadSamplePolicy, allowedAMICABadSamplePolicies), ...
    'Unsupported cfg.amicaBadSamplePolicy: %s', char(amicaBadSamplePolicy));
forceRecompute = cfg.forceRecompute;

epochLimitsSec = cfg.epochLimitsSec;
timewarpEventOrder = cfg.timewarpEventOrder;
baselineLatencyMs = cfg.baselineLatencyMs;
maxSTDForAbsolute = cfg.maxSTDForAbsolute;
maxSTDForRelative = cfg.maxSTDForRelative;

minimumEpochsForTimewarp = cfg.minimumEpochsForTimewarp;
lowEpochWarningThreshold = cfg.lowEpochWarningThreshold;
expectedSamplingRateHz = cfg.expectedSamplingRateHz;

conditionOrder = cfg.conditionOrder;
conditionDisplayOrder = cfg.conditionDisplayOrder;

outputFolder = P.outputFolder;
eeglabFolder = P.eeglabFolder;
grfSegmentationFolder = P.grfSegmentationFolder;

if exist('eeglab', 'file') ~= 2
    error('EEGLAB was not found after loading project_paths.m.');
end

% Start EEGLAB before checking make_timewarp. EEGLAB manages its own
% subfolder order; do not add the full EEGLAB tree with genpath.
eeglab('nogui');

makeTimewarpFile = which('make_timewarp');

if isempty(makeTimewarpFile)
    eeglabMiscfuncFolder = fullfile( ...
        eeglabFolder, ...
        'functions', ...
        'miscfunc');

    expectedMakeTimewarpFile = fullfile( ...
        eeglabMiscfuncFolder, ...
        'make_timewarp.m');

    if isfile(expectedMakeTimewarpFile)
        addpath(eeglabMiscfuncFolder, '-begin');
        rehash;
        makeTimewarpFile = which('make_timewarp');
    end
end

if isempty(makeTimewarpFile)
    expectedMakeTimewarpFile = fullfile( ...
        eeglabFolder, ...
        'functions', ...
        'miscfunc', ...
        'make_timewarp.m');

    error([ ...
        'EEGLAB started, but make_timewarp.m is still unavailable.\n' ...
        'Expected location:\n%s\n' ...
        'Check whether the EEGLAB installation is complete.'], ...
        expectedMakeTimewarpFile);
end

%% Subject-level sources with completed ICA QC
mappingFile = P.subjectLevelEEGTableFile;
subjectSpecs = load_subject_sources_local(mappingFile);

outputRoot = fullfile( ...
    outputFolder, ...
    cfg.rhsRootFolderName);

epochedSetRoot = fullfile( ...
    outputRoot, ...
    cfg.epochedSetFolderName);

manifestFile = fullfile( ...
    outputRoot, ...
    cfg.manifestFileName);

qcFile = fullfile( ...
    outputRoot, ...
    cfg.qcFileName);

recommendedCycleFile = fullfile( ...
    grfSegmentationFolder, ...
    cfg.recommendedCycleRelativePath);

if exist(recommendedCycleFile, 'file') ~= 2
    error([ ...
        'The GRF gait-cycle QC gate is missing:\n%s\n' ...
        'Run step04_check_grf_gait_cycles.m before RHS epoching.'], ...
        recommendedCycleFile);
end

recommendedCycles = load_recommended_cycles_local( ...
    recommendedCycleFile);

if ~exist(outputRoot, 'dir')
    mkdir(outputRoot);
end

if ~exist(epochedSetRoot, 'dir')
    mkdir(epochedSetRoot);
end

manifest = empty_manifest_local();
epochQC = empty_epoch_qc_local();

%% Process all current subjects

for s = 1:numel(subjectSpecs)

    spec = subjectSpecs(s);
    sourceSet = char(spec.sourceSet);

    if exist(sourceSet, 'file') ~= 2
        error('Required source dataset was not found:\n%s', sourceSet);
    end

    fprintf('Subject %d / %d: %s\n', ...
        s, numel(subjectSpecs), char(spec.subject));

    [sourceFolder, sourceName, sourceExt] = fileparts(sourceSet);

    EEGsource = pop_loadset( ...
        'filename', [sourceName sourceExt], ...
        'filepath', sourceFolder, 'loadmode', 'info');

    % Keep the ICA exactly as loaded for Step09/Step11, before event updates.
    sourceICA = struct();
    sourceICAFields = {'nbchan', 'chanlocs', 'icaweights', 'icasphere', ...
        'icawinv', 'icachansind', 'dipfit'};
    for f = 1:numel(sourceICAFields)
        fieldName = sourceICAFields{f};
        sourceICA.(fieldName) = EEGsource.(fieldName);
    end
    sourceICAIdentity = hipexo.ica_identity_signature(sourceICA);

    EEGsource = synchronize_current_raw_events_local( ...
        EEGsource, ...
        spec.eventSourceSet);

    sourceInfo = validate_source_dataset_local( ...
        EEGsource, ...
        spec.subject, ...
        expectedSamplingRateHz, ...
        spec.amicaInputSignature, spec.prefinalSignature);

    % Lightweight identities for provenance/reuse. Do not load the large
    % continuous .fdt files merely to decide whether an existing run is reusable.
    currentAMICASourceSignature = amica_source_signature_local(EEGsource);
    sourceSignature = hipexo.content_signature(struct( ...
        'amicaSource', currentAMICASourceSignature, ...
        'icaIdentity', sourceICAIdentity));
    eventSourceSignature = hipexo.content_signature(EEGsource.event);

    % Keep legacy input signatures under the user's original EEGLAB options.
    % Disable RMS rescaling only for epoch processing/repair/save operations.
    restoreRMS = suspend_ica_rms_local(); %#ok<NASGU>

    eventTypes = event_type_strings_local(EEGsource.event);
    sourceIndices = event_numeric_field_local( ...
        EEGsource.event, ...
        'source_recording_index');

    startMask = eventTypes == "RECORDING_START";
    recordingIndices = unique(sourceIndices(startMask), 'sorted');
    recordingIndices = recordingIndices(isfinite(recordingIndices));

    if isempty(recordingIndices)
        error('No valid recording_start events were found in %s.', sourceSet);
    end

    for r = 1:numel(recordingIndices)

        sourceRecordingIndex = recordingIndices(r);

        recording = recording_metadata_local( ...
            EEGsource, ...
            sourceRecordingIndex, ...
            conditionOrder, ...
            conditionDisplayOrder);

        recordingQC = screen_rhs_cycles_local( ...
            EEGsource, ...
            spec.subject, ...
            spec.datasetLabel, ...
            recording, ...
            epochLimitsSec, ...
            recommendedCycles, ...
            amicaBadSamplePolicy);

        nCandidateRHS = height(recordingQC);
        nRecommendedRHS = sum( ...
            recordingQC.RecommendedCycleMatched);
        nAMICAOverlapEpochs = sum( ...
            recordingQC.HasAMICABadSampleOverlap);
        validMask = recordingQC.PreQCStatus == "included";
        validAnchorIDs = recordingQC.RHSAnchorID(validMask);
        nPreQCAccepted = numel(validAnchorIDs);

        outputSubjectFolder = fullfile( ...
            epochedSetRoot, ...
            char(spec.datasetLabel));

        if ~exist(outputSubjectFolder, 'dir')
            mkdir(outputSubjectFolder);
        end

        outputStem = sprintf( ...
            '%s_%s_run-%02d_RHS_epoched_timewarp', ...
            char(spec.datasetLabel), ...
            char(recording.conditionCode), ...
            recording.runNumber);

        outputSetFile = [outputStem '.set'];
        outputSetPath = fullfile( ...
            outputSubjectFolder, ...
            outputSetFile);

        recommendedCycleSignature = hipexo.content_signature( ...
            sort(recordingQC.RecommendedCycleKey(recordingQC.RecommendedCycleMatched)));
        processingSignature = processing_signature_local( ...
            sourceSignature, ...
            eventSourceSignature, ...
            recommendedCycleSignature, ...
            sourceRecordingIndex, ...
            epochLimitsSec, ...
            maxSTDForAbsolute, ...
            maxSTDForRelative, ...
            amicaBadSamplePolicy, cfg);

        if nPreQCAccepted < minimumEpochsForTimewarp

            warning([ ...
                '%s %s run %d has only %d valid cycles before ' ...
                'timewarp. No dataset will be saved.'], ...
                char(spec.subject), ...
                char(recording.conditionCode), ...
                recording.runNumber, ...
                nPreQCAccepted);

            recordingQC.TimewarpStatus(validMask) = ...
                "not_run_too_few_preQC_epochs";

            manifestRow = make_manifest_row_local( ...
                s, ...
                spec, ...
                recording, ...
                sourceSet, ...
                "", ...
                nCandidateRHS, ...
                nRecommendedRHS, ...
                nAMICAOverlapEpochs, ...
                nPreQCAccepted, ...
                0, ...
                [], ...
                epochLimitsSec, ...
                "skipped_too_few_preQC_epochs", ...
                processingVersion);

            manifest = [manifest; manifestRow]; %#ok<AGROW>
            epochQC = [epochQC; recordingQC]; %#ok<AGROW>

            write_current_tables_local( ...
                manifest, epochQC, manifestFile, qcFile);

            continue;
        end

        reuseOutput = false;

        if exist(outputSetPath, 'file') == 2 && ~forceRecompute
            try
                EEGout = pop_loadset( ...
                    'filename', outputSetFile, ...
                    'filepath', outputSubjectFolder, ...
                    'loadmode', 'info');

                assert_reusable_output_local( ...
                    EEGout, EEGsource, sourceICAIdentity, recording, ...
                    validAnchorIDs, recommendedCycleSignature, ...
                    epochLimitsSec, timewarpEventOrder, baselineLatencyMs, ...
                    maxSTDForAbsolute, maxSTDForRelative, amicaBadSamplePolicy);

                reuseOutput = true;

            catch reuseME
                warning([ ...
                    'Existing output cannot be reused and will be rebuilt. ' ...
                    'Reason: %s'], reuseME.message);
            end
        end

        if ~reuseOutput
            if ~isnumeric(EEGsource.data) || isempty(EEGsource.data)
                sourceData = pop_loadset('filename', [sourceName sourceExt], ...
                    'filepath', sourceFolder);
                EEGsource.data = sourceData.data;
                clear sourceData
            end

            EEGep = epoch_one_recording_local( ...
                EEGsource, ...
                sourceRecordingIndex, ...
                validAnchorIDs, ...
                epochLimitsSec);

            preTimewarpAnchorIDs = ...
                anchor_ids_from_epochs_local(EEGep);

            try
                rawTimewarp = make_timewarp( ...
                    EEGep, ...
                    timewarpEventOrder, ...
                    'baselineLatency', baselineLatencyMs, ...
                    'maxSTDForAbsolute', maxSTDForAbsolute, ...
                    'maxSTDForRelative', maxSTDForRelative);
            catch timewarpME
                error([ ...
                    'make_timewarp failed for %s, %s, run %d.\n%s'], ...
                    char(spec.subject), ...
                    char(recording.conditionCode), ...
                    recording.runNumber, ...
                    timewarpME.message);
            end

            [acceptedEpochs, acceptedLatencies] = ...
                normalized_timewarp_rows_local( ...
                    rawTimewarp, ...
                    EEGep.trials, ...
                    numel(timewarpEventOrder), ...
                    EEGep.srate);

            if isempty(acceptedEpochs)
                error([ ...
                    'make_timewarp rejected every epoch for %s, %s, ' ...
                    'run %d.'], ...
                    char(spec.subject), ...
                    char(recording.conditionCode), ...
                    recording.runNumber);
            end

            finalAnchorIDs = preTimewarpAnchorIDs(acceptedEpochs);

            [foundFinalAnchors, finalQCRow] = ismember( ...
                finalAnchorIDs(:), recordingQC.RHSAnchorID);

            if ~all(foundFinalAnchors)
                error(['Could not map every final epoch back to its ' ...
                    'AMICA-overlap QC annotation.']);
            end

            EEGout = pop_select( ...
                EEGep, ...
                'trial', acceptedEpochs);

            finalTimewarp = rawTimewarp;
            finalTimewarp.latencies = acceptedLatencies;
            finalTimewarp.epochs = (1:EEGout.trials)';
            finalTimewarp.warpto = median(acceptedLatencies, 1);
            finalTimewarp.medianlatency = ...
                finalTimewarp.warpto(end);

            EEGout.timewarp = finalTimewarp;

            EEGout.subject = char(spec.subject);
            EEGout.condition = char(recording.conditionCode);
            EEGout.session = recording.runNumber;
            EEGout.group = EEGsource.group;
            EEGout.setname = outputStem;

            EEGout = remove_continuous_qc_masks_local(EEGout);

            processingInfo = struct();
            processingInfo.version = char(processingVersion);
            processingInfo.created_on = char(datetime( ...
                'now', ...
                'Format', 'yyyy-MM-dd HH:mm:ss'));
            processingInfo.source_set_path = sourceSet;
            processingInfo.source_set_signature = char(sourceSignature);
            processingInfo.source_ica_identity = char(sourceICAIdentity);
            processingInfo.event_source_set_path = char(spec.eventSourceSet);
            processingInfo.event_source_set_signature = ...
                char(eventSourceSignature);
            processingInfo.recommended_cycle_table_path = ...
                recommendedCycleFile;
            processingInfo.recommended_cycle_table_signature = ...
                char(recommendedCycleSignature);
            processingInfo.processing_signature = ...
                char(processingSignature);
            processingInfo.source_recording_index = ...
                sourceRecordingIndex;
            processingInfo.source_recording = ...
                char(recording.sourceRecording);
            processingInfo.condition_code = ...
                char(recording.conditionCode);
            processingInfo.condition_display = ...
                char(recording.conditionDisplay);
            processingInfo.run_number = recording.runNumber;
            processingInfo.epoch_limits_sec = epochLimitsSec;
            processingInfo.timewarp_event_order = timewarpEventOrder;
            processingInfo.baseline_latency_ms = baselineLatencyMs;
            processingInfo.max_std_absolute = maxSTDForAbsolute;
            processingInfo.max_std_relative = maxSTDForRelative;
            processingInfo.ic_selection_stage = 'Step11 current manual IC review';
            processingInfo.source_ica_count = sourceInfo.nICs;
            processingInfo.source_bad_sample_count = ...
                sourceInfo.badSampleCount;
            processingInfo.source_bad_sample_percent = ...
                sourceInfo.badSamplePercent;
            processingInfo.amica_bad_sample_policy = ...
                char(amicaBadSamplePolicy);
            processingInfo.amica_overlap_is_rejection = ...
                strcmp(amicaBadSamplePolicy, "exclude_any_overlap");
            processingInfo.candidate_rhs_count = nCandidateRHS;
            processingInfo.recommended_rhs_count = nRecommendedRHS;
            processingInfo.candidate_amica_overlap_count = ...
                nAMICAOverlapEpochs;
            processingInfo.pre_qc_accepted_count = ...
                nPreQCAccepted;
            processingInfo.make_timewarp_accepted_count = ...
                EEGout.trials;
            processingInfo.pre_timewarp_rhs_anchor_ids = ...
                preTimewarpAnchorIDs(:)';
            processingInfo.accepted_rhs_anchor_ids = ...
                finalAnchorIDs(:)';
            processingInfo.final_epoch_amica_bad_sample_count = ...
                recordingQC.AMICABadSampleCount(finalQCRow)';
            processingInfo.final_epoch_amica_bad_sample_percent = ...
                recordingQC.AMICABadSamplePercent(finalQCRow)';
            processingInfo.final_epoch_has_amica_bad_sample_overlap = ...
                recordingQC.HasAMICABadSampleOverlap(finalQCRow)';
            processingInfo.timewarp_warpto_ms = ...
                finalTimewarp.warpto;
            processingInfo.signal_timewarped = false;
            processingInfo.note = [ ...
                'EEG.timewarp contains per-trial gait-event latencies. ' ...
                'Only cycles listed by step04_check_grf_gait_cycles.m as ' ...
                'RecommendedForEpoch are eligible. ' ...
                sprintf('AMICA bad-sample policy: %s. ', char(amicaBadSamplePolicy)) ...
                'The signal is warped later during ERSP calculation.'];

            if ~isfield(EEGout, 'etc') || isempty(EEGout.etc)
                EEGout.etc = struct();
            end

            EEGout.etc.rhs_epoching = processingInfo;

            % Only epochs were selected; preserve the reviewed source ICA.
            EEGout = preserve_source_ica_local( ...
                EEGout, sourceICA, sourceICAIdentity);

        else
            finalAnchorIDs = ...
                EEGout.etc.rhs_epoching.accepted_rhs_anchor_ids(:);
        end

        if ~reuseOutput
            EEGout = pop_saveset( ...
                EEGout, ...
                'filename', outputSetFile, ...
                'filepath', outputSubjectFolder, ...
                'savemode', 'twofiles');

            if exist(outputSetPath, 'file') ~= 2
                error('pop_saveset did not create:\n%s', outputSetPath);
            end

            % Check the saved header through the same load mode as Step11.
            EEGsaved = pop_loadset('filename', outputSetFile, ...
                'filepath', outputSubjectFolder, 'loadmode', 'info');
            assert(hipexo.ica_identity_signature(EEGsaved) == sourceICAIdentity, ...
                ['Saved RHS dataset ICA differs from the reviewed source. ' ...
                 'Do not proceed to Step11. Dataset: %s'], outputSetPath);
            clear EEGsaved
        end

        if reuseOutput
            fprintf('Reused unchanged output: %s\n', outputSetFile);
        end

        nFinalEpochs = EEGout.trials;

        if nFinalEpochs < lowEpochWarningThreshold
            warning([ ...
                '%s %s run %d has only %d final epochs. Keep the ' ...
                'dataset, but review it before ERSP interpretation.'], ...
                char(spec.subject), ...
                char(recording.conditionCode), ...
                recording.runNumber, ...
                nFinalEpochs);
        end

        recordingQC = add_timewarp_result_to_qc_local( ...
            recordingQC, ...
            finalAnchorIDs);

        status = "completed";
        if reuseOutput
            status = "reused_verified_output";
        end

        manifestRow = make_manifest_row_local( ...
            s, ...
            spec, ...
            recording, ...
            sourceSet, ...
            outputSetPath, ...
            nCandidateRHS, ...
            nRecommendedRHS, ...
            nAMICAOverlapEpochs, ...
            nPreQCAccepted, ...
            nFinalEpochs, ...
            EEGout.timewarp.warpto, ...
            epochLimitsSec, ...
            status, ...
            processingVersion);

        manifest = [manifest; manifestRow]; %#ok<AGROW>
        epochQC = [epochQC; recordingQC]; %#ok<AGROW>

        write_current_tables_local( ...
            manifest, epochQC, manifestFile, qcFile);

        clear EEGep EEGout rawTimewarp;
    end

    clear EEGsource;
    clear restoreRMS; % Restore the option before the next subject's signatures.
end

%% Final tables and coverage report

write_current_tables_local( ...
    manifest, epochQC, manifestFile, qcFile);

%% Local functions

end

% FUNCTION: add_timewarp_result_to_qc_local.m

function qc = add_timewarp_result_to_qc_local(qc, finalAnchorIDs)

    preAccepted = qc.PreQCStatus == "included";
    qc.TimewarpStatus(preAccepted) = "rejected_by_make_timewarp";

    for k = 1:numel(finalAnchorIDs)
        row = find(qc.RHSAnchorID == finalAnchorIDs(k));

        if numel(row) ~= 1
            error('Could not map final RHS anchor ID %d to the QC table.', ...
                finalAnchorIDs(k));
        end

        qc.TimewarpStatus(row) = "accepted";
        qc.FinalEpochIndex(row) = k;
    end
end

function anchorIDs = anchor_ids_from_epochs_local(EEG)

    if EEG.trials < 1 || isempty(EEG.epoch)
        error('Expected an epoched EEG dataset with EEG.epoch metadata.');
    end

    anchorIDs = nan(EEG.trials, 1);
    zeroToleranceMs = 1000 / EEG.srate + 1e-6;

    for trial = 1:EEG.trials
        eventIndices = numeric_vector_local(EEG.epoch(trial).event);
        eventLatencies = numeric_vector_local( ...
            EEG.epoch(trial).eventlatency);

        if numel(eventIndices) ~= numel(eventLatencies)
            error('EEG.epoch event indices and latencies do not align.');
        end

        ids = nan(size(eventIndices));
        types = strings(size(eventIndices));

        for k = 1:numel(eventIndices)
            eventIndex = eventIndices(k);
            if eventIndex >= 1 && eventIndex <= numel(EEG.event) && ...
                    isfield(EEG.event, 'rhs_anchor_id')
                value = EEG.event(eventIndex).rhs_anchor_id;
                types(k) = upper(strtrim(string( ...
                    EEG.event(eventIndex).type)));
                if isnumeric(value) && isscalar(value) && isfinite(value)
                    ids(k) = double(value);
                end
            end
        end

        candidate = find( ...
            isfinite(ids) & ...
            types == "RHS" & ...
            abs(eventLatencies) <= zeroToleranceMs);

        if numel(candidate) ~= 1
            error([ ...
                'Expected one zero-latency RHS anchor in epoch %d, ' ...
                'but found %d.'], ...
                trial, numel(candidate));
        end

        anchorIDs(trial) = ids(candidate);
    end
end

function key = canonical_subject_key_local(value)
    key = lower(regexprep(strtrim(string(value)), '[^a-zA-Z0-9]', ''));
    key = regexprep(key, '^sub', '');
end

function tableOut = empty_epoch_qc_local()

    tableOut = table( ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        strings(0, 1), ...
        false(0, 1), ...
        zeros(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        false(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        'VariableNames', { ...
            'Subject', ...
            'DatasetLabel', ...
            'ConditionCode', ...
            'ConditionDisplay', ...
            'RunNumber', ...
            'SourceRecordingIndex', ...
            'SourceRecording', ...
            'RHSAnchorID', ...
            'RHSLatencySamples', ...
            'RHSLSLTime', ...
            'GRFSegmentIndex', ...
            'SourceXDF', ...
            'RecommendedCycleMatched', ...
            'RecommendedCycleRow', ...
            'RecommendedCycleKey', ...
            'PreQCStatus', ...
            'PreQCReason', ...
            'TimewarpStatus', ...
            'FinalEpochIndex', ...
            'HasAMICABadSampleOverlap', ...
            'AMICABadSampleCount', ...
            'AMICABadSamplePercent'});
end

function tableOut = empty_manifest_local()

    tableOut = table( ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        zeros(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        'VariableNames', { ...
            'SubjectOrder', ...
            'ConditionOrder', ...
            'Subject', ...
            'DatasetLabel', ...
            'ConditionCode', ...
            'ConditionDisplay', ...
            'RunNumber', ...
            'SourceRecordingIndex', ...
            'SourceRecording', ...
            'SourceSet', ...
            'OutputSet', ...
            'CandidateRHS', ...
            'GRFRecommendedRHS', ...
            'GRFNotRecommendedRHS', ...
            'AMICAOverlapAnnotated', ...
            'AMICAOverlapPercent', ...
            'PreQCAccepted', ...
            'PreQCRejected', ...
            'TimewarpAccepted', ...
            'TimewarpRejected', ...
            'EpochStartSec', ...
            'EpochEndSec', ...
            'WarptoRHSms', ...
            'WarptoLTOms', ...
            'WarptoLHSms', ...
            'WarptoRTOms', ...
            'WarptoNextRHSms', ...
            'Status', ...
            'ProcessingVersion'});
end

function EEGep = epoch_one_recording_local( ...
        EEGsource, sourceIndex, validAnchorIDs, epochLimitsSec)

    EEGwork = EEGsource;

    if ~isfield(EEGwork.event, 'rhs_anchor_id')
        [EEGwork.event.rhs_anchor_id] = deal(NaN);
    else
        for k = 1:numel(EEGwork.event)
            EEGwork.event(k).rhs_anchor_id = NaN;
        end
    end

    types = event_type_strings_local(EEGwork.event);
    sourceIndices = event_numeric_field_local( ...
        EEGwork.event, 'source_recording_index');

    rhsIndices = find(types == "RHS");

    for k = rhsIndices(:)'
        if sourceIndices(k) == sourceIndex
            EEGwork.event(k).rhs_anchor_id = k;
        else
            EEGwork.event(k).type = 'RHS_OTHER_SOURCE';
        end
    end

    EEGwork = eeg_checkset(EEGwork, 'eventconsistency');

    EEGep = pop_epoch( ...
        EEGwork, ...
        {'RHS'}, ...
        epochLimitsSec, ...
        'epochinfo', 'yes');

    allAnchorIDs = anchor_ids_from_epochs_local(EEGep);
    missingAccepted = setdiff(validAnchorIDs(:), allAnchorIDs(:));

    if ~isempty(missingAccepted)
        error([ ...
            'pop_epoch did not return %d pre-QC accepted RHS anchor(s). ' ...
            'First missing anchor ID: %d.'], ...
            numel(missingAccepted), missingAccepted(1));
    end

    keepTrials = find(ismember(allAnchorIDs, validAnchorIDs));

    EEGep = pop_select( ...
        EEGep, ...
        'trial', keepTrials);

    for k = 1:numel(EEGep.event)
        if strcmpi(string(EEGep.event(k).type), "RHS_OTHER_SOURCE")
            EEGep.event(k).type = 'RHS';
        end
    end

    EEGep = eeg_checkset(EEGep, 'eventconsistency');

    finalAnchorIDs = anchor_ids_from_epochs_local(EEGep);

    if numel(finalAnchorIDs) ~= numel(validAnchorIDs) || ...
            ~isequal(sort(finalAnchorIDs(:)), sort(validAnchorIDs(:)))
        error('The trial selection changed the accepted RHS anchor list.');
    end
end

function values = event_numeric_field_local(events, fieldName)

    values = nan(numel(events), 1);

    for k = 1:numel(events)
        values(k) = event_numeric_value_local(events(k), fieldName);
    end
end

function value = event_numeric_value_local(event, fieldName)

    value = NaN;

    if ~isfield(event, fieldName)
        return;
    end

    raw = event.(fieldName);

    if iscell(raw) && isscalar(raw)
        raw = raw{1};
    end

    if isnumeric(raw) && isscalar(raw)
        value = double(raw);
    else
        parsed = str2double(string(raw));
        if isscalar(parsed) && isfinite(parsed)
            value = parsed;
        end
    end
end

function values = event_text_field_local(events, fieldName)

    values = strings(numel(events), 1);

    for k = 1:numel(events)
        values(k) = event_text_value_local(events(k), fieldName);
    end
end

function value = event_text_value_local(event, fieldName)

    value = "";

    if ~isfield(event, fieldName)
        return;
    end

    raw = event.(fieldName);

    if iscell(raw) && isscalar(raw)
        raw = raw{1};
    end

    value = strtrim(string(raw));

    if ismissing(value)
        value = "";
    end
end

function types = event_type_strings_local(events)

    types = strings(numel(events), 1);

    for k = 1:numel(events)
        value = events(k).type;

        if iscell(value) && isscalar(value)
            value = value{1};
        end

        if isnumeric(value)
            if isscalar(value)
                value = string(value);
            else
                value = strjoin(string(value(:)'), '_');
            end
        end

        types(k) = upper(strtrim(string(value)));
    end
end

function specs = load_subject_sources_local(mappingFile)
    sourceMap = readtable(mappingFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = {'BidsSubject', 'BidsSession', 'PreprocessedICASetPath', ...
        'RawSetPath', 'ICAQCStatus', 'AMICAInputSignature'};
    assert(all(ismember(required, sourceMap.Properties.VariableNames)), ...
        'The subject-level table lacks required Step08 source fields.');
    sourceMap = sourceMap(string(sourceMap.ICAQCStatus) == ...
        "passed_ica_quality_basic_checks", :);
    assert(~isempty(sourceMap), 'No source dataset has passed ICA QC.');
    paths = string(sourceMap.PreprocessedICASetPath);
    [~, rows] = unique(paths, 'stable');
    sourceMap = sourceMap(rows, :);
    specs = repmat(struct('subject', "", 'session', "", 'datasetLabel', "", ...
        'sourceSet', "", 'eventSourceSet', "", ...
        'amicaInputSignature', "", 'prefinalSignature', ""), height(sourceMap), 1);
    for k = 1:height(sourceMap)
        subjectNumber = str2double(string(sourceMap.BidsSubject(k)));
        assert(isfinite(subjectNumber) && subjectNumber >= 1 && ...
            subjectNumber == round(subjectNumber), 'Invalid BidsSubject in source table.');
        source = string(sourceMap.PreprocessedICASetPath(k));
        events = string(sourceMap.RawSetPath(k));
        assert(isfile(source) && isfile(events), 'A required continuous source dataset is missing.');
        [~, name] = fileparts(char(source));
        specs(k).subject = "sub-" + compose('%02d', subjectNumber);
        specs(k).session = string(sourceMap.BidsSession(k));
        specs(k).datasetLabel = regexprep(string(name), '_preprocessed_and_ICA$', '', 'ignorecase');
        specs(k).sourceSet = source;
        specs(k).eventSourceSet = events;
        specs(k).amicaInputSignature = string(sourceMap.AMICAInputSignature(k));
        if ismember('AMICAPrefinalSignature', sourceMap.Properties.VariableNames)
            specs(k).prefinalSignature = string(sourceMap.AMICAPrefinalSignature(k));
        end
    end
    assert(numel(unique(string({specs.subject}))) == numel(specs), ...
        'Each subject must have one shared-ICA continuous dataset.');
end

function recommendedCycles = load_recommended_cycles_local(filePath)

    recommendedCycles = readtable( ...
        filePath, ...
        'TextType', 'string', ...
        'VariableNamingRule', 'preserve');

    requiredColumns = { ...
        'Subject', ...
        'XDFPath', ...
        'SegmentIndex', ...
        'RHS1_LSLTime', ...
        'RecommendedForEpoch'};

    missingColumns = setdiff( ...
        requiredColumns, ...
        recommendedCycles.Properties.VariableNames);

    if ~isempty(missingColumns)
        error([ ...
            'Recommended-cycle table is missing column(s): %s\n%s'], ...
            strjoin(missingColumns, ', '), ...
            filePath);
    end

    recommendedMask = logical_column_local( ...
        recommendedCycles.RecommendedForEpoch, ...
        'RecommendedForEpoch');

    recommendedCycles = recommendedCycles(recommendedMask, :);

    if isempty(recommendedCycles)
        error('Recommended-cycle table contains no eligible cycles:\n%s', ...
            filePath);
    end

    recommendedCycles.Subject = string(recommendedCycles.Subject);
    recommendedCycles.XDFPath = string(recommendedCycles.XDFPath);
    recommendedCycles.SegmentIndex = ...
        numeric_vector_local(recommendedCycles.SegmentIndex);
    recommendedCycles.RHS1_LSLTime = ...
        numeric_vector_local(recommendedCycles.RHS1_LSLTime);

    if any(~isfinite(recommendedCycles.SegmentIndex)) || ...
            any(~isfinite(recommendedCycles.RHS1_LSLTime))
        error('Recommended-cycle table contains non-finite identifiers.');
    end

    keys = strings(height(recommendedCycles), 1);
    for rowIndex = 1:height(recommendedCycles)
        keys(rowIndex) = recommended_cycle_key_local( ...
            recommendedCycles.Subject(rowIndex), ...
            recommendedCycles.XDFPath(rowIndex), ...
            recommendedCycles.SegmentIndex(rowIndex), ...
            recommendedCycles.RHS1_LSLTime(rowIndex));
    end

    if numel(unique(keys)) ~= numel(keys)
        error([ ...
            'Recommended-cycle table contains duplicate subject/XDF/' ...
            'segment/RHS identifiers.']);
    end
end

function values = logical_column_local(inputValues, columnName)

    if islogical(inputValues)
        values = inputValues(:);
        return;
    end

    if isnumeric(inputValues)
        if any(~isfinite(inputValues(:))) || ...
                any(~ismember(double(inputValues(:)), [0 1]))
            error('%s must contain only 0/1 values.', columnName);
        end
        values = logical(inputValues(:));
        return;
    end

    textValues = lower(strtrim(string(inputValues(:))));
    values = false(size(textValues));
    trueMask = ismember(textValues, ["true", "1", "yes", "y"]);
    falseMask = ismember(textValues, ["false", "0", "no", "n"]);

    if any(~trueMask & ~falseMask)
        error('%s contains an unrecognized logical value.', columnName);
    end

    values(trueMask) = true;
end

function row = make_manifest_row_local( ...
        subjectOrder, spec, recording, sourceSet, outputSet, ...
        nCandidate, nRecommended, nAMICAOverlap, nPreAccepted, nFinal, ...
        warpto, ...
        epochLimitsSec, status, version)

    SubjectOrder = subjectOrder;
    ConditionOrder = recording.conditionOrder;
    Subject = string(spec.subject);
    DatasetLabel = string(spec.datasetLabel);
    ConditionCode = recording.conditionCode;
    ConditionDisplay = recording.conditionDisplay;
    RunNumber = recording.runNumber;
    SourceRecordingIndex = recording.sourceRecordingIndex;
    SourceRecording = recording.sourceRecording;
    SourceSet = string(sourceSet);
    OutputSet = string(outputSet);
    CandidateRHS = nCandidate;
    GRFRecommendedRHS = nRecommended;
    GRFNotRecommendedRHS = nCandidate - nRecommended;
    AMICAOverlapAnnotated = nAMICAOverlap;
    AMICAOverlapPercent = ...
        100 * nAMICAOverlap / max(nCandidate, 1);
    PreQCAccepted = nPreAccepted;
    PreQCRejected = nCandidate - nPreAccepted;
    TimewarpAccepted = nFinal;
    TimewarpRejected = nPreAccepted - nFinal;
    EpochStartSec = epochLimitsSec(1);
    EpochEndSec = epochLimitsSec(2);

    WarptoRHSms = NaN;
    WarptoLTOms = NaN;
    WarptoLHSms = NaN;
    WarptoRTOms = NaN;
    WarptoNextRHSms = NaN;

    if numel(warpto) == 5
        WarptoRHSms = warpto(1);
        WarptoLTOms = warpto(2);
        WarptoLHSms = warpto(3);
        WarptoRTOms = warpto(4);
        WarptoNextRHSms = warpto(5);
    end

    Status = string(status);
    ProcessingVersion = string(version);

    row = table( ...
        SubjectOrder, ...
        ConditionOrder, ...
        Subject, ...
        DatasetLabel, ...
        ConditionCode, ...
        ConditionDisplay, ...
        RunNumber, ...
        SourceRecordingIndex, ...
        SourceRecording, ...
        SourceSet, ...
        OutputSet, ...
        CandidateRHS, ...
        GRFRecommendedRHS, ...
        GRFNotRecommendedRHS, ...
        AMICAOverlapAnnotated, ...
        AMICAOverlapPercent, ...
        PreQCAccepted, ...
        PreQCRejected, ...
        TimewarpAccepted, ...
        TimewarpRejected, ...
        EpochStartSec, ...
        EpochEndSec, ...
        WarptoRHSms, ...
        WarptoLTOms, ...
        WarptoLHSms, ...
        WarptoRTOms, ...
        WarptoNextRHSms, ...
        Status, ...
        ProcessingVersion);
end

function [matched, rowIndex, cycleKey] = match_recommended_cycle_local( ...
        subject, sourceXDF, segmentIndex, rhsLSLTime, recommendedCycles)

    matched = false;
    rowIndex = NaN;
    cycleKey = recommended_cycle_key_local( ...
        subject, sourceXDF, segmentIndex, rhsLSLTime);

    if strlength(strtrim(string(sourceXDF))) == 0 || ...
            ~isfinite(segmentIndex) || ~isfinite(rhsLSLTime)
        return;
    end

    subjectKey = canonical_subject_key_local(subject);
    xdfName = source_basename_local(sourceXDF);
    lslToleranceSec = 1e-4;

    subjectMatches = false(height(recommendedCycles), 1);
    xdfMatches = false(height(recommendedCycles), 1);

    for candidateIndex = 1:height(recommendedCycles)
        subjectMatches(candidateIndex) = ...
            canonical_subject_key_local( ...
                recommendedCycles.Subject(candidateIndex)) == subjectKey;
        xdfMatches(candidateIndex) = ...
            source_basename_local( ...
                recommendedCycles.XDFPath(candidateIndex)) == xdfName;
    end

    matchingRows = find( ...
        subjectMatches & ...
        xdfMatches & ...
        double(recommendedCycles.SegmentIndex) == segmentIndex & ...
        abs(double(recommendedCycles.RHS1_LSLTime) - rhsLSLTime) ...
            <= lslToleranceSec);

    if numel(matchingRows) > 1
        error([ ...
            'Ambiguous recommended-cycle match for %s, %s, segment %g, ' ...
            'RHS LSL %.12f.'], ...
            char(string(subject)), ...
            char(string(sourceXDF)), ...
            segmentIndex, ...
            rhsLSLTime);
    end

    if numel(matchingRows) == 1
        matched = true;
        rowIndex = matchingRows;
    end
end

function [acceptedEpochs, acceptedLatencies] = ...
        normalized_timewarp_rows_local( ...
        timewarp, nTrials, nExpectedEvents, srate)

    if ~isfield(timewarp, 'epochs') || ...
            ~isfield(timewarp, 'latencies')
        error('make_timewarp did not return epochs and latencies fields.');
    end

    acceptedEpochs = double(timewarp.epochs(:));
    allLatencies = double(timewarp.latencies);

    if isempty(acceptedEpochs)
        acceptedLatencies = zeros(0, nExpectedEvents);
        return;
    end

    if any(~isfinite(acceptedEpochs)) || ...
            any(acceptedEpochs < 1) || ...
            any(acceptedEpochs > nTrials) || ...
            any(mod(acceptedEpochs, 1) ~= 0) || ...
            numel(unique(acceptedEpochs)) ~= numel(acceptedEpochs)
        error('make_timewarp returned invalid epoch indices.');
    end

    if size(allLatencies, 2) ~= nExpectedEvents
        error([ ...
            'Expected %d timewarp event columns, but found %d.'], ...
            nExpectedEvents, size(allLatencies, 2));
    end

    if size(allLatencies, 1) == numel(acceptedEpochs)
        acceptedLatencies = allLatencies;
    elseif size(allLatencies, 1) == nTrials
        acceptedLatencies = allLatencies(acceptedEpochs, :);
    else
        error([ ...
            'Cannot align %d timewarp rows with %d accepted epochs ' ...
            'and %d input trials.'], ...
            size(allLatencies, 1), ...
            numel(acceptedEpochs), ...
            nTrials);
    end

    [acceptedEpochs, order] = sort(acceptedEpochs, 'ascend');
    acceptedLatencies = acceptedLatencies(order, :);

    if any(~isfinite(acceptedLatencies(:)))
        error('The accepted timewarp latency matrix contains NaN or Inf.');
    end

    latencyDifferences = diff(acceptedLatencies, 1, 2);
    if any(latencyDifferences(:) <= 0)
        error('One or more timewarp rows do not follow gait-event order.');
    end

    firstEventToleranceMs = 1000 / srate + 1e-6;
    if any(abs(acceptedLatencies(:, 1)) > firstEventToleranceMs)
        error('The first RHS is not at zero latency in every epoch.');
    end
end

function values = numeric_column_local(values)

    if isnumeric(values) || islogical(values)
        values = double(values(:));
        return;
    end

    if iscell(values)
        out = nan(numel(values), 1);
        for k = 1:numel(values)
            raw = values{k};
            if isempty(raw)
                continue;
            elseif isnumeric(raw) || islogical(raw)
                if isscalar(raw)
                    out(k) = double(raw);
                end
            else
                out(k) = str2double(string(raw));
            end
        end
        values = out;
    else
        values = str2double(string(values(:)));
    end
end

function values = numeric_vector_local(raw)

    if isnumeric(raw)
        values = double(raw(:));
        return;
    end

    if iscell(raw)
        values = nan(numel(raw), 1);
        for k = 1:numel(raw)
            item = raw{k};
            if isnumeric(item) && isscalar(item)
                values(k) = double(item);
            else
                values(k) = str2double(string(item));
            end
        end
        return;
    end

    values = str2double(string(raw(:)));
end

function signature = processing_signature_local(sourceSignature, ...
        eventSourceSignature, recommendedCycleSignature, sourceIndex, epochLimitsSec, ...
        maxSTDAbsolute, maxSTDRelative, amicaBadSamplePolicy, cfg)
    method = struct('source', sourceSignature, ...
        'events', eventSourceSignature, 'recommendedCycles', recommendedCycleSignature, ...
        'sourceIndex', sourceIndex, 'epochLimitsSec', epochLimitsSec, ...
        'maxSTDAbsolute', maxSTDAbsolute, 'maxSTDRelative', maxSTDRelative, ...
        'amicaBadSamplePolicy', amicaBadSamplePolicy, ...
        'eventOrder', {cfg.timewarpEventOrder}, 'baselineLatencyMs', cfg.baselineLatencyMs, ...
        'samplingRateHz', cfg.expectedSamplingRateHz, ...
        'minimumEpochsForTimewarp', cfg.minimumEpochsForTimewarp);
    signature = hipexo.content_signature(method);
end

function key = recommended_cycle_key_local( ...
        subject, sourceXDF, segmentIndex, rhsLSLTime)

    key = canonical_subject_key_local(subject) + "|" + ...
        source_basename_local(sourceXDF) + "|segment=" + ...
        string(segmentIndex) + "|rhs_lsl=" + ...
        string(sprintf('%.12f', rhsLSLTime));
end

function recording = recording_metadata_local( ...
        EEG, sourceIndex, conditionOrder, conditionDisplayOrder)

    types = event_type_strings_local(EEG.event);
    sourceIndices = event_numeric_field_local( ...
        EEG.event, 'source_recording_index');

    startIndex = find( ...
        types == "RECORDING_START" & ...
        sourceIndices == sourceIndex);

    if numel(startIndex) ~= 1
        error([ ...
            'Expected one recording_start event for source index %d, ' ...
            'but found %d.'], ...
            sourceIndex, numel(startIndex));
    end

    conditionRaw = event_text_value_local( ...
        EEG.event(startIndex), ...
        'condition_label');

    conditionCode = hipexo.canonical_condition(conditionRaw);
    conditionPosition = find(conditionOrder == conditionCode, 1);

    if isempty(conditionPosition)
        error('Unrecognized condition label: %s', char(conditionRaw));
    end

    runNumber = event_numeric_value_local( ...
        EEG.event(startIndex), ...
        'run_number');

    if ~isscalar(runNumber) || ~isfinite(runNumber) || ...
            runNumber < 1 || runNumber ~= round(runNumber)
        error(['Invalid run_number %.12g for source index %d. ' ...
            'Run numbers must be positive integers.'], ...
            runNumber, sourceIndex);
    end

    sourceRecording = event_text_value_local( ...
        EEG.event(startIndex), ...
        'source_recording');

    if strlength(sourceRecording) == 0
        sourceRecording = "source-index-" + string(sourceIndex);
    end

    recording = struct();
    recording.sourceRecordingIndex = sourceIndex;
    recording.sourceRecording = sourceRecording;
    recording.conditionCode = conditionCode;
    recording.conditionDisplay = ...
        conditionDisplayOrder(conditionPosition);
    recording.conditionOrder = conditionPosition;
    recording.runNumber = runNumber;
end

function EEG = remove_continuous_qc_masks_local(EEG)

    if ~isfield(EEG, 'etc') || isempty(EEG.etc)
        return;
    end

    continuousOnlyFields = { ...
        'bad_samples', ...
        'bad_samples_percent', ...
        'remove_data_intervals'};

    for k = 1:numel(continuousOnlyFields)
        fieldName = continuousOnlyFields{k};
        if isfield(EEG.etc, fieldName)
            EEG.etc = rmfield(EEG.etc, fieldName);
        end
    end
end

function qc = screen_rhs_cycles_local( ...
        EEG, subject, datasetLabel, recording, epochLimitsSec, ...
        recommendedCycles, amicaBadSamplePolicy)

    expectedSequence = ["RHS", "LTO", "LHS", "RTO", "RHS"];
    gaitTypes = ["RHS", "LTO", "LHS", "RTO"];

    types = event_type_strings_local(EEG.event);
    latencies = event_numeric_field_local(EEG.event, 'latency');
    sourceIndices = event_numeric_field_local( ...
        EEG.event, 'source_recording_index');
    conditionsRaw = event_text_field_local( ...
        EEG.event, 'condition_label');
    conditions = strings(size(conditionsRaw));

    for k = 1:numel(conditionsRaw)
        conditions(k) = hipexo.canonical_condition(conditionsRaw(k));
    end

    runNumbers = event_numeric_field_local(EEG.event, 'run_number');

    requiredEventFields = {'source_xdf', 'segment_index', 'lsl_time'};
    for fieldIndex = 1:numel(requiredEventFields)
        if ~isfield(EEG.event, requiredEventFields{fieldIndex})
            error([ ...
                'Mapped gait events are missing %s. Re-run ' ...
                'Step 03 GRF-to-EEG mapping and Step 03 subject concatenation.'], ...
                requiredEventFields{fieldIndex});
        end
    end

    sourceMask = sourceIndices == recording.sourceRecordingIndex;
    gaitEventIndices = find(sourceMask & ismember(types, gaitTypes));

    [~, order] = sort(latencies(gaitEventIndices), 'ascend');
    gaitEventIndices = gaitEventIndices(order);

    rhsPositions = find(types(gaitEventIndices) == "RHS");
    rhsEventIndices = gaitEventIndices(rhsPositions);
    n = numel(rhsEventIndices);

    Subject = repmat(string(subject), n, 1);
    DatasetLabel = repmat(string(datasetLabel), n, 1);
    ConditionCode = repmat(recording.conditionCode, n, 1);
    ConditionDisplay = repmat(recording.conditionDisplay, n, 1);
    RunNumber = repmat(recording.runNumber, n, 1);
    SourceRecordingIndex = repmat( ...
        recording.sourceRecordingIndex, n, 1);
    SourceRecording = repmat(recording.sourceRecording, n, 1);
    RHSAnchorID = double(rhsEventIndices(:));
    RHSLatencySamples = latencies(rhsEventIndices);
    RHSLSLTime = nan(n, 1);
    GRFSegmentIndex = nan(n, 1);
    SourceXDF = strings(n, 1);
    RecommendedCycleMatched = false(n, 1);
    RecommendedCycleRow = nan(n, 1);
    RecommendedCycleKey = strings(n, 1);
    PreQCStatus = repmat("excluded", n, 1);
    PreQCReason = repmat("not_evaluated", n, 1);
    TimewarpStatus = repmat("not_run_preQC_excluded", n, 1);
    FinalEpochIndex = nan(n, 1);
    HasAMICABadSampleOverlap = false(n, 1);
    AMICABadSampleCount = zeros(n, 1);
    AMICABadSamplePercent = zeros(n, 1);

    badMask = logical(EEG.etc.bad_samples(:));
    boundaryLatencies = latencies(types == "BOUNDARY");

    for c = 1:n
        gaitPosition = rhsPositions(c);
        anchorLatency = RHSLatencySamples(c);
        rhsEvent = EEG.event(rhsEventIndices(c));

        RHSLSLTime(c) = event_numeric_value_local(rhsEvent, 'lsl_time');
        GRFSegmentIndex(c) = ...
            event_numeric_value_local(rhsEvent, 'segment_index');
        SourceXDF(c) = event_text_value_local(rhsEvent, 'source_xdf');

        [RecommendedCycleMatched(c), ...
         RecommendedCycleRow(c), ...
         RecommendedCycleKey(c)] = ...
            match_recommended_cycle_local( ...
                subject, ...
                SourceXDF(c), ...
                GRFSegmentIndex(c), ...
                RHSLSLTime(c), ...
                recommendedCycles);

        if ~RecommendedCycleMatched(c)
            PreQCReason(c) = "not_in_GRF_recommended_cycle_table";
            continue;
        end

        epochStart = floor( ...
            anchorLatency + epochLimitsSec(1) * EEG.srate);
        epochEnd = ceil( ...
            anchorLatency + epochLimitsSec(2) * EEG.srate);

        if epochStart < 1 || epochEnd > EEG.pnts
            PreQCReason(c) = "epoch_outside_continuous_data";
            continue;
        end

        badSampleCount = sum(badMask(epochStart:epochEnd));
        epochSampleCount = epochEnd - epochStart + 1;

        AMICABadSampleCount(c) = badSampleCount;
        AMICABadSamplePercent(c) = ...
            100 * badSampleCount / epochSampleCount;
        HasAMICABadSampleOverlap(c) = badSampleCount > 0;

        if HasAMICABadSampleOverlap(c) && ...
                strcmp(string(amicaBadSamplePolicy), "exclude_any_overlap")
            PreQCReason(c) = "amica_bad_sample_overlap_excluded";
            continue;
        end

        if gaitPosition + 4 > numel(gaitEventIndices)
            PreQCReason(c) = "no_complete_next_gait_cycle";
            continue;
        end

        cycleIndices = gaitEventIndices(gaitPosition:gaitPosition + 4);
        sequence = types(cycleIndices);

        if ~isequal(sequence(:)', expectedSequence)
            PreQCReason(c) = ...
                "wrong_gait_sequence_" + strjoin(sequence, "-");
            continue;
        end

        cycleConditions = conditions(cycleIndices);
        cycleRuns = runNumbers(cycleIndices);
        cycleSources = sourceIndices(cycleIndices);

        if any(cycleConditions ~= recording.conditionCode) || ...
                any(cycleRuns ~= recording.runNumber) || ...
                any(cycleSources ~= recording.sourceRecordingIndex)
            PreQCReason(c) = "cycle_provenance_mismatch";
            continue;
        end

        nextRHSLatency = latencies(cycleIndices(end));
        if nextRHSLatency > epochEnd
            PreQCReason(c) = "next_RHS_outside_epoch_window";
            continue;
        end

        if any( ...
                boundaryLatencies >= epochStart & ...
                boundaryLatencies <= epochEnd)
            PreQCReason(c) = "boundary_inside_epoch_window";
            continue;
        end

        PreQCStatus(c) = "included";
        if HasAMICABadSampleOverlap(c)
            PreQCReason(c) = "passed_AMICA_overlap_annotated";
        else
            PreQCReason(c) = "passed_no_AMICA_overlap";
        end
        TimewarpStatus(c) = "pending_make_timewarp";
    end

    qc = table( ...
        Subject, ...
        DatasetLabel, ...
        ConditionCode, ...
        ConditionDisplay, ...
        RunNumber, ...
        SourceRecordingIndex, ...
        SourceRecording, ...
        RHSAnchorID, ...
        RHSLatencySamples, ...
        RHSLSLTime, ...
        GRFSegmentIndex, ...
        SourceXDF, ...
        RecommendedCycleMatched, ...
        RecommendedCycleRow, ...
        RecommendedCycleKey, ...
        PreQCStatus, ...
        PreQCReason, ...
        TimewarpStatus, ...
        FinalEpochIndex, ...
        HasAMICABadSampleOverlap, ...
        AMICABadSampleCount, ...
        AMICABadSamplePercent);
end

function name = source_basename_local(filePath)
    [~, stem, extension] = fileparts(char(strtrim(string(filePath))));
    name = lower(string([stem extension]));
end

function EEG = synchronize_current_raw_events_local(EEG, rawSetPath)

    rawSetPath = string(rawSetPath);

    [rawFolder, rawName, rawExt] = fileparts(char(rawSetPath));

    rawEEG = pop_loadset( ...
        'filename', [rawName rawExt], ...
        'filepath', rawFolder, ...
        'loadmode', 'info');

    if double(rawEEG.trials) ~= 1 || double(EEG.trials) ~= 1
        error('Event synchronization requires continuous datasets.');
    end

    if double(rawEEG.pnts) ~= double(EEG.pnts)
        error([ ...
            'Raw combined and ICA datasets have different sample counts ' ...
            '(%d versus %d).'], ...
            double(rawEEG.pnts), double(EEG.pnts));
    end

    if abs(double(rawEEG.srate) - double(EEG.srate)) > 1e-9
        error('Raw combined and ICA datasets have different sampling rates.');
    end

    verify_structural_event_layout_local(EEG, rawEEG);
    verify_source_manifest_layout_local(EEG, rawEEG);

    if isempty(rawEEG.event)
        error('The current raw combined dataset contains no events.');
    end

    EEG.event = rawEEG.event;

    if isfield(rawEEG, 'urevent')
        EEG.urevent = rawEEG.urevent;
    else
        EEG.urevent = [];
    end

    if isfield(rawEEG, 'eventdescription')
        EEG.eventdescription = rawEEG.eventdescription;
    end

    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc)
        EEG.etc = struct();
    end

    if isfield(rawEEG, 'etc') && isstruct(rawEEG.etc)
        rawEtcFields = fieldnames(rawEEG.etc);
        copyMask = startsWith(rawEtcFields, 'subject_merge_') | ...
            strcmp(rawEtcFields, 'subject_level_concatenation');
        fieldsToCopy = rawEtcFields(copyMask);

        for k = 1:numel(fieldsToCopy)
            fieldName = fieldsToCopy{k};
            EEG.etc.(fieldName) = rawEEG.etc.(fieldName);
        end
    end

    EEG = eeg_checkset(EEG, 'eventconsistency');
end

function info = validate_source_dataset_local( ...
        EEG, expectedSubject, expectedSamplingRateHz, ...
        expectedAMICAInputSignature, expectedPrefinalSignature)

    if EEG.trials ~= 1 || abs(double(EEG.xmin)) > 1e-12
        error('The input must be a continuous dataset, not epoched data.');
    end

    if abs(double(EEG.srate) - double(expectedSamplingRateHz)) > 1e-9
        error('Expected %.12g Hz data, but found %.12g Hz.', ...
            expectedSamplingRateHz, EEG.srate);
    end

    if ~strcmpi(string(EEG.subject), string(expectedSubject))
        error('Unexpected EEG.subject: %s', char(string(EEG.subject)));
    end

    if isempty(EEG.icaweights) || isempty(EEG.icasphere)
        error('The source dataset does not contain an ICA decomposition.');
    end

    nICs = size(EEG.icaweights, 1);

    if ~isfield(EEG, 'dipfit') || ...
            ~isfield(EEG.dipfit, 'model') || ...
            numel(EEG.dipfit.model) < nICs
        error('The source dataset has incomplete DIPFIT models.');
    end

    if ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'amica_input_signature') || ...
            strlength(string(EEG.etc.amica_input_signature)) == 0
        error('EEG.etc.amica_input_signature is missing.');
    end

    prefinalMatches = strlength(expectedPrefinalSignature) > 0 && ...
        isfield(EEG.etc, 'amica_stage_signatures') && ...
        string(EEG.etc.amica_stage_signatures.prefinal) == expectedPrefinalSignature;
    if ~prefinalMatches && string(EEG.etc.amica_input_signature) ~= ...
            string(expectedAMICAInputSignature)
        error([ ...
            'The AMICA input signature stored in the dataset does not ' ...
            'match the current subject-level processing table.']);
    end

    if ~isfield(EEG.etc, 'bad_samples')
        error([ ...
            'EEG.etc.bad_samples is missing. This script will not ' ...
            'silently accept epochs without the AMICA bad-sample mask.']);
    end

    badMask = logical(EEG.etc.bad_samples(:));

    if numel(badMask) ~= EEG.pnts
        error([ ...
            'EEG.etc.bad_samples has %d entries, but EEG.pnts is %d.'], ...
            numel(badMask), EEG.pnts);
    end

    requiredFields = { ...
        'type', ...
        'latency', ...
        'condition_label', ...
        'run_number', ...
        'source_recording_index'};

    for k = 1:numel(requiredFields)
        if ~isfield(EEG.event, requiredFields{k})
            error('EEG.event.%s is missing.', requiredFields{k});
        end
    end

    types = event_type_strings_local(EEG.event);

    requiredTypes = [ ...
        "RECORDING_START", ...
        "RHS", ...
        "LTO", ...
        "LHS", ...
        "RTO"];

    if ~all(ismember(requiredTypes, types))
        error('The source dataset is missing required gait event types.');
    end

    info = struct();
    info.nICs = nICs;
    info.badSampleCount = sum(badMask);
    info.badSamplePercent = 100 * mean(badMask);
end

function EEG = preserve_source_ica_local(EEG, sourceEEG, expectedIdentity)

    if double(EEG.nbchan) ~= double(sourceEEG.nbchan)
        error('Channel count changed during RHS epoching.');
    end

    outputLabels = string({EEG.chanlocs.labels});
    sourceLabels = string({sourceEEG.chanlocs.labels});
    if ~isequal(outputLabels, sourceLabels)
        error('Channel order changed during RHS epoching.');
    end

    EEG.icaweights = sourceEEG.icaweights;
    EEG.icasphere = sourceEEG.icasphere;
    EEG.icawinv = sourceEEG.icawinv;

    EEG.icachansind = sourceEEG.icachansind;
    EEG.dipfit = sourceEEG.dipfit;

    % Continuous ICA activations do not match the epoched data dimensions.
    % Let EEGLAB recompute them from the preserved decomposition if needed.
    EEG.icaact = [];
    EEG = eeg_checkset(EEG);

    if hipexo.ica_identity_signature(EEG) ~= expectedIdentity
        error('Could not preserve the source ICA during RHS epoching.');
    end
end

function verify_source_manifest_layout_local(sourceEEG, rawEEG)

    hasSourceManifest = isfield(sourceEEG, 'etc') && ...
        isfield(sourceEEG.etc, 'subject_merge_source_manifest') && ...
        istable(sourceEEG.etc.subject_merge_source_manifest);

    hasRawManifest = isfield(rawEEG, 'etc') && ...
        isfield(rawEEG.etc, 'subject_merge_source_manifest') && ...
        istable(rawEEG.etc.subject_merge_source_manifest);

    if ~(hasSourceManifest && hasRawManifest)
        error([ ...
            'Both datasets must contain subject_merge_source_manifest ' ...
            'before event synchronization.']);
    end

    sourceManifest = sourceEEG.etc.subject_merge_source_manifest;
    rawManifest = rawEEG.etc.subject_merge_source_manifest;

    if height(sourceManifest) ~= height(rawManifest)
        error('Source-recording manifest row counts differ.');
    end

    requiredFields = { ...
        'SourceIndex', ...
        'XDFPath', ...
        'ConditionLabel', ...
        'RunNumber', ...
        'StartSampleInMergedEEG', ...
        'EndSampleInMergedEEG', ...
        'SampleCount'};

    if ~all(ismember(requiredFields, ...
            sourceManifest.Properties.VariableNames)) || ...
            ~all(ismember(requiredFields, ...
            rawManifest.Properties.VariableNames))
        error('A required source-manifest layout field is missing.');
    end

    stringFields = {'XDFPath', 'ConditionLabel'};
    numericFields = setdiff(requiredFields, stringFields, 'stable');

    for k = 1:numel(stringFields)
        fieldName = stringFields{k};

        if any(~strcmpi( ...
                strtrim(string(sourceManifest.(fieldName))), ...
                strtrim(string(rawManifest.(fieldName)))))
            error('Source-manifest field %s differs.', fieldName);
        end
    end

    for k = 1:numel(numericFields)
        fieldName = numericFields{k};

        sourceValues = ...
            numeric_column_local(sourceManifest.(fieldName));

        rawValues = ...
            numeric_column_local(rawManifest.(fieldName));

        if numel(sourceValues) ~= numel(rawValues) || ...
                any(~isfinite(sourceValues)) || ...
                any(~isfinite(rawValues)) || ...
                any(abs(sourceValues - rawValues) > 1e-6)
            error('Source-manifest field %s differs.', fieldName);
        end
    end
end

function verify_structural_event_layout_local(sourceEEG, rawEEG)

    sourceTypes = ...
        upper(strtrim(event_type_strings_local(sourceEEG.event)));

    rawTypes = ...
        upper(strtrim(event_type_strings_local(rawEEG.event)));

    structuralTypes = ["BOUNDARY", "RECORDING_START"];

    for k = 1:numel(structuralTypes)
        eventType = structuralTypes(k);

        sourceLatencies = event_numeric_field_local( ...
            sourceEEG.event(sourceTypes == eventType), ...
            'latency');

        rawLatencies = event_numeric_field_local( ...
            rawEEG.event(rawTypes == eventType), ...
            'latency');

        if numel(sourceLatencies) ~= numel(rawLatencies) || ...
                any(abs(sourceLatencies - rawLatencies) > 1e-6)
            error([ ...
                'Structural %s markers differ between the ICA and ' ...
                'current raw combined datasets.'], ...
                eventType);
        end
    end
end

function signature = amica_source_signature_local(EEG)
    signature = "";
    if isfield(EEG, 'etc') && isstruct(EEG.etc)
        if isfield(EEG.etc, 'amica_stage_signatures') && ...
                isstruct(EEG.etc.amica_stage_signatures) && ...
                isfield(EEG.etc.amica_stage_signatures, 'prefinal')
            signature = string(EEG.etc.amica_stage_signatures.prefinal);
        end
        if strlength(signature) == 0 && ...
                isfield(EEG.etc, 'amica_input_signature')
            signature = string(EEG.etc.amica_input_signature);
        end
    end
    if strlength(signature) == 0
        error('AMICA source signature is missing.');
    end
end

function assert_reusable_output_local( ...
        EEGout, EEGsource, sourceICAIdentity, recording, validAnchorIDs, ...
        recommendedCycleSignature, epochLimitsSec, timewarpEventOrder, ...
        baselineLatencyMs, maxSTDAbsolute, maxSTDRelative, amicaBadSamplePolicy)

    if hipexo.ica_identity_signature(EEGout) ~= sourceICAIdentity
        error('ICA identity changed.');
    end

    if amica_source_signature_local(EEGout) ~= ...
            amica_source_signature_local(EEGsource)
        error('Upstream AMICA source changed.');
    end

    if ~isfield(EEGout, 'etc') || ~isfield(EEGout.etc, 'rhs_epoching')
        error('RHS epoching metadata is missing.');
    end
    info = EEGout.etc.rhs_epoching;

    required = {'source_recording_index','condition_code','run_number', ...
        'epoch_limits_sec','timewarp_event_order','baseline_latency_ms', ...
        'max_std_absolute','max_std_relative','amica_bad_sample_policy', ...
        'recommended_cycle_table_signature','pre_timewarp_rhs_anchor_ids', ...
        'accepted_rhs_anchor_ids'};
    if ~all(isfield(info, required))
        error('Required reuse metadata is missing.');
    end

    same = double(info.source_recording_index) == recording.sourceRecordingIndex && ...
        string(info.condition_code) == recording.conditionCode && ...
        double(info.run_number) == recording.runNumber && ...
        isequal(double(info.epoch_limits_sec(:))', double(epochLimitsSec(:))') && ...
        isequal(string(info.timewarp_event_order(:))', string(timewarpEventOrder(:))') && ...
        isequal(double(info.baseline_latency_ms), double(baselineLatencyMs)) && ...
        isequal(double(info.max_std_absolute), double(maxSTDAbsolute)) && ...
        isequal(double(info.max_std_relative), double(maxSTDRelative)) && ...
        string(info.amica_bad_sample_policy) == string(amicaBadSamplePolicy) && ...
        string(info.recommended_cycle_table_signature) == string(recommendedCycleSignature) && ...
        isequal(sort(double(info.pre_timewarp_rhs_anchor_ids(:))), ...
                sort(double(validAnchorIDs(:))));
    if ~same
        error('Inputs or Step10 settings changed.');
    end

    acceptedIDs = double(info.accepted_rhs_anchor_ids(:));
    currentLatencies = current_gait_latencies_local( ...
        EEGsource, recording.sourceRecordingIndex, acceptedIDs);
    savedLatencies = double(EEGout.timewarp.latencies);
    tolMs = 1000 / double(EEGsource.srate) + 1e-6;
    if ~isequal(size(currentLatencies), size(savedLatencies)) || ...
            any(abs(currentLatencies(:) - savedLatencies(:)) > tolMs)
        error('Current gait-event latencies changed.');
    end
end

function latencyMs = current_gait_latencies_local(EEG, sourceIndex, anchorIDs)
    types = event_type_strings_local(EEG.event);
    latencies = event_numeric_field_local(EEG.event, 'latency');
    sourceIndices = event_numeric_field_local(EEG.event, 'source_recording_index');
    gaitTypes = ["RHS", "LTO", "LHS", "RTO"];
    gaitEventIndices = find(sourceIndices == sourceIndex & ismember(types, gaitTypes));
    [~, order] = sort(latencies(gaitEventIndices), 'ascend');
    gaitEventIndices = gaitEventIndices(order);

    latencyMs = nan(numel(anchorIDs), 5);
    expected = ["RHS", "LTO", "LHS", "RTO", "RHS"];
    for k = 1:numel(anchorIDs)
        pos = find(gaitEventIndices == anchorIDs(k), 1);
        if isempty(pos) || pos + 4 > numel(gaitEventIndices)
            error('Saved RHS anchor is not present in current gait events.');
        end
        idx = gaitEventIndices(pos:pos+4);
        if ~isequal(types(idx(:))', expected)
            error('Current gait-event sequence changed.');
        end
        latencyMs(k,:) = ...
            (latencies(idx) - latencies(idx(1)))' * 1000 / double(EEG.srate);
    end
end

function write_current_tables_local( ...
        manifest, epochQC, manifestFile, qcFile)

    if ~isempty(manifest)
        manifest = sortrows( ...
            manifest, ...
            {'SubjectOrder', 'ConditionOrder', 'RunNumber'});

        writetable(manifest, manifestFile);
    end

    if ~isempty(epochQC)
        epochQC = sortrows( ...
            epochQC, ...
            { ...
                'Subject', ...
                'SourceRecordingIndex', ...
                'RHSLatencySamples'});

        writetable(epochQC, qcFile);
    end
end

function restoreRMS = suspend_ica_rms_local()
% Keep the reviewed ICA weights unchanged during load/check/save operations.
% EEGLAB eeg_checkset scales weights when option_scaleicarms is enabled.
    eeglab_options;
    previousScale = option_scaleicarms;
    restoreRMS = [];
    if previousScale ~= 0
        restoreRMS = onCleanup(@() pop_editoptions( ...
            'option_scaleicarms', previousScale));
        pop_editoptions('option_scaleicarms', 0);
        eeglab_options;
        assert(option_scaleicarms == 0, ...
            'Could not disable automatic ICA RMS scaling. No epochs were rebuilt.');
    end
end
