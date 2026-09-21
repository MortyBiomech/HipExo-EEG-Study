function signature = roi_review_identity(STUDY, ALLEEG, clusterIndex, roi, qcSettings)
% GOAL
%   Bind manual ROI review to its definition and actual source components.
% INPUT
%   A ROI STUDY, dataset headers, selected cluster and one config ROI row.
% APPROACH
%   Verify the ROI definition and hash member ICA, dipole and scalp identities.
% OUTPUT
%   A review identity independent of STUDY filenames and member ordering.
% USED BY
%   Step 13 review preservation and Step 14 review confirmation.

assert(height(roi) == 1 && isfield(STUDY, 'etc') && ...
    isfield(STUDY.etc, 'rhs_roi_clustering'), ...
    'ROI review requires one definition and ROI STUDY metadata.');
metadata = STUDY.etc.rhs_roi_clustering;
xyz = double([roi.MNI_X, roi.MNI_Y, roi.MNI_Z]);
assert(string(metadata.roi_id) == string(roi.ROIID) && ...
    string(metadata.roi_name) == string(roi.ROIName) && ...
    string(metadata.original_exploratory_cluster_id) == ...
        string(roi.OriginalClusterID) && ...
    numel(metadata.roi_mni) == 3 && ...
    max(abs(double(metadata.roi_mni(:)') - xyz)) < 1e-9 && ...
    double(metadata.selected_cluster) == clusterIndex, ...
    'ROI definition or selected cluster changed. Run Steps 12 and 13.');

members = hipexo.cluster_membership(STUDY, clusterIndex);
assert(~isempty(members), 'The selected ROI cluster contains no members.');
datasetIndices = unique(members.DatasetIndex, 'stable');
identities = strings(numel(datasetIndices), 1);
for k = 1:numel(datasetIndices)
    d = datasetIndices(k);
    assert(d <= numel(ALLEEG), 'ROI member refers to missing EEG header %d.', d);
    identities(k) = hipexo.ica_identity_signature(ALLEEG(d));
end
[~, locations] = ismember(members.DatasetIndex, datasetIndices);
memberICA = identities(locations);
units = unique(members.ICAUnit, 'stable');
for k = 1:numel(units)
    assert(numel(unique(memberICA(members.ICAUnit == units(k)))) == 1, ...
        'Runs in %s contain different ICA decompositions.', char(units(k)));
end

evidence = strings(height(members), 1);
for k = 1:height(members)
    EEG = ALLEEG(members.DatasetIndex(k));
    ic = members.IC(k);
    assert(ic <= size(EEG.icawinv, 2) && ...
        isfield(EEG, 'dipfit') && isfield(EEG.dipfit, 'model') && ...
        ic <= numel(EEG.dipfit.model), ...
        'ROI member IC %d lacks its scalp map or dipole model.', ic);
    detail.dipole = EEG.dipfit.model(ic);
    detail.scalp_map = double(EEG.icawinv(:, ic));
    evidence(k) = hipexo.review_content_signature(detail);
end
S.study_subjects = sort(unique(string({STUDY.datasetinfo.subject})));
S.qc_definition = struct( ...
    'minimumSubjectCoverageFraction', qcSettings.minimumSubjectCoverageFraction, ...
    'frequencyRangeHz', qcSettings.frequencyRangeHz);
S.input_processing = strings(numel(datasetIndices), 1);
for k = 1:numel(datasetIndices)
    d = datasetIndices(k);
    assert(isfield(ALLEEG(d).etc, 'rhs_epoching') && ...
        isfield(ALLEEG(d).etc.rhs_epoching, 'processing_signature'), ...
        'ROI review requires current epoch processing provenance.');
    S.input_processing(k) = string(ALLEEG(d).etc.rhs_epoching.processing_signature);
end
S.input_processing = sort(unique(S.input_processing));
S.roi = struct('id', string(roi.ROIID), 'name', string(roi.ROIName), ...
    'original_cluster', string(roi.OriginalClusterID), 'mni', xyz);
S.members = sortrows(unique(table(members.ICAComponentUnit, memberICA, ...
    evidence, 'VariableNames', {'Component', 'ICAIdentity', 'Evidence'}), ...
    'rows'), {'Component', 'ICAIdentity', 'Evidence'});
signature = hipexo.review_content_signature(S);
end
