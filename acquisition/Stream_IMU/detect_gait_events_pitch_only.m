function events = detect_gait_events_pitch_only(t, q)
%DETECT_GAIT_EVENTS_PITCH_ONLY Pitch-only gait event proxies from dorsum-foot IMU.
%
% Inputs:
%   t : Nx1 LSL timestamps (s)
%   q : Nx4 quaternion [w x y z]
%
% Outputs:
%   events.HS : indices (pitch maxima)  -> HS proxy
%   events.TO : indices (pitch minima)  -> TO proxy
%   events.pitch : filtered pitch (rad)
%   events.pitch_rate : pitch derivative (rad/s)
%   events.Fs : estimated sampling rate
%
% Notes:
% - Uses pitch extrema as consistent within-cycle landmarks.
% - Optional refinement: move event to nearest zero-crossing of pitch_rate.

    % --- sort & clean time ---
    t = double(t(:));
    [t, idx] = sort(t, 'ascend');
    q = double(q(idx,:));
    good = [true; diff(t) > 0];
    t = t(good);
    q = q(good,:);

    Fs = 1 / median(diff(t));
    nyq = Fs/2;

    % --- quaternion normalize + sign continuity ---
    q = normalize_quat(q);
    q = enforce_quat_continuity(q);

    % --- pitch from quaternion (ZYX) ---
    w = q(:,1); x = q(:,2); y = q(:,3); z = q(:,4);
    sinp = 2*(w.*y - z.*x);
    sinp = max(-1, min(1, sinp));
    pitch = asin(sinp);

    % --- filter pitch (gait) ---
    fcutPitch = min(6, 0.60*nyq);        % safe under Nyquist (~18.8 at Fs~37.6)
    pitch_f = lowpass1(pitch, fcutPitch, Fs);

    % Pitch rate (for optional refinement)
    pitch_rate = gradient(pitch_f) * Fs;

    % --- stride-scale constraints ---
    % MinPeakDistance: set from expected cadence. For treadmill walking:
    % stride time usually ~0.8–1.4 s => distance ~0.8*Fs to 1.4*Fs
    % Choose conservative: 0.6 s
    minDist = max(1, round(0.6 * Fs));

    % -------------------------------------------------------
    % 1) Find maxima and minima of pitch (one per stride)
    % -------------------------------------------------------
    [~, HS_raw] = findpeaks(pitch_f,  'MinPeakDistance', minDist);   % maxima
    [~, TO_raw] = findpeaks(-pitch_f, 'MinPeakDistance', minDist);   % minima

    % -------------------------------------------------------
    % 2) Pair events into cycles (TO -> HS -> next TO)
    % -------------------------------------------------------
    % We enforce: TO(i) < HS(i) < TO(i+1)
    HS = [];
    TO = [];

    TO_raw = sort(TO_raw(:));
    HS_raw = sort(HS_raw(:));

    iTO = 1;
    while iTO < numel(TO_raw)
        to1 = TO_raw(iTO);
        to2 = TO_raw(iTO+1);

        % HS between consecutive minima
        hsCand = HS_raw(HS_raw > to1 & HS_raw < to2);
        if isempty(hsCand)
            iTO = iTO + 1;
            continue;
        end

        % If multiple maxima, choose the highest pitch (true maximum)
        [~, k] = max(pitch_f(hsCand));
        hs = hsCand(k);

        TO(end+1,1) = to1;
        HS(end+1,1) = hs;

        iTO = iTO + 1;
    end

    % -------------------------------------------------------
    % 3) Optional refinement using pitch_rate zero-crossing
    % -------------------------------------------------------
    % Maxima occur where pitch_rate crosses + to - (down-crossing)
    % Minima occur where pitch_rate crosses - to + (up-crossing)
    win = max(1, round(0.08 * Fs));  % +/- 80 ms window

    HS_ref = HS;
    for i = 1:numel(HS)
        c = HS(i);
        i1 = max(2, c - win); i2 = min(numel(pitch_rate)-1, c + win);
        % Find index where pitch_rate changes sign from + to -
        idx = find(pitch_rate(i1:i2-1) > 0 & pitch_rate(i1+1:i2) <= 0, 1, 'last');
        if ~isempty(idx)
            HS_ref(i) = i1 + idx - 1;
        end
    end

    TO_ref = TO;
    for i = 1:numel(TO)
        c = TO(i);
        i1 = max(2, c - win); i2 = min(numel(pitch_rate)-1, c + win);
        % Find index where pitch_rate changes sign from - to +
        idx = find(pitch_rate(i1:i2-1) < 0 & pitch_rate(i1+1:i2) >= 0, 1, 'last');
        if ~isempty(idx)
            TO_ref(i) = i1 + idx - 1;
        end
    end

    events.HS = HS_ref(:);
    events.TO = TO_ref(:);
    events.pitch = pitch_f(:);
    events.pitch_rate = pitch_rate(:);
    events.Fs = Fs;
end

% -------- helpers --------
function qn = normalize_quat(q)
    n = sqrt(sum(q.^2, 2));
    n(n==0) = 1;
    qn = q ./ n;
end

function qc = enforce_quat_continuity(q)
    qc = q;
    for i=2:size(q,1)
        if dot(qc(i,:), qc(i-1,:)) < 0
            qc(i,:) = -qc(i,:);
        end
    end
end

function y = lowpass1(x, fcut, Fs)
    if fcut >= Fs/2, y = x; return; end
    [b,a] = butter(4, fcut/(Fs/2), 'low');
    y = filtfilt(b,a, x);
end
