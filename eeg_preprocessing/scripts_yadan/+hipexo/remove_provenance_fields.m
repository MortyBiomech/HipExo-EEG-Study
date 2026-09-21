function value = remove_provenance_fields(value)
% Remove descriptive bookkeeping from scientific metadata before hashing.
if istable(value), value = table2struct(value); end
if isstruct(value)
    names = fieldnames(value);
    descriptive = {'version','processingVersion','created_on','created_at', ...
        'createdOn','updated_on','processing_date','history','filename','filepath', ...
        'source_set_signature','event_source_set_signature','processing_signature', ...
        'source_xdf_signature','source_grf_signature','source_event_signature', ...
        'source_bids_eeg_set_signature','recommended_cycle_table_signature', ...
        'eeg_segment_code_signature'};
    drop = names(ismember(names, descriptive));
    if ~isempty(drop), value = rmfield(value, drop); end
    names = fieldnames(value);
    for k = 1:numel(value)
        for n = 1:numel(names)
            value(k).(names{n}) = hipexo.remove_provenance_fields(value(k).(names{n}));
        end
    end
elseif iscell(value)
    for k = 1:numel(value), value{k} = hipexo.remove_provenance_fields(value{k}); end
end
end
