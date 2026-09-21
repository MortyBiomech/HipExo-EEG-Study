function [members, uniqueMembers] = cluster_membership(STUDY, clusterIndex)
% GOAL
%   Resolve cluster members and count shared ICA components once.
% INPUT
%   An EEGLAB STUDY and a cluster index.
% APPROACH
%   Expand sets/comps to dataset-IC pairs and resolve subject/session/run.
% OUTPUT
%   members: one row per dataset-IC pair.
%   uniqueMembers: one row per subject/session/IC, in stable order.
% USED BY
%   ROI clustering, review and ERSP input selection.

cluster = STUDY.cluster(clusterIndex);
sets = double(cluster.sets);
comps = double(cluster.comps);
if isvector(comps) && size(sets, 2) == numel(comps)
    comps = comps(:)';
    valid = isfinite(sets) & sets > 0;
    [~, columns] = find(valid);
    pairs = [sets(valid), reshape(comps(columns), [], 1)];
elseif numel(sets) == numel(comps)
    pairs = [sets(:), comps(:)];
    valid = all(isfinite(pairs) & pairs > 0, 2);
    pairs = pairs(valid, :);
else
    error('Unsupported cluster sets/comps shape: %s / %s.', ...
        mat2str(size(sets)), mat2str(size(comps)));
end
assert(all(isfinite(pairs(:))) && all(pairs(:) > 0) && ...
    all(pairs(:) == round(pairs(:))), ...
    'Cluster dataset and component indices must be positive integers.');
pairs = unique(pairs, 'rows', 'stable');

DatasetIndex = pairs(:, 1);
IC = pairs(:, 2);
n = size(pairs, 1);
Subject = strings(n, 1);
ICASession = nan(n, 1);
PhysicalRun = nan(n, 1);
Condition = strings(n, 1);
infoIndices = double([STUDY.datasetinfo.index]);
assert(numel(unique(infoIndices)) == numel(infoIndices), ...
    'STUDY dataset indices must be unique.');
for k = 1:n
    infoIndex = find(infoIndices == DatasetIndex(k), 1);
    assert(~isempty(infoIndex), 'Unknown dataset index %d.', DatasetIndex(k));
    info = STUDY.datasetinfo(infoIndex);
    Subject(k) = string(info.subject);
    ICASession(k) = double(info.session);
    Condition(k) = string(info.condition);
    if isfield(info, 'run') && ~isempty(info.run)
        PhysicalRun(k) = double(info.run);
    end
end
ICAUnit = Subject + "|session" + string(ICASession);
ICAComponentUnit = ICAUnit + "|IC" + string(IC);
members = table(DatasetIndex, Subject, ICASession, PhysicalRun, ...
    Condition, IC, ICAUnit, ICAComponentUnit);
members = sortrows(members, ...
    {'Subject', 'ICASession', 'PhysicalRun', 'Condition', 'IC'});
[~, firstRows] = unique(members.ICAComponentUnit, 'stable');
uniqueMembers = members(firstRows, :);
end
