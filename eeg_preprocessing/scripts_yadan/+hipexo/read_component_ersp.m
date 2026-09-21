function R = read_component_ersp( ...
        STUDY, subject, ic, conditionNames, timerange, freqrange, ...
        baseline, basenorm, trialbase)
% Read one retained IC from the cached complex TF decomposition and return
% only condition-level ERSPs. No physical-run export is generated.

infoIndices = find(string({STUDY.datasetinfo.subject}) == string(subject));
assert(~isempty(infoIndices), 'Subject has no STUDY datasets.');

fileBase = hipexo.tf_cache_file_base(STUDY, infoIndices(1));

for index = infoIndices(:)'
    assert(strcmp(fileBase, hipexo.tf_cache_file_base(STUDY, index)), ...
        'One retained subject spans multiple ICA sessions.');
end

[raw, params, times, freqs, ~, trialInfo] = std_readfile( ...
    [fileBase '.icatimef'], ...
    'components', ic, ...
    'singletrials', 'on', ...
    'freqlimits', freqrange);

assert(iscell(raw) && numel(raw) == 1 && ~isempty(raw{1}), ...
    'Expected one component TF array.');

trials = trialInfo{1};

assert(isfield(trials, 'index') && ...
    numel(trials) == size(raw{1}, 3), ...
    'TF trial metadata do not match the TF trials.');

indices = double([trials.index]);

params.baseline = baseline;
params.basenorm = basenorm;
params.trialbase = trialbase;
params.verbose = 'off';

power = raw{1} .* conj(raw{1});
clear raw

conditionNames = string(conditionNames(:));
trialConditions = strings(size(indices));

for index = infoIndices(:)'
    trialConditions(indices == STUDY.datasetinfo(index).index) = ...
        string(STUDY.datasetinfo(index).condition);
end

conditionPower = cell(numel(conditionNames), 1);

% trialbase='full' must use the full cached TF epoch, as in newtimef.
% Crop to the displayed gait cycle only after single-trial normalization.
fullTimes = times;
timeMask = fullTimes >= timerange(1) & fullTimes <= timerange(2);
assert(any(timeMask), 'No TF samples fall inside the requested gait-cycle range.');
times = fullTimes(timeMask);

for c = 1:numel(conditionNames)

    mask = trialConditions == conditionNames(c);

    if any(mask)
        normalized = newtimeftrialbaseln( ...
            power(:, :, mask), ...
            fullTimes, ...
            params);

        normalized = normalized(:, timeMask, :);
        conditionPower{c} = double(mean(normalized, 3));
    end
end

available = ~cellfun(@isempty, conditionPower);
assert(any(available), ...
    'No retained trials match the condition design.');

params.singletrials = 'off';
params.commonbase = 'on';

corrected = newtimefbaseln( ...
    conditionPower(available), ...
    times, ...
    params);

R.conditionERSP = cell(numel(conditionNames), 1);
R.conditionERSP(available) = cellfun( ...
    @(x) 10 .* log10(double(x)), ...
    corrected, ...
    'UniformOutput', false);

R.times = double(times(:)');
R.freqs = double(freqs(:)');
R.conditionNames = conditionNames;
end
