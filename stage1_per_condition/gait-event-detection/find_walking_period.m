function [t_start, t_end] = find_walking_period(GRF_R, GRF_L, fs, varargin)
% Detects walking period by finding when GRF starts/stops oscillating.

    p = inputParser;
    addParameter(p, 'WindowDur',  2.0);    % seconds per variance window
    addParameter(p, 'Threshold',  0.10);   % variance threshold (fraction of max variance)
    parse(p, varargin{:});
    opt = p.Results;

    win     = round(opt.WindowDur * fs);
    GRF_sum = GRF_R + GRF_L;              % use total GRF for robustness
    n_wins  = floor(numel(GRF_sum) / win);

    var_profile = zeros(n_wins, 1);
    for k = 1:n_wins
        seg            = GRF_sum((k-1)*win+1 : k*win);
        var_profile(k) = var(seg);
    end

    % Normalise and threshold
    var_norm    = var_profile / max(var_profile);
    is_walking  = var_norm > opt.Threshold;

    % First and last walking window
    first_win = find(is_walking, 1, 'first');
    last_win  = find(is_walking, 1, 'last');

    t_start = (first_win - 1) * opt.WindowDur;
    t_end   =  last_win       * opt.WindowDur;

    fprintf('\n  Walking period detected: %.1f s → %.1f s (%.1f s duration)\n', ...
        t_start, t_end, t_end - t_start);
end