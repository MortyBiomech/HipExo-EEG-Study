% GOAL
%   Perform the complete structural and consistency QC for one set of
%   AMICA, DIPFIT, ICLabel, preprocessed-ICA, and cleaned-ICA outputs.
%
% METHOD
%   Preserve the current working Step 08 QC logic exactly while moving the
%   single-dataset check out of the orchestration script.

function [status, notes, metrics] = check_ica_output_quality(cleanedSetPath, preprocessedICASetPath, amicaSetPath, dipfittedSetPath, expectedChannels, expectedSrate, rankSampleLimit, rvThreshold15, rvThreshold20, maxAMICABadSamplesPercent, expectedAMICAInputSignature)

    metrics = empty_ica_metrics();
    warnings = strings(0, 1);
    failures = strings(0, 1);

    metrics.hasCleanedICASet = exist(cleanedSetPath, 'file') == 2;
    metrics.hasPreprocessedICASet = exist(preprocessedICASetPath, 'file') == 2;
    metrics.hasAMICASet = exist(amicaSetPath, 'file') == 2;
    metrics.hasDipfittedSet = exist(dipfittedSetPath, 'file') == 2;

    if ~metrics.hasCleanedICASet
        status = "failed_cleaned_ica_set_missing";
        notes = "CleanedICASetPath does not exist.";
        return;
    end

    if ~metrics.hasPreprocessedICASet
        failures(end+1, 1) = "preprocessed_and_ICA_set_missing";
    end

    if ~metrics.hasAMICASet
        failures(end+1, 1) = "AMICA_set_missing";
    end

    if ~metrics.hasDipfittedSet
        failures(end+1, 1) = "dipfitted_set_missing";
    end

    %% --------------------------------------------------------------------
    %  Load cleaned_with_ICA.set for final cleaned EEG data checks
    %  --------------------------------------------------------------------

    try
        EEG_cleaned = load_set_local(cleanedSetPath);
    catch ME
        status = "failed_load_cleaned_ica_set";
        notes = "Could not load cleaned ICA set: " + string(ME.message);
        return;
    end

    metrics.channels = safe_get_numeric_field(EEG_cleaned, 'nbchan');
    metrics.srate = safe_get_numeric_field(EEG_cleaned, 'srate');
    metrics.samples = safe_get_numeric_field(EEG_cleaned, 'pnts');

    if ~isnan(metrics.srate) && metrics.srate > 0 && ~isnan(metrics.samples) && metrics.samples > 1
        metrics.durationSec = (metrics.samples - 1) / metrics.srate;
    end

    if metrics.channels ~= expectedChannels
        failures(end+1, 1) = "unexpected_cleaned_channel_count";
    end

    if isnan(metrics.srate) || abs(metrics.srate - expectedSrate) > 1e-6
        failures(end+1, 1) = "unexpected_cleaned_sampling_rate";
    end

    if isempty(EEG_cleaned.data)
        failures(end+1, 1) = "empty_cleaned_EEG_data";
    else
        finiteOK = check_data_finite_sampled(EEG_cleaned.data);
        if ~finiteOK
            failures(end+1, 1) = "NaN_or_Inf_in_cleaned_EEG_data";
        end
    end

    cleanedLabels = get_channel_labels(EEG_cleaned);
    if numel(cleanedLabels) ~= numel(unique(cleanedLabels))
        warnings(end+1, 1) = "duplicate_channel_labels_in_cleaned_set";
    end

    %% --------------------------------------------------------------------
    %  Load preprocessed_and_ICA.set for ICA / ICLabel / DIPFIT checks
    %  --------------------------------------------------------------------

    if metrics.hasPreprocessedICASet

        try
            EEG_ica = load_set_local(preprocessedICASetPath);
        catch ME
            failures(end+1, 1) = "failed_load_preprocessed_and_ICA_set";
            warnings(end+1, 1) = "preprocessed_and_ICA_load_error: " + string(ME.message);
            EEG_ica = [];
        end

    else

        EEG_ica = [];

    end

    if ~isempty(EEG_ica)

        icaChannels = safe_get_numeric_field(EEG_ica, 'nbchan');
        icaSrate = safe_get_numeric_field(EEG_ica, 'srate');
        icaSamples = safe_get_numeric_field(EEG_ica, 'pnts');

        if isempty(EEG_ica.data) || ~check_data_finite_sampled(EEG_ica.data)
            failures(end+1, 1) = "NaN_Inf_or_empty_data_in_preprocessed_and_ICA";
        end

        if icaChannels == metrics.channels && ...
                abs(icaSrate - metrics.srate) <= 1e-6 && ...
                icaSamples == metrics.samples
            metrics.preprocessedCleanedCompatible = true;
        else
            metrics.preprocessedCleanedCompatible = false;
            warnings(end+1, 1) = "preprocessed_and_ICA_not_fully_compatible_with_cleaned_set";
        end

        icaLabels = get_channel_labels(EEG_ica);
        if numel(icaLabels) ~= numel(unique(icaLabels))
            warnings(end+1, 1) = "duplicate_channel_labels_in_preprocessed_and_ICA_set";
        end

        metrics.hasICAWeights = isfield(EEG_ica, 'icaweights') && ~isempty(EEG_ica.icaweights) && ...
            isfield(EEG_ica, 'icasphere') && ~isempty(EEG_ica.icasphere);

        if metrics.hasICAWeights
            metrics.nICs = size(EEG_ica.icaweights, 1);
            metrics.rankEstimate = estimate_data_rank_sampled(EEG_ica.data, rankSampleLimit);

            hasSphere = isfield(EEG_ica, 'icasphere') && ~isempty(EEG_ica.icasphere);
            hasWinv = isfield(EEG_ica, 'icawinv') && ~isempty(EEG_ica.icawinv);
            hasChanInd = isfield(EEG_ica, 'icachansind') && ~isempty(EEG_ica.icachansind);

            if hasSphere && hasWinv && hasChanInd
                metrics.icaMatrixDimOK = ...
                    size(EEG_ica.icaweights, 2) == size(EEG_ica.icasphere, 1) && ...
                    size(EEG_ica.icasphere, 2) == numel(EEG_ica.icachansind) && ...
                    size(EEG_ica.icawinv, 1) == numel(EEG_ica.icachansind) && ...
                    size(EEG_ica.icawinv, 2) == metrics.nICs && ...
                    all(EEG_ica.icachansind >= 1) && ...
                    all(EEG_ica.icachansind <= EEG_ica.nbchan);
            end

            metrics.icaValuesFinite = all(isfinite(double(EEG_ica.icaweights(:)))) && ...
                hasSphere && all(isfinite(double(EEG_ica.icasphere(:)))) && ...
                hasWinv && all(isfinite(double(EEG_ica.icawinv(:))));

            if ~metrics.icaMatrixDimOK
                failures(end+1, 1) = "ICA_matrix_dimensions_are_inconsistent";
            end
            if ~metrics.icaValuesFinite
                failures(end+1, 1) = "ICA_matrices_contain_NaN_or_Inf";
            end
        else
            failures(end+1, 1) = "missing_ICA_weights_or_sphere_in_preprocessed_and_ICA";
        end

        if isfield(EEG_ica, 'etc') && isfield(EEG_ica.etc, 'spatial_filter') && ...
                isfield(EEG_ica.etc.spatial_filter, 'algorithm') && ...
                strcmpi(string(EEG_ica.etc.spatial_filter.algorithm), "AMICA")
            metrics.hasAMICAMetadata = true;
        else
            failures(end+1, 1) = "missing_AMICA_algorithm_metadata";
        end

        if strlength(strtrim(string(expectedAMICAInputSignature))) > 0 && ...
                isfield(EEG_ica, 'etc') && ...
                isfield(EEG_ica.etc, 'amica_input_signature') && ...
                string(EEG_ica.etc.amica_input_signature) == ...
                string(expectedAMICAInputSignature)
            metrics.amicaInputSignatureOK = true;
        else
            failures(end+1, 1) = "AMICA_input_signature_mismatch";
        end

        if isfield(EEG_ica, 'etc') && isfield(EEG_ica.etc, 'bad_samples')
            rawMask = EEG_ica.etc.bad_samples(:);
            maskIsNumericOrLogical = isnumeric(rawMask) || islogical(rawMask);

            if maskIsNumericOrLogical
                numericMask = double(rawMask);
                maskIsBinaryFinite = all(isfinite(numericMask)) && ...
                    all(ismember(numericMask, [0 1]));
            else
                maskIsBinaryFinite = false;
                numericMask = [];
            end

            metrics.hasBadSampleMask = ...
                maskIsBinaryFinite && numel(numericMask) == EEG_ica.pnts;

            if ~maskIsBinaryFinite
                failures(end+1, 1) = ...
                    "AMICA_bad_sample_mask_not_binary_finite";
            elseif ~metrics.hasBadSampleMask
                failures(end+1, 1) = "AMICA_bad_sample_mask_length_mismatch";
            else
                mask = logical(numericMask);
                metrics.badSamples = sum(mask);
                metrics.badSamplesPercent = 100 * mean(mask);

                if metrics.badSamplesPercent > maxAMICABadSamplesPercent
                    warnings(end+1, 1) = ...
                        "AMICA_bad_sample_percentage_exceeds_review_threshold";
                end
            end
        else
            warnings(end+1, 1) = "AMICA_bad_sample_mask_missing";
        end

        [hasICLabel, icLabelMetrics, icLabelDimOK] = extract_iclabel_metrics(EEG_ica, metrics.nICs);
        metrics.hasICLabel = hasICLabel;
        metrics.icLabelDimOK = icLabelDimOK;

        if hasICLabel
            metrics.brainICs = icLabelMetrics.brainICs;
            metrics.brainICsP050 = icLabelMetrics.brainICsP050;
            metrics.brainICsP075 = icLabelMetrics.brainICsP075;
            metrics.eyeICs = icLabelMetrics.eyeICs;
            metrics.muscleICs = icLabelMetrics.muscleICs;
            metrics.heartICs = icLabelMetrics.heartICs;
            metrics.lineNoiseICs = icLabelMetrics.lineNoiseICs;
            metrics.channelNoiseICs = icLabelMetrics.channelNoiseICs;
            metrics.otherICs = icLabelMetrics.otherICs;

            if ~icLabelDimOK
                failures(end+1, 1) = "ICLabel_dimension_does_not_match_IC_count";
            end
        else
            failures(end+1, 1) = "missing_ICLabel_classification_in_preprocessed_and_ICA";
        end

        [hasDIPFIT, dipfitMetrics, dipfitDimOK] = extract_dipfit_metrics(EEG_ica, metrics.nICs, rvThreshold15, rvThreshold20);
        metrics.hasDIPFIT = hasDIPFIT;
        metrics.dipfitDimOK = dipfitDimOK;

        if hasDIPFIT
            metrics.dipfitRVMedian = dipfitMetrics.rvMedian;
            metrics.dipfitRVBelow15 = dipfitMetrics.rvBelow15;
            metrics.dipfitRVBelow20 = dipfitMetrics.rvBelow20;

            if ~dipfitDimOK
                failures(end+1, 1) = "DIPFIT_model_count_does_not_match_IC_count";
            end
        else
            failures(end+1, 1) = "missing_DIPFIT_model_or_RV_in_preprocessed_and_ICA";
        end

    end


    %% --------------------------------------------------------------------
    %  Verify AMICA.set and dipfitted.set use the same spatial filter
    %  --------------------------------------------------------------------

    if ~isempty(EEG_ica) && metrics.hasAMICASet
        try
            EEG_amica = load_set_local(amicaSetPath);
            metrics.amicaPreprocessedEquivalent = spatial_filters_equivalent(EEG_amica, EEG_ica);
            if ~metrics.amicaPreprocessedEquivalent
                failures(end+1, 1) = "AMICA_and_preprocessed_ICA_spatial_filters_do_not_match";
            end
        catch ME
            failures(end+1, 1) = "failed_load_or_compare_AMICA_set";
            warnings(end+1, 1) = "AMICA_compare_error: " + string(ME.message);
        end
    end

    %% --------------------------------------------------------------------
    %  Check dipfitted.set contains DIPFIT as expected
    %  --------------------------------------------------------------------

    if metrics.hasDipfittedSet

        try
            EEG_dipfitted = load_set_local(dipfittedSetPath);
            [dipfittedHasDIPFIT, ~, dipfittedDimOK] = extract_dipfit_metrics(EEG_dipfitted, metrics.nICs, rvThreshold15, rvThreshold20);
            metrics.dipfittedHasDIPFIT = dipfittedHasDIPFIT;
            if ~isempty(EEG_ica)
                metrics.dipfittedPreprocessedEquivalent = ...
                    spatial_filters_equivalent(EEG_dipfitted, EEG_ica);
                if ~metrics.dipfittedPreprocessedEquivalent
                    failures(end+1, 1) = "dipfitted_and_preprocessed_ICA_spatial_filters_do_not_match";
                end
            end

            if ~dipfittedHasDIPFIT
                failures(end+1, 1) = "dipfitted_set_has_no_DIPFIT_RV_values";
            elseif ~dipfittedDimOK && ~isnan(metrics.nICs)
                failures(end+1, 1) = "dipfitted_set_DIPFIT_count_does_not_match_IC_count";
            end
        catch ME
            failures(end+1, 1) = "failed_load_dipfitted_set";
            warnings(end+1, 1) = "dipfitted_set_load_error: " + string(ME.message);
        end

    end

    %% --------------------------------------------------------------------
    %  Rank sanity check
    %  --------------------------------------------------------------------

    if metrics.hasICAWeights && ~isnan(metrics.nICs) && ~isnan(metrics.rankEstimate)
        if metrics.nICs > metrics.rankEstimate + 2
            warnings(end+1, 1) = "IC_count_larger_than_estimated_cleaned_data_rank";
        end
    end

    %% --------------------------------------------------------------------
    %  Final status
    %  --------------------------------------------------------------------

    if isempty(failures) && isempty(warnings)
        status = "passed_ica_quality_basic_checks";
        notes = "All basic ICA output checks passed. Still visually inspect IC maps/classes before final analysis.";
    elseif isempty(failures)
        status = "warning_ica_quality_needs_review";
        notes = "Warnings: " + join(warnings, "; ");
    else
        status = "failed_ica_quality_basic_checks";
        if isempty(warnings)
            notes = "Failures: " + join(failures, "; ");
        else
            notes = "Failures: " + join(failures, "; ") + "; Warnings: " + join(warnings, "; ");
        end
    end

end

function metrics = empty_ica_metrics()

    metrics = struct();
    metrics.channels = NaN;
    metrics.srate = NaN;
    metrics.samples = NaN;
    metrics.durationSec = NaN;
    metrics.rankEstimate = NaN;
    metrics.nICs = NaN;

    metrics.hasAMICASet = false;
    metrics.hasDipfittedSet = false;
    metrics.hasPreprocessedICASet = false;
    metrics.hasCleanedICASet = false;

    metrics.hasICAWeights = false;
    metrics.hasICLabel = false;
    metrics.hasDIPFIT = false;
    metrics.icLabelDimOK = false;
    metrics.dipfitDimOK = false;
    metrics.dipfittedHasDIPFIT = false;
    metrics.preprocessedCleanedCompatible = false;
    metrics.icaMatrixDimOK = false;
    metrics.icaValuesFinite = false;
    metrics.amicaPreprocessedEquivalent = false;
    metrics.dipfittedPreprocessedEquivalent = false;
    metrics.hasAMICAMetadata = false;
    metrics.amicaInputSignatureOK = false;
    metrics.hasBadSampleMask = false;
    metrics.badSamples = NaN;
    metrics.badSamplesPercent = NaN;

    metrics.brainICs = NaN;
    metrics.brainICsP050 = NaN;
    metrics.brainICsP075 = NaN;
    metrics.eyeICs = NaN;
    metrics.muscleICs = NaN;
    metrics.heartICs = NaN;
    metrics.lineNoiseICs = NaN;
    metrics.channelNoiseICs = NaN;
    metrics.otherICs = NaN;

    metrics.dipfitRVMedian = NaN;
    metrics.dipfitRVBelow15 = NaN;
    metrics.dipfitRVBelow20 = NaN;

end

function EEG = load_set_local(setPath)

    [folderPath, fileNameNoExt, fileExt] = fileparts(setPath);
    EEG = pop_loadset('filename', [fileNameNoExt fileExt], 'filepath', folderPath);
    EEG = eeg_checkset(EEG);

end

function value = safe_get_numeric_field(S, fieldName)

    value = NaN;

    if isfield(S, fieldName)
        rawValue = S.(fieldName);
        if isnumeric(rawValue) && ~isempty(rawValue)
            value = double(rawValue(1));
        end
    end

end

function labels = get_channel_labels(EEG)

    labels = strings(0, 1);

    if ~isfield(EEG, 'chanlocs') || isempty(EEG.chanlocs)
        return;
    end

    labels = strings(numel(EEG.chanlocs), 1);

    for k = 1:numel(EEG.chanlocs)
        if isfield(EEG.chanlocs(k), 'labels')
            labels(k) = string(EEG.chanlocs(k).labels);
        else
            labels(k) = "";
        end
    end

end

function finiteOK = check_data_finite_sampled(data)

    finiteOK = ~isempty(data);
    if ~finiteOK
        return;
    end

    try
        blockSize = 100000;
        for firstSample = 1:blockSize:size(data, 2)
            lastSample = min(size(data, 2), firstSample + blockSize - 1);
            block = double(data(:, firstSample:lastSample));
            if any(~isfinite(block(:)))
                finiteOK = false;
                return;
            end
        end
    catch
        finiteOK = false;
    end

end

function rankEstimate = estimate_data_rank_sampled(data, rankSampleLimit)

    rankEstimate = NaN;

    try
        nSamples = size(data, 2);

        if nSamples > rankSampleLimit
            idx = round(linspace(1, nSamples, rankSampleLimit));
            dataDouble = double(data(:, idx));
        else
            dataDouble = double(data);
        end

        dataDouble = dataDouble - mean(dataDouble, 2, 'omitnan');
        rankEstimate = rank(dataDouble');
    catch
        rankEstimate = NaN;
    end

end

function equivalent = spatial_filters_equivalent(A, B)

    equivalent = false;

    required = {'icaweights', 'icasphere'};
    for i = 1:numel(required)
        if ~isfield(A, required{i}) || isempty(A.(required{i})) || ...
                ~isfield(B, required{i}) || isempty(B.(required{i}))
            return;
        end
    end

    UA = double(A.icaweights) * double(A.icasphere);
    UB = double(B.icaweights) * double(B.icasphere);

    if ~isequal(size(UA), size(UB)) || any(~isfinite(UA(:))) || any(~isfinite(UB(:)))
        return;
    end

    normA = sqrt(sum(UA.^2, 2));
    normB = sqrt(sum(UB.^2, 2));
    if any(normA == 0) || any(normB == 0)
        return;
    end

    UA = UA ./ normA;
    UB = UB ./ normB;
    rowCosine = abs(sum(UA .* UB, 2));
    equivalent = all(rowCosine > 1 - 1e-8);

end

function [hasICLabel, metrics, dimOK] = extract_iclabel_metrics(EEG, nICs)

    hasICLabel = false;
    dimOK = false;

    metrics = struct();
    metrics.brainICs = NaN;
    metrics.brainICsP050 = NaN;
    metrics.brainICsP075 = NaN;
    metrics.eyeICs = NaN;
    metrics.muscleICs = NaN;
    metrics.heartICs = NaN;
    metrics.lineNoiseICs = NaN;
    metrics.channelNoiseICs = NaN;
    metrics.otherICs = NaN;

    if ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'ic_classification') || ...
            ~isfield(EEG.etc.ic_classification, 'ICLabel') || ...
            ~isfield(EEG.etc.ic_classification.ICLabel, 'classifications')
        return;
    end

    probs = EEG.etc.ic_classification.ICLabel.classifications;

    if isempty(probs) || size(probs, 2) < 7
        return;
    end

    hasICLabel = true;

    if ~isnan(nICs) && size(probs, 1) == nICs
        dimOK = true;
    end

    [~, dominantClass] = max(probs, [], 2);

    metrics.brainICs = sum(dominantClass == 1);
    metrics.muscleICs = sum(dominantClass == 2);
    metrics.eyeICs = sum(dominantClass == 3);
    metrics.heartICs = sum(dominantClass == 4);
    metrics.lineNoiseICs = sum(dominantClass == 5);
    metrics.channelNoiseICs = sum(dominantClass == 6);
    metrics.otherICs = sum(dominantClass == 7);

    metrics.brainICsP050 = sum(probs(:, 1) >= 0.50);
    metrics.brainICsP075 = sum(probs(:, 1) >= 0.75);

end

function [hasDIPFIT, metrics, dimOK] = extract_dipfit_metrics(EEG, nICs, rvThreshold15, rvThreshold20)

    hasDIPFIT = false;
    dimOK = false;

    metrics = struct();
    metrics.rvMedian = NaN;
    metrics.rvBelow15 = NaN;
    metrics.rvBelow20 = NaN;

    if ~isfield(EEG, 'dipfit') || ~isfield(EEG.dipfit, 'model') || isempty(EEG.dipfit.model)
        return;
    end

    if ~isnan(nICs) && numel(EEG.dipfit.model) == nICs
        dimOK = true;
    end

    rvValues = [];

    for k = 1:numel(EEG.dipfit.model)
        if isfield(EEG.dipfit.model(k), 'rv') && ~isempty(EEG.dipfit.model(k).rv)
            rvValues(end+1, 1) = double(EEG.dipfit.model(k).rv);
        end
    end

    rvValues = rvValues(isfinite(rvValues));

    if isempty(rvValues)
        return;
    end

    hasDIPFIT = true;
    metrics.rvMedian = median(rvValues);
    metrics.rvBelow15 = sum(rvValues < rvThreshold15);
    metrics.rvBelow20 = sum(rvValues < rvThreshold20);

end

