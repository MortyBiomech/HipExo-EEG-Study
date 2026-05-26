function events = detect_gait_events_pitch_acc(t, q, acc)
% Detect HS/TO using pitch (from quaternion) + accelerometer magnitude.
% Quaternion order: [w x y z]
%
% Inputs:
%   t   Nx1 timestamps (s) from LSL
%   q   Nx4 quaternion [w x y z]
%   acc Nx3 accelerometer (sensor frame)
%
% Outputs:
%   events.HS, events.TO : sample indices
%   events.pitch         : filtered pitch (rad)
%   events.acc_mag       : filtered accel magnitude
%   events.Fs            : estimated Fs

    % --- sort & clean time ---
    t = double(t(:));
    [t, idx] = sort(t, 'ascend');
    q   = double(q(idx,:));
    acc = double(acc(idx,:));

    good = [true; diff(t) > 0];
    t = t(good); q = q(good,:); acc = acc(good,:);

    Fs = 1/median(diff(t));
    nyq = Fs/2;

    % --- quaternion continuity & normalize ---
    q = normalize_quat(q);
    q = enforce_quat_continuity(q);

    % --- pitch from quaternion (ZYX) ---
    w = q(:,1); x = q(:,2); y = q(:,3); z = q(:,4);
    sinp = 2*(w.*y - z.*x);
    sinp = max(-1, min(1, sinp));
    pitch = asin(sinp);

    % --- filter pitch (gait content) ---
    fcutPitch = min(6, 0.6*nyq);
    pitch_f = lowpass1(pitch, fcutPitch, Fs);
    pitch_rate = gradient(pitch_f) * Fs;

    % --- accel magnitude (contact cue) ---
    acc_mag = sqrt(sum(acc.^2,2));
    fcutAcc = min(12, 0.85*nyq);
    acc_f = lowpass1(acc_mag, fcutAcc, Fs);

    % ---------------------------------------------------------
    % 1) Find stride markers from pitch maxima (stable on treadmill)
    % ---------------------------------------------------------
    minStride = round(0.5*Fs);  % ~2 Hz max cadence; adjust if needed
    [pks, locMax] = findpeaks(pitch_f, 'MinPeakDistance', minStride);

    % If your pitch maxima are not the dominant peaks, invert:
    if numel(locMax) < 3
        [~, locMax] = findpeaks(-pitch_f, 'MinPeakDistance', minStride);
    end

    % ---------------------------------------------------------
    % 2) For each stride (max_i -> max_{i+1}), find TO and HS
    % ---------------------------------------------------------
    HS = [];
    TO = [];

    for i = 1:numel(locMax)-1
        iA = locMax(i);
        iB = locMax(i+1);

        seg = iA:iB;

        % ---- TO candidate: pitch minimum within the stride window
        [~, kMin] = min(pitch_f(seg));
        to = seg(1) + kMin - 1;

        % Alternative TO: point of maximum pitch_rate after the minimum (optional)
        % Search 0–30% of stride after minimum:
        % w1 = to;
        % w2 = min(iB, to + round(0.3*(iB-iA)));
        % [~, k] = max(pitch_rate(w1:w2));
        % to = w1 + k - 1;

        % ---- HS candidate: accel peak near end of swing
        % Define HS search window relative to stride:
        % Late part before the next pitch max (typical end of swing)
        wHS1 = max(iA, iB - round(0.35*(iB-iA))); % last 35% of stride
        wHS2 = iB;

        [~, kHS] = max(acc_f(wHS1:wHS2));
        hs = wHS1 + kHS - 1;

        % Sanity: enforce ordering inside stride
        if to < hs && hs < iB
            TO(end+1,1) = to;
            HS(end+1,1) = hs;
        else
            % Fallback: if ordering fails, try HS as max |pitch_rate| near iB
            w1 = max(iA, iB - round(0.25*(iB-iA)));
            w2 = iB;
            [~, k2] = max(abs(pitch_rate(w1:w2)));
            hs2 = w1 + k2 - 1;

            TO(end+1,1) = to;
            HS(end+1,1) = hs2;
        end
    end

    events.HS = HS;
    events.TO = TO;
    events.pitch = pitch_f;
    events.pitch_rate = pitch_rate;
    events.acc_mag = acc_f;
    events.Fs = Fs;
end

% ---- helpers ----
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
