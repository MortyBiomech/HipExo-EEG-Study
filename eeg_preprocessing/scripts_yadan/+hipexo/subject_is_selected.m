function mask = subject_is_selected(values)
% Optional processing scope; it never declares an existing result current.
selected = config_processing_scope();
mask = true(size(values));
if isempty(selected), return; end
requested = str2double(regexprep(lower(string(selected(:))), '^sub-', ''));
assert(all(isfinite(requested) & requested >= 1 & requested == round(requested)), ...
    'Processing subjects must be positive subject numbers.');
actual = str2double(regexprep(lower(string(values)), '^sub-', ''));
mask = ismember(actual, requested);
end
