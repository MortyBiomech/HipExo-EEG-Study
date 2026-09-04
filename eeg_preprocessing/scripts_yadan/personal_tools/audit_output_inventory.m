%% audit_output_inventory.m
% Read-only audit of the complete HipExo output_data folder.
%
% This script does not change, move, delete, epoch, resave or overwrite any
% existing EEG/STUDY result. It only reads file metadata and writes audit
% files into:
%
%   output_data/00_output_inventory_audit/
%
% Upload output_audit_bundle.zip from that folder for the next review.

clear;
clc;

%% ------------------------------------------------------------------------
% LOCATION
% -------------------------------------------------------------------------
% Normally leave this empty. The script then reads outputFolder from paths.m.
% If this script is not stored beside paths.m, enter output_data manually:
% manualOutputRoot = "E:\master_thesis\HipExo-EEG-Study_1\EEG_preprocessing_Yadan\output_data";
manualOutputRoot = "";

scriptFolder = fileparts(mfilename('fullpath'));
pathsFile = fullfile(scriptFolder, 'project_paths.m');

if strlength(manualOutputRoot) > 0
    outputRoot = char(manualOutputRoot);
elseif isfile(pathsFile)
    run(pathsFile);
    assert(exist('outputFolder', 'var') == 1, ...
        'paths.m did not create the variable outputFolder.');
    outputRoot = char(outputFolder);
else
    selectedFolder = uigetdir(pwd, 'Select the output_data folder');
    assert(~isequal(selectedFolder, 0), ...
        'No output_data folder was selected.');
    outputRoot = selectedFolder;
end

assert(isfolder(outputRoot), ...
    'output_data folder does not exist:\n%s', outputRoot);

auditFolder = fullfile(outputRoot, '00_output_inventory_audit');
if ~isfolder(auditFolder)
    mkdir(auditFolder);
end

%% ------------------------------------------------------------------------
% EEGLAB METADATA READER
% -------------------------------------------------------------------------
% pop_loadset(..., 'loadmode', 'info') reads EEG metadata without loading
% the large signal array from the paired .fdt file.
if exist('pop_loadset', 'file') ~= 2
    assert(exist('eeglab', 'file') == 2, ...
        ['EEGLAB was not found. Check eeglabFolder in paths.m, then run ' ...
         'this script again.']);
    eeglab('nogui');
end

assert(exist('pop_loadset', 'file') == 2, ...
    'EEGLAB pop_loadset is not available after EEGLAB startup.');

fprintf('============================================================\n');
fprintf('HipExo output inventory audit\n');
fprintf('Root: %s\n', outputRoot);
fprintf('The audit is read-only for all existing outputs.\n');
fprintf('============================================================\n');

auditStarted = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');

%% ------------------------------------------------------------------------
% COMPLETE FILE/FOLDER INVENTORY
% -------------------------------------------------------------------------
allItems = dir(fullfile(outputRoot, '**', '*'));

fileRows = repmat(file_row_template_local(), 0, 1);
setPaths = strings(0, 1);
studyPaths = strings(0, 1);

for itemIndex = 1:numel(allItems)
    item = allItems(itemIndex);
    fullPath = fullfile(item.folder, item.name);

    % Do not audit the audit outputs themselves.
    if is_same_or_child_path_local(fullPath, auditFolder)
        continue;
    end

    row = file_row_template_local();
    row.ItemType = string(ternary_local(item.isdir, 'folder', 'file'));
    row.Name = string(item.name);
    [~, stem, extension] = fileparts(item.name);
    row.Stem = string(stem);
    row.Extension = lower(string(extension));
    row.FileKind = classify_file_local(extension, item.isdir);
    row.RelativePath = relative_path_local(fullPath, outputRoot);
    row.FullPath = string(fullPath);
    row.ParentRelativePath = relative_path_local(item.folder, outputRoot);
    row.Bytes = double(item.bytes);
    row.Modified = format_datenum_local(item.datenum);

    if ~item.isdir && strcmpi(extension, '.set')
        pairedFDT = fullfile(item.folder, [stem '.fdt']);
        row.PairedFDTPath = string(pairedFDT);
        row.PairedFDTExists = isfile(pairedFDT);
        setPaths(end + 1, 1) = string(fullPath); %#ok<SAGROW>
    elseif ~item.isdir && strcmpi(extension, '.fdt')
        pairedSET = fullfile(item.folder, [stem '.set']);
        row.PairedSETPath = string(pairedSET);
        row.PairedSETExists = isfile(pairedSET);
    elseif ~item.isdir && strcmpi(extension, '.study')
        studyPaths(end + 1, 1) = string(fullPath); %#ok<SAGROW>
    end

    fileRows(end + 1, 1) = row; %#ok<SAGROW>
end

fileInventory = struct_rows_to_table_local( ...
    fileRows, file_row_template_local());
setPaths = unique(setPaths, 'stable');
studyPaths = unique(studyPaths, 'stable');

fprintf('Filesystem scan: %d items, %d SET files, %d STUDY files.\n', ...
    height(fileInventory), numel(setPaths), numel(studyPaths));

%% ------------------------------------------------------------------------
% EEGLAB .SET METADATA
% -------------------------------------------------------------------------
setRows = repmat(set_row_template_local(), 0, 1);
eventRows = repmat(event_row_template_local(), 0, 1);
errorRows = repmat(error_row_template_local(), 0, 1);

for setIndex = 1:numel(setPaths)
    setPath = char(setPaths(setIndex));
    [setFolder, setFilename, setExtension] = fileparts(setPath);
    setFilename = [setFilename setExtension];

    fprintf('SET %d/%d: %s\n', setIndex, numel(setPaths), ...
        relative_path_local(setPath, outputRoot));

    row = set_row_template_local();
    row.FullPath = string(setPath);
    row.RelativePath = relative_path_local(setPath, outputRoot);
    fileInfo = dir(setPath);
    if ~isempty(fileInfo)
        row.FileBytes = double(fileInfo(1).bytes);
        row.Modified = format_datenum_local(fileInfo(1).datenum);
    end

    try
        EEG = pop_loadset( ...
            'filename', setFilename, ...
            'filepath', setFolder, ...
            'loadmode', 'info');

        row.LoadStatus = "OK";
        row.SetName = field_string_local(EEG, 'setname');
        row.Subject = field_string_local(EEG, 'subject');
        row.Condition = field_string_local(EEG, 'condition');
        row.Group = field_string_local(EEG, 'group');
        row.Session = field_string_local(EEG, 'session');
        row.Run = field_string_local(EEG, 'run');
        row.ETCFieldNames = struct_field_names_local(EEG, 'etc');
        row.EventFieldNames = struct_field_names_local(EEG, 'event');
        row.EpochFieldNames = struct_field_names_local(EEG, 'epoch');
        row.UreventCount = number_of_elements_local(EEG, 'urevent');

        row.NbChan = field_double_local(EEG, 'nbchan');
        row.Pnts = field_double_local(EEG, 'pnts');
        row.Trials = field_double_local(EEG, 'trials');
        row.SRate = field_double_local(EEG, 'srate');
        row.XMinSeconds = field_double_local(EEG, 'xmin');
        row.XMaxSeconds = field_double_local(EEG, 'xmax');
        row.TotalSamples = row.Pnts * row.Trials;

        if isfinite(row.SRate) && row.SRate > 0
            row.TotalDataSeconds = row.TotalSamples / row.SRate;
        end
        if isfinite(row.XMinSeconds) && isfinite(row.XMaxSeconds)
            row.EpochWindowSeconds = ...
                row.XMaxSeconds - row.XMinSeconds;
        end

        if row.Trials > 1 || ...
                (isfield(EEG, 'epoch') && ~isempty(EEG.epoch))
            row.DataKind = "epoched";
        else
            row.DataKind = "continuous";
        end

        if isfield(EEG, 'event') && ~isempty(EEG.event)
            row.EventCount = numel(EEG.event);
            typeLabels = event_field_values_local(EEG.event, 'type');
            typeLabelsUpper = upper(strtrim(typeLabels));
            row.UniqueEventTypeCount = numel(unique(typeLabelsUpper));
            row.EventTypes = join_unique_local(typeLabels);
            row.RHSCount = sum(typeLabelsUpper == "RHS");
            row.LTOCount = sum(typeLabelsUpper == "LTO");
            row.LHSCount = sum(typeLabelsUpper == "LHS");
            row.RTOCount = sum(typeLabelsUpper == "RTO");
            row.HasCompleteGaitEventSet = all([ ...
                row.RHSCount, row.LTOCount, ...
                row.LHSCount, row.RTOCount] > 0);

            eventRows = append_event_counts_local( ...
                eventRows, EEG.event, setPath, row.Subject, 'type');
            eventRows = append_event_counts_local( ...
                eventRows, EEG.event, setPath, row.Subject, 'condition');
            eventRows = append_event_counts_local( ...
                eventRows, EEG.event, setPath, row.Subject, 'cond');
            eventRows = append_event_counts_local( ...
                eventRows, EEG.event, setPath, row.Subject, 'subcond');

            conditionLabels = [ ...
                event_field_values_local(EEG.event, 'condition'); ...
                event_field_values_local(EEG.event, 'cond')];
            row.EventConditionLabels = join_unique_local(conditionLabels);
        end

        [row.HasICA, row.ICAComponentCount] = ica_info_local(EEG);
        [row.HasDIPFIT, row.DIPFITModelCount, ...
            row.ValidDipoleCount] = dipfit_info_local(EEG);
        row.HasICLabel = has_iclabel_local(EEG);

        [row.HasManualICSelection, row.ManualYesICCount, ...
            row.ManualYesICs] = manual_selection_info_local(EEG);

        [row.HasTimewarp, row.TimewarpAcceptedEpochCount, ...
            row.TimewarpLatencyRows, row.TimewarpWarptoCount, ...
            row.TimewarpFieldNames] = ...
            timewarp_info_local(EEG);

        [row.ExternalDataFile, row.ExternalDataExists] = ...
            external_data_info_local(EEG, setFolder, setPath);

        clear EEG;
    catch setError
        row.LoadStatus = "ERROR";
        row.LoadError = clean_message_local(setError.message);
        errorRow = error_row_template_local();
        errorRow.SourceType = "SET";
        errorRow.RelativePath = relative_path_local(setPath, outputRoot);
        errorRow.FullPath = string(setPath);
        errorRow.Message = clean_message_local(setError.message);
        errorRows(end + 1, 1) = errorRow; %#ok<SAGROW>
        clear EEG;
    end

    setRows(end + 1, 1) = row; %#ok<SAGROW>
end

setInventory = struct_rows_to_table_local( ...
    setRows, set_row_template_local());
eventInventory = struct_rows_to_table_local( ...
    eventRows, event_row_template_local());

%% ------------------------------------------------------------------------
% EEGLAB .STUDY METADATA AND REFERENCES
% -------------------------------------------------------------------------
studyRows = repmat(study_row_template_local(), 0, 1);
studyDatasetRows = repmat(study_dataset_row_template_local(), 0, 1);
clusterRows = repmat(cluster_row_template_local(), 0, 1);
clusterMemberRows = repmat(cluster_member_row_template_local(), 0, 1);

for studyIndex = 1:numel(studyPaths)
    studyPath = char(studyPaths(studyIndex));
    studyFolder = fileparts(studyPath);

    fprintf('STUDY %d/%d: %s\n', studyIndex, numel(studyPaths), ...
        relative_path_local(studyPath, outputRoot));

    row = study_row_template_local();
    row.FullPath = string(studyPath);
    row.RelativePath = relative_path_local(studyPath, outputRoot);
    fileInfo = dir(studyPath);
    if ~isempty(fileInfo)
        row.FileBytes = double(fileInfo(1).bytes);
        row.Modified = format_datenum_local(fileInfo(1).datenum);
    end

    try
        loadedStudy = load(studyPath, '-mat');
        if isfield(loadedStudy, 'STUDY')
            STUDY = loadedStudy.STUDY;
        else
            variableNames = fieldnames(loadedStudy);
            studyCandidate = [];
            for variableIndex = 1:numel(variableNames)
                candidate = loadedStudy.(variableNames{variableIndex});
                if isstruct(candidate) && ...
                        isfield(candidate, 'datasetinfo')
                    studyCandidate = candidate;
                    break;
                end
            end
            assert(~isempty(studyCandidate), ...
                'No STUDY structure was found in this .study file.');
            STUDY = studyCandidate;
        end

        row.LoadStatus = "OK";
        row.StudyName = field_string_local(STUDY, 'name');
        row.StoredFilename = field_string_local(STUDY, 'filename');
        row.ETCFieldNames = struct_field_names_local(STUDY, 'etc');
        row.DatasetCount = number_of_elements_local(STUDY, 'datasetinfo');
        row.DesignCount = number_of_elements_local(STUDY, 'design');
        row.ClusterCount = number_of_elements_local(STUDY, 'cluster');
        [row.HasERSPPrecompute, row.HasSpectrumPrecompute, ...
            row.PrecomputeMeasureNames] = study_precompute_info_local(STUDY);

        if isfield(STUDY, 'datasetinfo') && ~isempty(STUDY.datasetinfo)
            subjects = strings(0, 1);
            conditions = strings(0, 1);
            groups = strings(0, 1);
            missingReferenceCount = 0;

            for datasetIndex = 1:numel(STUDY.datasetinfo)
                info = STUDY.datasetinfo(datasetIndex);
                datasetRow = study_dataset_row_template_local();
                datasetRow.StudyPath = string(studyPath);
                datasetRow.StudyName = row.StudyName;
                datasetRow.DatasetIndex = datasetIndex;
                datasetRow.Subject = field_string_local(info, 'subject');
                datasetRow.Condition = field_string_local(info, 'condition');
                datasetRow.Group = field_string_local(info, 'group');
                datasetRow.Session = field_string_local(info, 'session');
                datasetRow.Run = field_string_local(info, 'run');
                datasetRow.DatasetFilename = ...
                    field_string_local(info, 'filename');
                datasetRow.DatasetFilepath = ...
                    field_string_local(info, 'filepath');
                datasetRow.ResolvedSETPath = resolve_study_set_path_local( ...
                    info, studyFolder);
                datasetRow.SETExists = isfile(datasetRow.ResolvedSETPath);
                missingReferenceCount = missingReferenceCount + ...
                    double(~datasetRow.SETExists);

                selectedComponents = field_numeric_vector_local(info, 'comps');
                datasetRow.SelectedICCount = numel(selectedComponents);
                datasetRow.SelectedICs = numeric_list_local(selectedComponents);

                studyDatasetRows(end + 1, 1) = datasetRow; %#ok<SAGROW>
                subjects(end + 1, 1) = datasetRow.Subject; %#ok<SAGROW>
                conditions(end + 1, 1) = datasetRow.Condition; %#ok<SAGROW>
                groups(end + 1, 1) = datasetRow.Group; %#ok<SAGROW>
            end

            row.SubjectCount = numel(unique_nonempty_local(subjects));
            row.Subjects = join_unique_local(subjects);
            row.Conditions = join_unique_local(conditions);
            row.Groups = join_unique_local(groups);
            row.MissingDatasetReferenceCount = missingReferenceCount;
        end

        [row.HasBeMoBILClustering, row.ROIMNI, row.ROIClusterIndex] = ...
            study_bemobil_info_local(STUDY);

        if isfield(STUDY, 'cluster') && ~isempty(STUDY.cluster)
            for clusterIndex = 1:numel(STUDY.cluster)
                clusterInfo = STUDY.cluster(clusterIndex);
                [setIndices, componentIndices] = ...
                    cluster_membership_local(clusterInfo);

                clusterRow = cluster_row_template_local();
                clusterRow.StudyPath = string(studyPath);
                clusterRow.StudyName = row.StudyName;
                clusterRow.ClusterIndex = clusterIndex;
                clusterRow.ClusterName = ...
                    field_string_local(clusterInfo, 'name');
                clusterRow.MemberCount = numel(componentIndices);
                clusterRow.SubjectCount = cluster_subject_count_local( ...
                    STUDY, setIndices);
                clusterRow.IsParentCluster = contains( ...
                    lower(clusterRow.ClusterName), 'parent');
                clusterRow.IsOutlierCluster = contains( ...
                    lower(clusterRow.ClusterName), 'outlier');
                [clusterRow.CentroidX, clusterRow.CentroidY, ...
                    clusterRow.CentroidZ] = cluster_centroid_local(clusterInfo);
                clusterRows(end + 1, 1) = clusterRow; %#ok<SAGROW>

                for memberIndex = 1:numel(componentIndices)
                    memberRow = cluster_member_row_template_local();
                    memberRow.StudyPath = string(studyPath);
                    memberRow.StudyName = row.StudyName;
                    memberRow.ClusterIndex = clusterIndex;
                    memberRow.ClusterName = clusterRow.ClusterName;
                    memberRow.MemberIndex = memberIndex;
                    memberRow.DatasetIndex = setIndices(memberIndex);
                    memberRow.Component = componentIndices(memberIndex);

                    if memberRow.DatasetIndex >= 1 && ...
                            memberRow.DatasetIndex <= numel(STUDY.datasetinfo)
                        datasetInfo = STUDY.datasetinfo( ...
                            memberRow.DatasetIndex);
                        memberRow.Subject = ...
                            field_string_local(datasetInfo, 'subject');
                        memberRow.Condition = ...
                            field_string_local(datasetInfo, 'condition');
                    end

                    clusterMemberRows(end + 1, 1) = memberRow; %#ok<SAGROW>
                end
            end
        end

        clear STUDY loadedStudy;
    catch studyError
        row.LoadStatus = "ERROR";
        row.LoadError = clean_message_local(studyError.message);
        errorRow = error_row_template_local();
        errorRow.SourceType = "STUDY";
        errorRow.RelativePath = relative_path_local(studyPath, outputRoot);
        errorRow.FullPath = string(studyPath);
        errorRow.Message = clean_message_local(studyError.message);
        errorRows(end + 1, 1) = errorRow; %#ok<SAGROW>
        clear STUDY loadedStudy;
    end

    studyRows(end + 1, 1) = row; %#ok<SAGROW>
end

studyInventory = struct_rows_to_table_local( ...
    studyRows, study_row_template_local());
studyDatasetReferences = struct_rows_to_table_local( ...
    studyDatasetRows, study_dataset_row_template_local());
studyClusterInventory = struct_rows_to_table_local( ...
    clusterRows, cluster_row_template_local());
studyClusterMembership = struct_rows_to_table_local( ...
    clusterMemberRows, cluster_member_row_template_local());
auditErrors = struct_rows_to_table_local( ...
    errorRows, error_row_template_local());

%% ------------------------------------------------------------------------
% SAVE TABLES
% -------------------------------------------------------------------------
outputInventoryPath = fullfile(auditFolder, 'output_inventory.csv');
setInventoryPath = fullfile(auditFolder, 'eeg_set_inventory.csv');
eventInventoryPath = fullfile(auditFolder, 'eeg_event_inventory.csv');
studyInventoryPath = fullfile(auditFolder, 'study_inventory.csv');
studyReferencesPath = fullfile( ...
    auditFolder, 'study_dataset_references.csv');
clusterInventoryPath = fullfile( ...
    auditFolder, 'study_cluster_inventory.csv');
clusterMembershipPath = fullfile( ...
    auditFolder, 'study_cluster_membership.csv');
errorPath = fullfile(auditFolder, 'output_audit_errors.csv');
metadataPath = fullfile(auditFolder, 'output_metadata.mat');
reportPath = fullfile(auditFolder, 'output_audit_report.txt');

writetable(fileInventory, outputInventoryPath);
writetable(setInventory, setInventoryPath);
writetable(eventInventory, eventInventoryPath);
writetable(studyInventory, studyInventoryPath);
writetable(studyDatasetReferences, studyReferencesPath);
writetable(studyClusterInventory, clusterInventoryPath);
writetable(studyClusterMembership, clusterMembershipPath);
writetable(auditErrors, errorPath);

auditFinished = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
auditConfiguration = struct();
auditConfiguration.output_root = outputRoot;
auditConfiguration.audit_folder = auditFolder;
auditConfiguration.started = char(auditStarted);
auditConfiguration.finished = char(auditFinished);
auditConfiguration.read_only_for_existing_outputs = true;
auditConfiguration.set_loadmode = 'info';

save(metadataPath, ...
    'fileInventory', ...
    'setInventory', ...
    'eventInventory', ...
    'studyInventory', ...
    'studyDatasetReferences', ...
    'studyClusterInventory', ...
    'studyClusterMembership', ...
    'auditErrors', ...
    'auditConfiguration', ...
    '-v7.3');

%% ------------------------------------------------------------------------
% HUMAN-READABLE REPORT
% -------------------------------------------------------------------------
write_report_local( ...
    reportPath, outputRoot, auditStarted, auditFinished, ...
    fileInventory, setInventory, studyInventory, ...
    studyDatasetReferences, studyClusterInventory, auditErrors);

%% ------------------------------------------------------------------------
% ONE SMALL FILE TO UPLOAD
% -------------------------------------------------------------------------
bundleNames = { ...
    'output_inventory.csv', ...
    'eeg_set_inventory.csv', ...
    'eeg_event_inventory.csv', ...
    'study_inventory.csv', ...
    'study_dataset_references.csv', ...
    'study_cluster_inventory.csv', ...
    'study_cluster_membership.csv', ...
    'output_audit_errors.csv', ...
    'output_metadata.mat', ...
    'output_audit_report.txt'};

bundlePath = fullfile(auditFolder, 'output_audit_bundle.zip');
create_zip_bundle_local(auditFolder, bundleNames, bundlePath);

fprintf('\n============================================================\n');
fprintf('Output inventory audit completed.\n');
fprintf('Report: %s\n', reportPath);
fprintf('Upload this file to ChatGPT:\n%s\n', bundlePath);
fprintf('Do not upload the large .fdt files.\n');
fprintf('============================================================\n');

%% ========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function row = file_row_template_local()
    row = struct( ...
        'ItemType', "", ...
        'FileKind', "", ...
        'Name', "", ...
        'Stem', "", ...
        'Extension', "", ...
        'RelativePath', "", ...
        'FullPath', "", ...
        'ParentRelativePath', "", ...
        'Bytes', NaN, ...
        'Modified', "", ...
        'PairedSETPath', "", ...
        'PairedSETExists', false, ...
        'PairedFDTPath', "", ...
        'PairedFDTExists', false);
end

function row = set_row_template_local()
    row = struct( ...
        'FullPath', "", ...
        'RelativePath', "", ...
        'FileBytes', NaN, ...
        'Modified', "", ...
        'LoadStatus', "NOT_READ", ...
        'LoadError', "", ...
        'SetName', "", ...
        'Subject', "", ...
        'Condition', "", ...
        'Group', "", ...
        'Session', "", ...
        'Run', "", ...
        'ETCFieldNames', "", ...
        'EventFieldNames', "", ...
        'EpochFieldNames', "", ...
        'DataKind', "", ...
        'NbChan', NaN, ...
        'Pnts', NaN, ...
        'Trials', NaN, ...
        'SRate', NaN, ...
        'XMinSeconds', NaN, ...
        'XMaxSeconds', NaN, ...
        'EpochWindowSeconds', NaN, ...
        'TotalSamples', NaN, ...
        'TotalDataSeconds', NaN, ...
        'EventCount', 0, ...
        'UreventCount', 0, ...
        'UniqueEventTypeCount', 0, ...
        'EventTypes', "", ...
        'RHSCount', 0, ...
        'LTOCount', 0, ...
        'LHSCount', 0, ...
        'RTOCount', 0, ...
        'HasCompleteGaitEventSet', false, ...
        'EventConditionLabels', "", ...
        'HasICA', false, ...
        'ICAComponentCount', 0, ...
        'HasDIPFIT', false, ...
        'DIPFITModelCount', 0, ...
        'ValidDipoleCount', 0, ...
        'HasICLabel', false, ...
        'HasManualICSelection', false, ...
        'ManualYesICCount', 0, ...
        'ManualYesICs', "", ...
        'HasTimewarp', false, ...
        'TimewarpAcceptedEpochCount', 0, ...
        'TimewarpLatencyRows', 0, ...
        'TimewarpWarptoCount', 0, ...
        'TimewarpFieldNames', "", ...
        'ExternalDataFile', "", ...
        'ExternalDataExists', false);
end

function row = event_row_template_local()
    row = struct( ...
        'SETPath', "", ...
        'Subject', "", ...
        'Category', "", ...
        'Label', "", ...
        'Count', 0);
end

function row = study_row_template_local()
    row = struct( ...
        'FullPath', "", ...
        'RelativePath', "", ...
        'FileBytes', NaN, ...
        'Modified', "", ...
        'LoadStatus', "NOT_READ", ...
        'LoadError', "", ...
        'StudyName', "", ...
        'StoredFilename', "", ...
        'ETCFieldNames', "", ...
        'DatasetCount', 0, ...
        'SubjectCount', 0, ...
        'Subjects', "", ...
        'Conditions', "", ...
        'Groups', "", ...
        'DesignCount', 0, ...
        'ClusterCount', 0, ...
        'HasERSPPrecompute', false, ...
        'HasSpectrumPrecompute', false, ...
        'PrecomputeMeasureNames', "", ...
        'MissingDatasetReferenceCount', 0, ...
        'HasBeMoBILClustering', false, ...
        'ROIMNI', "", ...
        'ROIClusterIndex', NaN);
end

function row = study_dataset_row_template_local()
    row = struct( ...
        'StudyPath', "", ...
        'StudyName', "", ...
        'DatasetIndex', NaN, ...
        'Subject', "", ...
        'Condition', "", ...
        'Group', "", ...
        'Session', "", ...
        'Run', "", ...
        'DatasetFilename', "", ...
        'DatasetFilepath', "", ...
        'ResolvedSETPath', "", ...
        'SETExists', false, ...
        'SelectedICCount', 0, ...
        'SelectedICs', "");
end

function row = cluster_row_template_local()
    row = struct( ...
        'StudyPath', "", ...
        'StudyName', "", ...
        'ClusterIndex', NaN, ...
        'ClusterName', "", ...
        'MemberCount', 0, ...
        'SubjectCount', 0, ...
        'IsParentCluster', false, ...
        'IsOutlierCluster', false, ...
        'CentroidX', NaN, ...
        'CentroidY', NaN, ...
        'CentroidZ', NaN);
end

function row = cluster_member_row_template_local()
    row = struct( ...
        'StudyPath', "", ...
        'StudyName', "", ...
        'ClusterIndex', NaN, ...
        'ClusterName', "", ...
        'MemberIndex', NaN, ...
        'DatasetIndex', NaN, ...
        'Subject', "", ...
        'Condition', "", ...
        'Component', NaN);
end

function row = error_row_template_local()
    row = struct( ...
        'SourceType', "", ...
        'RelativePath', "", ...
        'FullPath', "", ...
        'Message', "");
end

function output = ternary_local(condition, trueValue, falseValue)
    if condition
        output = trueValue;
    else
        output = falseValue;
    end
end

function outputTable = struct_rows_to_table_local(rows, template)
    if isempty(rows)
        outputTable = struct2table(template, 'AsArray', true);
        outputTable(1, :) = [];
    else
        outputTable = struct2table(rows, 'AsArray', true);
    end
end

function yes = is_same_or_child_path_local(pathValue, parentValue)
    pathText = lower(char(pathValue));
    parentText = lower(char(parentValue));
    yes = strcmp(pathText, parentText) || ...
        startsWith(pathText, [parentText filesep]);
end

function relativePath = relative_path_local(fullPath, rootPath)
    fullText = char(fullPath);
    rootText = char(rootPath);
    if strcmpi(fullText, rootText)
        relativePath = ".";
        return;
    end
    prefix = [rootText filesep];
    if startsWith(lower(fullText), lower(prefix))
        relativePath = string(fullText(numel(prefix) + 1:end));
    else
        relativePath = string(fullText);
    end
end

function kind = classify_file_local(extension, isFolder)
    if isFolder
        kind = "folder";
        return;
    end
    ext = lower(string(extension));
    switch ext
        case ".set"
            kind = "EEGLAB_SET";
        case ".fdt"
            kind = "EEGLAB_FDT";
        case ".study"
            kind = "EEGLAB_STUDY";
        case ".fig"
            kind = "MATLAB_FIGURE";
        case ".mat"
            kind = "MATLAB_DATA";
        case {".csv", ".tsv", ".xlsx", ".xls"}
            kind = "TABLE";
        case {".png", ".jpg", ".jpeg", ".tif", ".tiff"}
            kind = "IMAGE";
        case {".txt", ".md", ".log"}
            kind = "TEXT";
        otherwise
            kind = "OTHER";
    end
end

function textValue = format_datenum_local(dateNumber)
    if isempty(dateNumber) || ~isfinite(dateNumber)
        textValue = "";
    else
        textValue = string(datetime(dateNumber, ...
            'ConvertFrom', 'datenum', ...
            'Format', 'yyyy-MM-dd HH:mm:ss'));
    end
end

function value = field_string_local(structure, fieldName)
    value = "";
    if ~isstruct(structure) || ~isfield(structure, fieldName)
        return;
    end
    raw = structure.(fieldName);
    if isempty(raw)
        return;
    end
    try
        if isnumeric(raw) || islogical(raw)
            value = numeric_list_local(raw(:)');
        elseif ischar(raw)
            value = string(raw);
        elseif isstring(raw)
            value = join(raw(:), ';');
        elseif iscell(raw)
            value = join(string(raw(:)), ';');
        else
            value = string(raw);
        end
    catch
        value = "<unprintable>";
    end
end

function value = field_double_local(structure, fieldName)
    value = NaN;
    if isstruct(structure) && isfield(structure, fieldName)
        raw = structure.(fieldName);
        if isnumeric(raw) && isscalar(raw)
            value = double(raw);
        end
    end
end

function vector = field_numeric_vector_local(structure, fieldName)
    vector = [];
    if isstruct(structure) && isfield(structure, fieldName)
        raw = structure.(fieldName);
        if isnumeric(raw)
            vector = double(raw(:)');
        elseif iscell(raw)
            try
                vector = double(cell2mat(raw(:)'));
            catch
                vector = [];
            end
        end
    end
end

function count = number_of_elements_local(structure, fieldName)
    count = 0;
    if isstruct(structure) && isfield(structure, fieldName) && ...
            ~isempty(structure.(fieldName))
        count = numel(structure.(fieldName));
    end
end

function names = struct_field_names_local(structure, fieldName)
    names = "";
    if ~isstruct(structure) || ~isfield(structure, fieldName) || ...
            ~isstruct(structure.(fieldName)) || ...
            isempty(structure.(fieldName))
        return;
    end
    names = join(string(fieldnames(structure.(fieldName))), ';');
end

function labels = event_field_values_local(events, fieldName)
    labels = strings(0, 1);
    if isempty(events) || ~isstruct(events) || ~isfield(events, fieldName)
        return;
    end
    labels = strings(numel(events), 1);
    keep = false(numel(events), 1);
    for eventIndex = 1:numel(events)
        raw = events(eventIndex).(fieldName);
        if isempty(raw)
            continue;
        end
        try
            if isnumeric(raw) || islogical(raw)
                labels(eventIndex) = numeric_list_local(raw(:)');
            elseif iscell(raw)
                labels(eventIndex) = join(string(raw(:)), ';');
            else
                labels(eventIndex) = string(raw);
            end
            keep(eventIndex) = strlength(strtrim(labels(eventIndex))) > 0;
        catch
            labels(eventIndex) = "<unprintable>";
            keep(eventIndex) = true;
        end
    end
    labels = labels(keep);
end

function rows = append_event_counts_local( ...
        rows, events, setPath, subject, fieldName)
    labels = event_field_values_local(events, fieldName);
    if isempty(labels)
        return;
    end
    [uniqueLabels, ~, labelGroup] = unique(labels, 'stable');
    counts = accumarray(labelGroup, 1);
    for labelIndex = 1:numel(uniqueLabels)
        row = event_row_template_local();
        row.SETPath = string(setPath);
        row.Subject = string(subject);
        row.Category = string(fieldName);
        row.Label = uniqueLabels(labelIndex);
        row.Count = counts(labelIndex);
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
end

function joined = join_unique_local(values)
    values = string(values(:));
    values = strtrim(values);
    values = values(~ismissing(values) & strlength(values) > 0);
    if isempty(values)
        joined = "";
    else
        joined = join(unique(values, 'stable'), ';');
    end
end

function values = unique_nonempty_local(values)
    values = string(values(:));
    values = strtrim(values);
    values = unique(values(~ismissing(values) & strlength(values) > 0));
end

function [hasICA, numberOfICs] = ica_info_local(EEG)
    hasICA = false;
    numberOfICs = 0;
    if isfield(EEG, 'icaweights') && ~isempty(EEG.icaweights)
        hasICA = true;
        numberOfICs = size(EEG.icaweights, 1);
    elseif isfield(EEG, 'icawinv') && ~isempty(EEG.icawinv)
        hasICA = true;
        numberOfICs = size(EEG.icawinv, 2);
    end
end

function [hasDIPFIT, modelCount, validCount] = dipfit_info_local(EEG)
    hasDIPFIT = false;
    modelCount = 0;
    validCount = 0;
    if ~isfield(EEG, 'dipfit') || isempty(EEG.dipfit)
        return;
    end
    hasDIPFIT = true;
    if ~isfield(EEG.dipfit, 'model') || isempty(EEG.dipfit.model)
        return;
    end
    models = EEG.dipfit.model;
    modelCount = numel(models);
    for modelIndex = 1:modelCount
        if isfield(models(modelIndex), 'posxyz') && ...
                isnumeric(models(modelIndex).posxyz) && ...
                ~isempty(models(modelIndex).posxyz) && ...
                size(models(modelIndex).posxyz, 2) == 3 && ...
                all(isfinite(models(modelIndex).posxyz(:)))
            validCount = validCount + 1;
        end
    end
end

function yes = has_iclabel_local(EEG)
    yes = isfield(EEG, 'etc') && isstruct(EEG.etc) && ...
        isfield(EEG.etc, 'ic_classification') && ...
        isstruct(EEG.etc.ic_classification) && ...
        isfield(EEG.etc.ic_classification, 'ICLabel');
end

function [hasSelection, yesCount, yesList] = ...
        manual_selection_info_local(EEG)
    hasSelection = false;
    yesCount = 0;
    yesList = "";
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || ...
            ~isfield(EEG.etc, 'manual_ic_selection')
        return;
    end
    hasSelection = true;
    selection = EEG.etc.manual_ic_selection;
    if isstruct(selection) && isfield(selection, 'yes_ic') && ...
            isnumeric(selection.yes_ic)
        yesICs = double(selection.yes_ic(:)');
        yesCount = numel(yesICs);
        yesList = numeric_list_local(yesICs);
    end
end

function [hasTimewarp, acceptedCount, latencyRows, warptoCount, ...
        timewarpFieldNames] = ...
        timewarp_info_local(EEG)
    hasTimewarp = false;
    acceptedCount = 0;
    latencyRows = 0;
    warptoCount = 0;
    timewarpFieldNames = "";
    if ~isfield(EEG, 'timewarp') || isempty(EEG.timewarp)
        return;
    end
    hasTimewarp = true;
    timewarp = EEG.timewarp;
    if isstruct(timewarp)
        timewarpFieldNames = join(string(fieldnames(timewarp)), ';');
    end
    if isstruct(timewarp) && isfield(timewarp, 'epochs')
        acceptedCount = numel(timewarp.epochs);
    end
    if isstruct(timewarp) && isfield(timewarp, 'latencies') && ...
            ~isempty(timewarp.latencies)
        latencyRows = size(timewarp.latencies, 1);
    end
    if isstruct(timewarp) && isfield(timewarp, 'warpto')
        warptoCount = numel(timewarp.warpto);
    end
end

function [dataPath, existsFlag] = external_data_info_local( ...
        EEG, setFolder, setPath)
    dataReference = "";
    if isfield(EEG, 'datfile') && ~isempty(EEG.datfile)
        dataReference = string(EEG.datfile);
    elseif isfield(EEG, 'data') && ...
            (ischar(EEG.data) || isstring(EEG.data))
        dataCandidate = string(EEG.data);
        candidateIsFDT = isscalar(dataCandidate) && ...
            endsWith(lower(dataCandidate), '.fdt');
        candidateExists = false;
        if isscalar(dataCandidate)
            candidateExists = isfile(fullfile( ...
                setFolder, char(dataCandidate)));
        end
        if candidateIsFDT || candidateExists
            dataReference = dataCandidate;
        end
    end

    if strlength(dataReference) == 0
        [~, stem] = fileparts(setPath);
        candidate = fullfile(setFolder, [stem '.fdt']);
        if isfile(candidate)
            dataReference = string(candidate);
        end
    end

    if strlength(dataReference) == 0
        dataPath = "";
        existsFlag = false;
        return;
    end

    if is_absolute_path_local(dataReference)
        dataPath = dataReference;
    else
        dataPath = string(fullfile(setFolder, char(dataReference)));
    end
    existsFlag = isfile(dataPath);
end

function yes = is_absolute_path_local(pathValue)
    pathText = char(pathValue);
    yes = ~isempty(regexp(pathText, '^[A-Za-z]:[\\/]', 'once')) || ...
        startsWith(pathText, '\\') || startsWith(pathText, '/');
end

function resolvedPath = resolve_study_set_path_local(info, studyFolder)
    filename = field_string_local(info, 'filename');
    filepath = field_string_local(info, 'filepath');
    if strlength(filename) == 0
        resolvedPath = "";
        return;
    end
    if is_absolute_path_local(filename)
        resolvedPath = filename;
        return;
    end
    if strlength(filepath) == 0
        resolvedPath = string(fullfile(studyFolder, char(filename)));
    elseif is_absolute_path_local(filepath)
        resolvedPath = string(fullfile(char(filepath), char(filename)));
    else
        resolvedPath = string(fullfile( ...
            studyFolder, char(filepath), char(filename)));
    end
end

function [hasClustering, roiText, roiClusterIndex] = ...
        study_bemobil_info_local(STUDY)
    hasClustering = false;
    roiText = "";
    roiClusterIndex = NaN;
    if ~isfield(STUDY, 'etc') || ~isstruct(STUDY.etc) || ...
            ~isfield(STUDY.etc, 'bemobil') || ...
            ~isstruct(STUDY.etc.bemobil) || ...
            ~isfield(STUDY.etc.bemobil, 'clustering')
        return;
    end
    clustering = STUDY.etc.bemobil.clustering;
    hasClustering = true;
    if isfield(clustering, 'cluster_ROI_MNI')
        roi = clustering.cluster_ROI_MNI;
        if isstruct(roi) && all(isfield(roi, {'x', 'y', 'z'}))
            roiText = numeric_list_local([roi.x roi.y roi.z]);
        elseif isnumeric(roi)
            roiText = numeric_list_local(roi(:)');
        end
    end
    if isfield(clustering, 'cluster_ROI_index') && ...
            isnumeric(clustering.cluster_ROI_index) && ...
            isscalar(clustering.cluster_ROI_index)
        roiClusterIndex = double(clustering.cluster_ROI_index);
    end
end

function [hasERSP, hasSpectrum, measureNames] = ...
        study_precompute_info_local(STUDY)
    hasERSP = false;
    hasSpectrum = false;
    measureNames = "";
    measures = strings(0, 1);

    if isfield(STUDY, 'measure') && ~isempty(STUDY.measure)
        measures = string(STUDY.measure(:));
    end

    if isfield(STUDY, 'etc') && isstruct(STUDY.etc)
        etcNames = string(fieldnames(STUDY.etc));
        measures = [measures; etcNames]; %#ok<AGROW>
    end

    measures = lower(measures);
    hasERSP = any(contains(measures, 'ersp'));
    hasSpectrum = any(contains(measures, 'spec'));
    measureNames = join_unique_local(measures);
end

function [setIndices, componentIndices] = ...
        cluster_membership_local(clusterInfo)
    setIndices = [];
    componentIndices = [];
    if ~isfield(clusterInfo, 'sets') || ...
            ~isfield(clusterInfo, 'comps')
        return;
    end
    sets = clusterInfo.sets;
    comps = clusterInfo.comps;

    if isnumeric(sets) && isnumeric(comps)
        setIndices = double(sets(:));
        componentIndices = double(comps(:));
        count = min(numel(setIndices), numel(componentIndices));
        setIndices = setIndices(1:count);
        componentIndices = componentIndices(1:count);
        return;
    end

    if iscell(sets) || iscell(comps)
        if ~iscell(sets)
            sets = num2cell(sets);
        end
        if ~iscell(comps)
            comps = num2cell(comps);
        end
        cellCount = min(numel(sets), numel(comps));
        for cellIndex = 1:cellCount
            setPart = numeric_from_any_local(sets{cellIndex});
            compPart = numeric_from_any_local(comps{cellIndex});
            if isempty(setPart) || isempty(compPart)
                continue;
            end
            if numel(setPart) == 1 && numel(compPart) > 1
                setPart = repmat(setPart, size(compPart));
            elseif numel(compPart) == 1 && numel(setPart) > 1
                compPart = repmat(compPart, size(setPart));
            end
            count = min(numel(setPart), numel(compPart));
            setIndices = [setIndices; setPart(1:count)]; %#ok<AGROW>
            componentIndices = [ ...
                componentIndices; compPart(1:count)]; %#ok<AGROW>
        end
    end
end

function values = numeric_from_any_local(raw)
    values = [];
    if isnumeric(raw)
        values = double(raw(:));
    elseif iscell(raw)
        try
            values = double(cell2mat(raw(:)));
        catch
            values = [];
        end
    end
end

function count = cluster_subject_count_local(STUDY, setIndices)
    subjects = strings(0, 1);
    for index = unique(setIndices(:)')
        if index >= 1 && index <= numel(STUDY.datasetinfo)
            subjects(end + 1, 1) = field_string_local( ...
                STUDY.datasetinfo(index), 'subject'); %#ok<AGROW>
        end
    end
    count = numel(unique_nonempty_local(subjects));
end

function [x, y, z] = cluster_centroid_local(clusterInfo)
    x = NaN;
    y = NaN;
    z = NaN;
    if ~isfield(clusterInfo, 'centroid') || ...
            ~isstruct(clusterInfo.centroid) || ...
            ~isfield(clusterInfo.centroid, 'dipoles')
        return;
    end
    dipoles = clusterInfo.centroid.dipoles;
    if isnumeric(dipoles) && numel(dipoles) >= 3
        xyzValues = double(dipoles);
        if size(xyzValues, 2) == 3
            xyz = mean(xyzValues, 1, 'omitnan');
        else
            xyz = xyzValues(1:3);
        end
        x = xyz(1);
        y = xyz(2);
        z = xyz(3);
    elseif isstruct(dipoles) && isfield(dipoles, 'posxyz')
        positions = nan(0, 3);
        for dipoleIndex = 1:numel(dipoles)
            position = dipoles(dipoleIndex).posxyz;
            if isnumeric(position) && ~isempty(position) && ...
                    size(position, 2) == 3
                positions = [positions; double(position)]; %#ok<AGROW>
            end
        end
        if ~isempty(positions)
            xyz = mean(positions, 1, 'omitnan');
            x = xyz(1);
            y = xyz(2);
            z = xyz(3);
        end
    end
end

function textValue = numeric_list_local(values)
    if isempty(values)
        textValue = "";
        return;
    end
    values = double(values(:)');
    parts = strings(size(values));
    for valueIndex = 1:numel(values)
        parts(valueIndex) = string(sprintf('%.12g', values(valueIndex)));
    end
    textValue = join(parts, ' ');
end

function textValue = clean_message_local(message)
    textValue = string(message);
    textValue = replace(textValue, newline, ' | ');
    textValue = replace(textValue, char(13), ' ');
    textValue = strtrim(textValue);
end

function write_report_local( ...
        reportPath, outputRoot, auditStarted, auditFinished, ...
        fileInventory, setInventory, studyInventory, ...
        studyReferences, clusterInventory, auditErrors)
    fileID = fopen(reportPath, 'w');
    assert(fileID ~= -1, 'Could not create report: %s', reportPath);
    cleanupObject = onCleanup(@() fclose(fileID)); %#ok<NASGU>

    fprintf(fileID, 'HipExo output audit report\n');
    fprintf(fileID, '==========================\n\n');
    fprintf(fileID, 'Output root: %s\n', outputRoot);
    fprintf(fileID, 'Started: %s\n', char(auditStarted));
    fprintf(fileID, 'Finished: %s\n', char(auditFinished));
    fprintf(fileID, 'Existing outputs modified: no\n\n');

    fprintf(fileID, 'Filesystem summary\n');
    fprintf(fileID, '------------------\n');
    fprintf(fileID, 'Items: %d\n', height(fileInventory));
    fprintf(fileID, 'Files: %d\n', sum(fileInventory.ItemType == "file"));
    fprintf(fileID, 'Folders: %d\n', sum(fileInventory.ItemType == "folder"));
    fprintf(fileID, 'SET files: %d\n', height(setInventory));
    fprintf(fileID, 'STUDY files: %d\n\n', height(studyInventory));

    fprintf(fileID, 'EEGLAB SET summary\n');
    fprintf(fileID, '------------------\n');
    for rowIndex = 1:height(setInventory)
        row = setInventory(rowIndex, :);
        fprintf(fileID, '[%s] %s\n', ...
            char(row.LoadStatus), char(row.RelativePath));
        if row.LoadStatus == "OK"
            fprintf(fileID, ...
                '  subject=%s | condition=%s | %s | channels=%g | trials=%g | srate=%g\n', ...
                char(row.Subject), char(row.Condition), ...
                char(row.DataKind), row.NbChan, row.Trials, row.SRate);
            fprintf(fileID, ...
                '  ICA=%d (%g ICs) | DIPFIT=%d (%g valid) | manual Yes=%g\n', ...
                row.HasICA, row.ICAComponentCount, ...
                row.HasDIPFIT, row.ValidDipoleCount, ...
                row.ManualYesICCount);
            fprintf(fileID, ...
                '  RHS/LTO/LHS/RTO=%g/%g/%g/%g | timewarp=%d | external data exists=%d\n', ...
                row.RHSCount, row.LTOCount, row.LHSCount, row.RTOCount, ...
                row.HasTimewarp, row.ExternalDataExists);
        else
            fprintf(fileID, '  ERROR: %s\n', char(row.LoadError));
        end
    end

    fprintf(fileID, '\nEEGLAB STUDY summary\n');
    fprintf(fileID, '--------------------\n');
    for rowIndex = 1:height(studyInventory)
        row = studyInventory(rowIndex, :);
        fprintf(fileID, '[%s] %s\n', ...
            char(row.LoadStatus), char(row.RelativePath));
        if row.LoadStatus == "OK"
            fprintf(fileID, ...
                '  name=%s | datasets=%g | subjects=%g | designs=%g | clusters=%g\n', ...
                char(row.StudyName), row.DatasetCount, row.SubjectCount, ...
                row.DesignCount, row.ClusterCount);
            fprintf(fileID, ...
                '  subjects=%s | conditions=%s | missing SET references=%g\n', ...
                char(row.Subjects), char(row.Conditions), ...
                row.MissingDatasetReferenceCount);
            fprintf(fileID, ...
                '  ERSP precompute marker=%d | spectrum precompute marker=%d\n', ...
                row.HasERSPPrecompute, row.HasSpectrumPrecompute);
        else
            fprintf(fileID, '  ERROR: %s\n', char(row.LoadError));
        end
    end

    fprintf(fileID, '\nPipeline-relevant checks\n');
    fprintf(fileID, '------------------------\n');
    continuousCandidates = setInventory( ...
        setInventory.LoadStatus == "OK" & ...
        setInventory.DataKind == "continuous" & ...
        setInventory.HasManualICSelection & ...
        setInventory.ManualYesICCount > 0 & ...
        setInventory.HasCompleteGaitEventSet, :);
    fprintf(fileID, ...
        'Continuous manual-Yes datasets with all gait event types: %d\n', ...
        height(continuousCandidates));
    for rowIndex = 1:height(continuousCandidates)
        fprintf(fileID, '  %s | Yes ICs=%g\n', ...
            char(continuousCandidates.RelativePath(rowIndex)), ...
            continuousCandidates.ManualYesICCount(rowIndex));
    end

    warpedDatasets = setInventory( ...
        setInventory.LoadStatus == "OK" & ...
        setInventory.DataKind == "epoched" & ...
        setInventory.HasTimewarp, :);
    fprintf(fileID, 'Epoched datasets containing EEG.timewarp: %d\n', ...
        height(warpedDatasets));
    for rowIndex = 1:height(warpedDatasets)
        fprintf(fileID, '  %s | epochs=%g | accepted timewarp epochs=%g\n', ...
            char(warpedDatasets.RelativePath(rowIndex)), ...
            warpedDatasets.Trials(rowIndex), ...
            warpedDatasets.TimewarpAcceptedEpochCount(rowIndex));
    end

    missingFDT = setInventory( ...
        setInventory.LoadStatus == "OK" & ...
        strlength(setInventory.ExternalDataFile) > 0 & ...
        ~setInventory.ExternalDataExists, :);
    fprintf(fileID, 'SET files with missing external data reference: %d\n', ...
        height(missingFDT));
    for rowIndex = 1:height(missingFDT)
        fprintf(fileID, '  %s -> %s\n', ...
            char(missingFDT.RelativePath(rowIndex)), ...
            char(missingFDT.ExternalDataFile(rowIndex)));
    end

    missingStudySets = studyReferences(~studyReferences.SETExists, :);
    fprintf(fileID, 'Missing STUDY dataset references: %d\n', ...
        height(missingStudySets));
    for rowIndex = 1:height(missingStudySets)
        fprintf(fileID, '  %s -> %s\n', ...
            char(missingStudySets.StudyName(rowIndex)), ...
            char(missingStudySets.ResolvedSETPath(rowIndex)));
    end

    fprintf(fileID, 'Cluster records found: %d\n', ...
        height(clusterInventory));
    fprintf(fileID, 'Read errors: %d\n', height(auditErrors));
    for rowIndex = 1:height(auditErrors)
        fprintf(fileID, '  [%s] %s: %s\n', ...
            char(auditErrors.SourceType(rowIndex)), ...
            char(auditErrors.RelativePath(rowIndex)), ...
            char(auditErrors.Message(rowIndex)));
    end

    fprintf(fileID, '\nNext action\n');
    fprintf(fileID, '-----------\n');
    fprintf(fileID, ...
        ['Upload output_audit_bundle.zip. The audit will be used to choose ' ...
         'the exact Subject 1 and Subject 3 input SET files before writing ' ...
         'the RHS epoching and timewarp script.\n']);
end

function create_zip_bundle_local(auditFolder, bundleNames, bundlePath)
    originalFolder = pwd;
    cleanupObject = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
    cd(auditFolder);
    [~, bundleStem, bundleExtension] = fileparts(bundlePath);
    localBundleName = [bundleStem bundleExtension];
    if isfile(localBundleName)
        delete(localBundleName);
    end
    zip(localBundleName, bundleNames);
end
