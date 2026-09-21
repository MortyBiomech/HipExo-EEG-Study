function [ALLEEG, EEG_preprocessed_and_ICA, CURRENTSET] = mod_bemobil_process_all_AMICA( ...
    ALLEEG, EEG_preprocessed, CURRENTSET, subject, bemobil_config, force_recompute)

% Modified from BeMoBIL bemobil_process_all_AMICA for the HipExo-EEG project.
%
% Project-specific modifications:
%   - Preserve zero-padded subject labels such as "01" and "03".
%   - Reuse existing AMICA, DIPFIT, and preprocessed_and_ICA stages when
%     force_recompute = false.
%   - Set EEGLAB option_computeica = 0 for large continuous datasets.
%   - Do not save AMICA_autoreject.fig; retain PNG only.
%   - Run DIPFIT with a minimal temporary data container while preserving
%     the original ICA scalp maps and DIPFIT settings.
%   - Run ICLabel feature extraction one IC at a time to avoid allocating
%     the full IC-by-time activation matrix in double precision.
%   - Do not generate the final vis_artifacts cleaned-data analytics figure.
%
% AMICA, DIPFIT, ICLabel classifier, filtering, ICLabel thresholds, and
% cleaning settings otherwise follow BeMoBIL and the project configuration.

%  CONFIG

bemobil_config = bemobil_check_config(bemobil_config);

expected_input_signature = "";

if isfield(EEG_preprocessed, 'etc') && ...
        isfield(EEG_preprocessed.etc, 'amica_input_signature')

    expected_input_signature = ...
        string(EEG_preprocessed.etc.amica_input_signature);

end

if numel(expected_input_signature) ~= 1 || ...
        strlength(strtrim(expected_input_signature)) == 0

    error('EEG.etc.amica_input_signature must contain one non-empty value.');

end

expected_stages = EEG_preprocessed.etc.amica_stage_signatures;
legacy_signature = string(EEG_preprocessed.etc.amica_legacy_match_signature);
reusable_classification = [];

try
    pop_editoptions( ...
        'option_saveversion6', 0, ...
        'option_single', 0, ...
        'option_memmapdata', 0, ...
        'option_savetwofiles', 1, ...
        'option_storedisk', 0, ...
        'option_computeica', 0);
catch
    warning('Could NOT edit EEGLAB memory options!!');
end

if ~exist('force_recompute', 'var')
    force_recompute = false;
end

if force_recompute
    warning('RECOMPUTING OLD FILES IF FOUND!!!')
end

%  SUBJECT LABEL

if isnumeric(subject)
    subject_label = num2str(subject);
elseif isstring(subject)
    subject_label = char(subject);
elseif ischar(subject)
    subject_label = subject;
else
    subject_label = char(string(subject));
end

subject_label = strtrim(subject_label);
subject_label = regexprep(subject_label, '^sub-', '');
subject_label = regexprep(subject_label, '[^A-Za-z0-9]', '');

subject_folder = ...
    [bemobil_config.filename_prefix subject_label];

%  OUTPUT PATHS

spatial_output_filepath = fullfile( ...
    bemobil_config.study_folder, ...
    bemobil_config.spatial_filters_folder, ...
    bemobil_config.spatial_filters_folder_AMICA, ...
    subject_folder);

single_output_filepath = fullfile( ...
    bemobil_config.study_folder, ...
    bemobil_config.single_subject_analysis_folder, ...
    subject_folder);

if ~exist(spatial_output_filepath, 'dir')
    mkdir(spatial_output_filepath);
end

if ~exist(single_output_filepath, 'dir')
    mkdir(single_output_filepath);
end

amica_filename = ...
    [subject_folder '_' bemobil_config.amica_filename_output];

dipfitted_filename = ...
    [subject_folder '_' bemobil_config.dipfitted_filename];

preprocessed_ica_filename = ...
    [subject_folder '_' bemobil_config.preprocessed_and_ICA_filename];

cleaned_ica_filename = ...
    [subject_folder '_' ...
     bemobil_config.single_subject_cleaned_ICA_filename];

amica_set_path = ...
    fullfile(spatial_output_filepath, amica_filename);

dipfitted_set_path = ...
    fullfile(spatial_output_filepath, dipfitted_filename);

preprocessed_ica_set_path = ...
    fullfile(single_output_filepath, preprocessed_ica_filename);

%  RESUME FROM EXISTING PREPROCESSED_AND_ICA

resume_from_preprocessed_ica = ...
    ~force_recompute && ...
    exist(preprocessed_ica_set_path, 'file') == 2;

if resume_from_preprocessed_ica

    EEG_single_subject_copied = load_complete_stage_local( ...
        preprocessed_ica_filename, single_output_filepath);

    if ~isempty(EEG_single_subject_copied) && hipexo.amica_stage_matches(EEG_single_subject_copied, ...
            expected_stages, 'prefinal', legacy_signature)

        fprintf('\nResuming from compatible preprocessed_and_ICA.set:\n%s\n', ...
            preprocessed_ica_set_path);

        EEG_single_subject_copied.icaact = [];

    else

        if ~isempty(EEG_single_subject_copied) && hipexo.amica_stage_matches(EEG_single_subject_copied, ...
                expected_stages, 'iclabel', legacy_signature) && ...
                isfield(EEG_single_subject_copied.etc, 'ic_classification')
            reusable_classification = EEG_single_subject_copied.etc.ic_classification;
        end
        clear EEG_single_subject_copied
        resume_from_preprocessed_ica = false;

    end

end

if resume_from_preprocessed_ica

    clear EEG_preprocessed
    ALLEEG = [];
    CURRENTSET = 0;

else

    %  RESUME FROM EXISTING DIPFIT

    EEG_dipfitted = [];

    if ~force_recompute && exist(dipfitted_set_path, 'file') == 2

        EEG_dipfitted = load_complete_stage_local( ...
            dipfitted_filename, spatial_output_filepath);

        if ~isempty(EEG_dipfitted) && hipexo.amica_stage_matches(EEG_dipfitted, ...
                expected_stages, 'dipfit', legacy_signature)

            fprintf('\nReusing compatible dipfitted.set:\n%s\n', ...
                dipfitted_set_path);

            EEG_dipfitted.icaact = [];
            ALLEEG = [];
            CURRENTSET = 0;

        else

            clear EEG_dipfitted
            EEG_dipfitted = [];

        end

    end

    if isempty(EEG_dipfitted)

    %  AMICA

    EEG_AMICA = [];

    if ~force_recompute && exist(amica_set_path, 'file') == 2

        EEG_AMICA = load_complete_stage_local( ...
            amica_filename, spatial_output_filepath);

        if ~isempty(EEG_AMICA) && hipexo.amica_stage_matches(EEG_AMICA, ...
                expected_stages, 'amica', legacy_signature)

            fprintf('\nReusing compatible AMICA.set:\n%s\n', ...
                amica_set_path);

            EEG_AMICA.icaact = [];
            ALLEEG = [];
            CURRENTSET = 0;

        else

            clear EEG_AMICA
            EEG_AMICA = [];

        end

    end

    %  COMPUTE AMICA ONLY IF NEEDED

    if isempty(EEG_AMICA)

        [ALLEEG, EEG_filtered_for_AMICA, CURRENTSET] = ...
            bemobil_filter( ...
                ALLEEG, ...
                EEG_preprocessed, ...
                CURRENTSET, ...
                bemobil_config.filter_lowCutoffFreqAMICA, ...
                bemobil_config.filter_highCutoffFreqAMICA, ...
                [], ...
                [], ...
                bemobil_config.filter_AMICA_highPassOrder, ...
                bemobil_config.filter_AMICA_lowPassOrder);

        EEG_filtered_for_AMICA.event = [];
        EEG_filtered_for_AMICA.urevent = [];

        if isfield(bemobil_config, 'use_reject_continuous') && ...
                bemobil_config.use_reject_continuous

            if ~isfield( ...
                    bemobil_config, ...
                    'reject_continuous_fixed_threshold') || ...
                    isempty( ...
                        bemobil_config.reject_continuous_fixed_threshold)

                bemobil_config.reject_continuous_fixed_threshold = 0.07;

            end

            bemobil_config.reject_continuous_epochs_length = 0.5;
            bemobil_config.reject_continuous_epochs_overlap = 0.125;
            bemobil_config.reject_continuous_epoch_buffer = 0.0625;
            bemobil_config.reject_continuous_weights = [1 1 1 1];
            bemobil_config.reject_continuous_use_kneepoint = 0;
            bemobil_config.reject_continuous_kneepoint_offset = 0;
            bemobil_config.reject_continuous_highpass_cutoff = 10;
            bemobil_config.reject_continuous_do_plot = 1;
            bemobil_config.reject_continuous_do_plot_continuous = 0;

            [ ...
                ALLEEG, ...
                EEG_filtered_for_AMICA, ...
                CURRENTSET, ...
                plot_handles ...
            ] = bemobil_reject_continuous( ...
                ALLEEG, ...
                EEG_filtered_for_AMICA, ...
                CURRENTSET, ...
                bemobil_config.reject_continuous_epochs_length, ...
                bemobil_config.reject_continuous_epochs_overlap, ...
                bemobil_config.reject_continuous_epoch_buffer, ...
                bemobil_config.reject_continuous_fixed_threshold, ...
                bemobil_config.reject_continuous_weights, ...
                bemobil_config.reject_continuous_use_kneepoint, ...
                bemobil_config.reject_continuous_kneepoint_offset, ...
                bemobil_config.reject_continuous_highpass_cutoff, ...
                bemobil_config.reject_continuous_do_plot, ...
                bemobil_config.reject_continuous_do_plot_continuous);

            if bemobil_config.reject_continuous_do_plot

                print( ...
                    plot_handles(1), ...
                    fullfile( ...
                        spatial_output_filepath, ...
                        [subject_folder '_time_domain-autoclean.png']), ...
                    '-dpng');

                for i_plot = 1:length(plot_handles)
                    close(plot_handles(i_plot));
                end

            end

        end

        [ALLEEG, EEG_AMICA, CURRENTSET] = ...
            bemobil_signal_decomposition( ...
                ALLEEG, ...
                EEG_filtered_for_AMICA, ...
                CURRENTSET, ...
                true, ...
                bemobil_config.num_models, ...
                bemobil_config.max_threads, ...
                EEG_filtered_for_AMICA.etc.rank, ...
                [], ...
                amica_filename, ...
                spatial_output_filepath, ...
                bemobil_config.AMICA_autoreject, ...
                bemobil_config.AMICA_n_rej, ...
                bemobil_config.AMICA_reject_sigma_threshold, ...
                bemobil_config.AMICA_max_iter);

        clear EEG_filtered_for_AMICA

        EEG_AMICA.icaact = [];

        %  AMICA AUTOREJECTION QC

        data2plot = ...
            EEG_AMICA.data( ...
                1:round(EEG_AMICA.nbchan/10):EEG_AMICA.nbchan, ...
                :)';

        figure;

        set( ...
            gcf, ...
            'color', ...
            'w', ...
            'Position', ...
            get(0, 'screensize'));

        plot(data2plot, 'g');

        data2plot(~EEG_AMICA.etc.bad_samples, :) = NaN;

        hold on
        plot(data2plot, 'r');

        xlim([-10000 EEG_AMICA.pnts + 10000]);
        ylim([-1000 1000]);

        title( ...
            ['AMICA autorejection, removed ' ...
             num2str(round(EEG_AMICA.etc.bad_samples_percent, 2)) ...
             '% of the samples']);

        xlabel('Samples');
        ylabel('\muV');

        drawnow
        clear data2plot

        % HipExo: PNG only. No savefig().
        print( ...
            gcf, ...
            fullfile( ...
                spatial_output_filepath, ...
                [subject_folder '_AMICA_autoreject.png']), ...
            '-dpng');

        close;

        %  PLOT ALL ICs

        pop_topoplot( ...
            EEG_AMICA, ...
            0, ...
            1:size(EEG_AMICA.icaweights, 1), ...
            EEG_AMICA.filename, ...
            [], ...
            0, ...
            'electrodes', ...
            'off');

        allICfighandle = gcf;

        print( ...
            allICfighandle, ...
            fullfile( ...
                spatial_output_filepath, ...
                [subject_folder '_all_ICs.png']), ...
            '-dpng');

        close(allICfighandle);

    end

    end

    %  DIPFIT

    %  COMPUTE DIPFIT ONLY IF NEEDED

    if isempty(EEG_dipfitted)

        % DIPFIT uses ICA scalp topographies. Keep the original ICA
        % decomposition and scalp maps, but avoid passing millions of
        % continuous samples into eeglab2fieldtrip.

        EEG_dipfit_work = EEG_AMICA;

        nIC = size(EEG_AMICA.icaweights, 1);

        EEG_dipfit_work.data = ...
            zeros(EEG_AMICA.nbchan, 2, 'like', EEG_AMICA.data);

        EEG_dipfit_work.icaact = ...
            zeros(nIC, 2, 'like', EEG_AMICA.icaweights);

        EEG_dipfit_work.pnts = 2;
        EEG_dipfit_work.trials = 1;
        EEG_dipfit_work.xmin = 0;
        EEG_dipfit_work.xmax = 1 / EEG_AMICA.srate;
        EEG_dipfit_work.times = ...
            [0 1000 / EEG_AMICA.srate];

        EEG_dipfit_work.event = [];
        EEG_dipfit_work.urevent = [];

        EEG_dipfit_work.filename = '';
        EEG_dipfit_work.filepath = '';
        EEG_dipfit_work.datfile = '';

        dipfitALLEEG = [];
        dipfitCURRENTSET = 0;

        [ ...
            dipfitALLEEG, ...
            EEG_dipfit_work, ...
            dipfitCURRENTSET ...
        ] = bemobil_dipfit( ...
            EEG_dipfit_work, ...
            dipfitALLEEG, ...
            dipfitCURRENTSET, ...
            bemobil_config.warping_channel_names, ...
            bemobil_config.residualVariance_threshold, ...
            bemobil_config.do_remove_outside_head, ...
            bemobil_config.number_of_dipoles);

        clear dipfitALLEEG dipfitCURRENTSET

        EEG_dipfitted = EEG_AMICA;

        EEG_dipfitted.chanlocs = ...
            EEG_dipfit_work.chanlocs;

        if isfield(EEG_dipfit_work, 'chaninfo')
            EEG_dipfitted.chaninfo = ...
                EEG_dipfit_work.chaninfo;
        end

        EEG_dipfitted.dipfit = ...
            EEG_dipfit_work.dipfit;

        if ~isfield(EEG_dipfitted, 'etc') || ...
                isempty(EEG_dipfitted.etc)

            EEG_dipfitted.etc = struct();

        end

        if isfield(EEG_dipfit_work, 'etc') && ...
                isfield(EEG_dipfit_work.etc, 'dipfit')

            EEG_dipfitted.etc.dipfit = ...
                EEG_dipfit_work.etc.dipfit;

        end

        EEG_dipfitted.icaact = [];

        clear EEG_dipfit_work EEG_AMICA

        EEG_dipfitted.etc.amica_input_signature = char(expected_input_signature);
        EEG_dipfitted.etc.amica_stage_signatures = expected_stages;
        EEG_dipfitted = pop_saveset( ...
            EEG_dipfitted, ...
            'filename', dipfitted_filename, ...
            'filepath', spatial_output_filepath);

        [~, ftpath] = ft_version;

        if contains(path, fullfile(ftpath, 'external', 'signal'))
            rmpath(fullfile(ftpath, 'external', 'signal'));
        end

        if contains(path, fullfile(ftpath, 'external', 'stats'))
            rmpath(fullfile(ftpath, 'external', 'stats'));
        end

        if contains(path, fullfile(ftpath, 'external', 'image'))
            rmpath(fullfile(ftpath, 'external', 'image'));
        end

    end

    %  COPY SPATIAL FILTER INTO FULL-LENGTH PREPROCESSED DATA

    EEG_preprocessed.icaact = [];
    EEG_dipfitted.icaact = [];
    EEG_dipfitted.etc.amica_input_signature = char(expected_input_signature);
    EEG_dipfitted.etc.amica_stage_signatures = expected_stages;

    ALLEEG = [];
    CURRENTSET = 0;

    EEG_preprocessed.etc.amica_stage_signatures.prefinal = '';
    EEG_preprocessed.etc.amica_stage_signatures.cleaned = '';
    EEG_dipfitted.etc.amica_stage_signatures.prefinal = '';
    EEG_dipfitted.etc.amica_stage_signatures.cleaned = '';

    [ALLEEG, EEG_single_subject_copied, CURRENTSET] = ...
        bemobil_copy_spatial_filter( ...
            EEG_preprocessed, ...
            ALLEEG, ...
            CURRENTSET, ...
            EEG_dipfitted, ...
            preprocessed_ica_filename, ...
            single_output_filepath);

    EEG_single_subject_copied.icaact = [];

    clear EEG_preprocessed EEG_dipfitted
    ALLEEG = [];
    CURRENTSET = 0;

end

%  CHECK WHETHER ICLABEL WAS ALREADY COMPLETED

EEG_single_subject_copied.etc.amica_input_signature = char(expected_input_signature);
EEG_single_subject_copied.etc.amica_stage_signatures = expected_stages;
if ~isempty(reusable_classification)
    EEG_single_subject_copied.etc.ic_classification = reusable_classification;
end

has_iclabel = false;

if isfield(EEG_single_subject_copied, 'etc') && ...
        isfield(EEG_single_subject_copied.etc, 'ic_classification') && ...
        isfield( ...
            EEG_single_subject_copied.etc.ic_classification, ...
            'ICLabel') && ...
        isfield( ...
            EEG_single_subject_copied.etc.ic_classification.ICLabel, ...
            'classifications') && ...
        ~isempty( ...
            EEG_single_subject_copied.etc.ic_classification.ICLabel.classifications)

    has_iclabel = true;

end

%  MEMORY-SAFE ICLABEL

if ~has_iclabel

    iclabel_version = ...
        lower(char(string(bemobil_config.iclabel_classifier)));

    if isempty(iclabel_version)
        iclabel_version = 'default';
    end

    if ~any(strcmp(iclabel_version, {'default', 'lite', 'beta'}))
        error( ...
            'Unsupported ICLabel classifier version in configuration: %s', ...
            iclabel_version);
    end

    flag_autocorr = ...
        any(strcmpi(iclabel_version, {'', 'default'}));

    %  MATCH ICLABEL REFERENCE HANDLING

    EEG_iclabel_source = EEG_single_subject_copied;
    EEG_iclabel_source.icaact = [];

    if ~isequal(EEG_iclabel_source.ref, 'average') && ...
            ~isequal(EEG_iclabel_source.ref, 'averef')

        [~, EEG_iclabel_source] = evalc( ...
            'pop_reref(EEG_iclabel_source, [], ''exclude'', setdiff(1:EEG_iclabel_source.nbchan, EEG_iclabel_source.icachansind));');

        EEG_iclabel_source.icaact = [];

    end

    %  TOPOGRAPHY FEATURES

    ncomp = size(EEG_iclabel_source.icawinv, 2);

    topo = zeros(32, 32, 1, ncomp);

    for ic = 1:ncomp

        if ~exist('OCTAVE_VERSION', 'builtin')

            [~, temp_topo] = ...
                topoplotFast( ...
                    EEG_iclabel_source.icawinv(:, ic), ...
                    EEG_iclabel_source.chanlocs( ...
                        EEG_iclabel_source.icachansind), ...
                    'noplot', ...
                    'on');

        else

            [~, temp_topo] = ...
                topoplot( ...
                    EEG_iclabel_source.icawinv(:, ic), ...
                    EEG_iclabel_source.chanlocs( ...
                        EEG_iclabel_source.icachansind), ...
                    'noplot', ...
                    'on', ...
                    'gridscale', ...
                    32);

        end

        temp_topo(isnan(temp_topo)) = 0;

        topo(:, :, 1, ic) = ...
            temp_topo / max(abs(temp_topo(:)));

    end

    topo = single(topo);

    %  PSD + AUTOCORRELATION FEATURES
    %
    %  Use the ICLabel plugin's own eeg_rpsd and eeg_autocorr_welch
    %  functions, but pass one IC activation at a time.

    psd_features = zeros(ncomp, 100);

    if flag_autocorr
        autocorr_features = zeros(ncomp, 100);
    end

    for ic = 1:ncomp

        % Only one IC activation vector is materialized in memory.
        one_icaact = ...
            eeg_getica(EEG_iclabel_source, ic);

        one_icaact = double(one_icaact);

        one_ic_eeg = struct();

        % eeg_rpsd / eeg_autocorr_welch use the number of rows in
        % icaweights as the number of components.
        one_ic_eeg.icaweights = 1;

        one_ic_eeg.icaact = reshape( ...
            one_icaact, ...
            [1, ...
             EEG_iclabel_source.pnts, ...
             EEG_iclabel_source.trials]);

        one_ic_eeg.pnts = ...
            EEG_iclabel_source.pnts;

        one_ic_eeg.trials = ...
            EEG_iclabel_source.trials;

        one_ic_eeg.srate = ...
            EEG_iclabel_source.srate;

        this_psd = ...
            eeg_rpsd(one_ic_eeg, 100);

        psd_features(ic, :) = ...
            this_psd(1, :);

        if flag_autocorr

            if EEG_iclabel_source.trials == 1

                if EEG_iclabel_source.pnts / ...
                        EEG_iclabel_source.srate > 5

                    this_autocorr = ...
                        eeg_autocorr_welch(one_ic_eeg);

                else

                    this_autocorr = ...
                        eeg_autocorr(one_ic_eeg);

                end

            else

                this_autocorr = ...
                    eeg_autocorr_fftw(one_ic_eeg);

            end

            autocorr_features(ic, :) = ...
                this_autocorr(1, :);

        end

        clear one_icaact one_ic_eeg this_psd this_autocorr

    end

    %  SAME PSD POST-PROCESSING AS ICL_FEATURE_EXTRACTOR

    nfreq = size(psd_features, 2);

    if nfreq < 100

        psd_features = [ ...
            psd_features, ...
            repmat( ...
                psd_features(:, end), ...
                1, ...
                100 - nfreq)];

    end

    for linenoise_ind = [50, 60]

        linenoise_around = ...
            [linenoise_ind - 1, linenoise_ind + 1];

        difference = ...
            bsxfun( ...
                @minus, ...
                psd_features(:, linenoise_around), ...
                psd_features(:, linenoise_ind));

        notch_ind = ...
            all(difference > 5, 2);

        if any(notch_ind)

            psd_features(notch_ind, linenoise_ind) = ...
                mean( ...
                    psd_features( ...
                        notch_ind, ...
                        linenoise_around), ...
                    2);

        end

    end

    psd_features = ...
        bsxfun( ...
            @rdivide, ...
            psd_features, ...
            max(abs(psd_features), [], 2));

    psd_features = ...
        single(permute(psd_features, [3 2 4 1]));

    if flag_autocorr

        autocorr_features = ...
            single(permute( ...
                autocorr_features, ...
                [3 2 4 1]));

    end

    %  OFFICIAL ICLABEL NETWORK

    if flag_autocorr

        labels = run_ICL( ...
            iclabel_version, ...
            0.99 * topo, ...
            0.99 * psd_features, ...
            0.99 * autocorr_features);

    else

        labels = run_ICL( ...
            iclabel_version, ...
            0.99 * topo, ...
            0.99 * psd_features);

    end

    %  STORE ICLABEL RESULTS

    if ~isfield(EEG_single_subject_copied, 'etc') || ...
            isempty(EEG_single_subject_copied.etc)

        EEG_single_subject_copied.etc = struct();

    end

    EEG_single_subject_copied.etc.ic_classification.ICLabel.classes = ...
        { ...
            'Brain', ...
            'Muscle', ...
            'Eye', ...
            'Heart', ...
            'Line Noise', ...
            'Channel Noise', ...
            'Other' ...
        };

    EEG_single_subject_copied.etc.ic_classification.ICLabel.classifications = ...
        labels;

    EEG_single_subject_copied.etc.ic_classification.ICLabel.version = ...
        iclabel_version;

    EEG_single_subject_copied.icaact = [];

    clear EEG_iclabel_source
    clear topo psd_features autocorr_features labels

    ALLEEG = [];
    CURRENTSET = 0;

end

if ~resume_from_preprocessed_ica
    [ ...
        ALLEEG, ...
        EEG_single_subject_copied, ...
        CURRENTSET ...
    ] = bemobil_filter( ...
        ALLEEG, ...
        EEG_single_subject_copied, ...
        CURRENTSET, ...
        bemobil_config.final_filter_lower_edge, ...
        bemobil_config.final_filter_higher_edge, ...
        erase(preprocessed_ica_filename, '.set'), ...
        single_output_filepath);

    EEG_single_subject_copied.icaact = [];
end

%  CLEAN WITH ICLABEL

% Keep only the dataset required for the cleaning operation.
ALLEEG = [];
CURRENTSET = 0;

[ALLEEG, EEG_single_subject_copied, CURRENTSET] = ...
    eeg_store( ...
        ALLEEG, ...
        EEG_single_subject_copied, ...
        1);

EEG_single_subject_copied.icaact = [];

[ ...
    ALLEEG, ...
    EEG_preprocessed_and_ICA, ...
    CURRENTSET, ...
    ICs_keep, ...
    ICs_throw ...
] = bemobil_clean_with_iclabel( ...
    EEG_single_subject_copied, ...
    ALLEEG, ...
    CURRENTSET, ...
    bemobil_config.iclabel_classifier, ...
    bemobil_config.iclabel_classes, ...
    bemobil_config.iclabel_threshold, ...
    cleaned_ica_filename, ...
    single_output_filepath); %#ok<ASGLU>

%  FINAL ANALYTICS FIGURE

% HipExo:
% The original BeMoBIL vis_artifacts figure is omitted for these long
% continuous subject-level datasets. The required analysis datasets have
% already been saved above.

disp('AMICA processing completed.');

end


function EEG = load_complete_stage_local(filename, folder)
EEG = [];
try
    candidate = pop_loadset('filename', filename, 'filepath', folder);
    if isnumeric(candidate.data) && ~isempty(candidate.data) && ...
            numel(candidate.data) == double(candidate.nbchan)*double(candidate.pnts)*double(candidate.trials)
        EEG = candidate;
    end
catch
    % Missing/corrupt intermediate output: use an earlier verified stage.
end
end
