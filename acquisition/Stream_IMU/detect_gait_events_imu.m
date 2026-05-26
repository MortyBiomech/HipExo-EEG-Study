function events = detect_gait_events_imu(t, q, gyro, acc)
%DETECT_GAIT_EVENTS_IMU Detect Heel-Strike (HS) and Toe-Off (TO) from foot IMU.
%
% Uses LSL timestamps to compute the *true* sampling rate (Fs), assumes near-uniform
% sampling (as in your dt plot), and avoids resampling.
%
% INPUTS:
%   t     : Nx1 timestamps (seconds, from LSL)
%   q     : Nx4 quaternion [w x y z]
%   gyro  : Nx3 gyroscope [gx gy gz] (rad/s or deg/s; just be consistent)
%   acc   : Nx3 accelerometer [ax ay az] (optional; pass [] if not available)
%
% OUTPUT (struct):
%   events.HS              sample indices of heel strikes
%   events.TO              sample indices of toe offs
%   events.stance          Nx1 logical stance mask (true=stance)
%   events.Fs              estimated sampling rate from timestamps
%   events.threshold_omega stance threshold used on |omega|
%   events.omega_mag_f     filtered gyro magnitude
%   events.pitch           filtered pitch angle (rad)
%   events.pitch_rate      pitch rate (rad/s)
%
% METHOD:
%   1) estimate Fs = 1/median(diff(t))
%   2) stance/swing via low-passed gyro magnitude threshold (median + k*MAD)
%   3) HS = stance start (swing->stance), refined using accel magnitude peak (if acc given)
%      otherwise refined using max |pitch_rate|
%   4) TO = stance end (stance->swing), refined using max |pitch_rate|
%
% IMPORTANT:
%   - At ~38 Hz, Nyquist is ~19 Hz; cutoffs are chosen accordingly.

    if nargin < 4
        acc = [];
    end

    % -----------------------------
    % 0) Sort by time, remove non-increasing timestamps
    % -----------------------------
    t = double(t(:));
    [t, idx] = sort(t, 'ascend');

    q    = double(q(idx,:));
    gyro = double(gyro(idx,:));
    if ~isempty(acc)
        acc = double(acc(idx,:));
        acc = acc(idx,:);
    end

    dt = diff(t);
    good = [true; dt > 0];
    t = t(good);
    q = q(good,:);
    gyro = gyro(good,:);
    if ~isempty(acc), acc = acc(good,:); end

    N = size(q,1);
    assert(size(q,2)==4, 'q must be Nx4 [w x y z].');
    assert(all(size(gyro)==[N,3]), 'gyro must be Nx3 and match q length.');
    if ~isempty(acc)
        assert(all(size(acc)==[N,3]), 'acc must be Nx3 and match q length.');
    end

    % -----------------------------
    % 1) Sampling rate from timestamps
    % -----------------------------
    Fs = 1 / median(diff(t));

    % -----------------------------
    % 2) Parameters (adaptive to Fs)
    % -----------------------------
    nyq = Fs/2;
    params.fcutGyro     = min(12, 0.85*nyq);  % Hz
    params.fcutPitch    = min(6,  0.60*nyq);  % Hz
    params.fcutAccMag   = min(12, 0.85*nyq);  % Hz (if used)
    params.kMad         = 1.5;                % omega threshold = median + k*MAD

    params.minStepTime  = 0.35;               % s
    params.minStanceDur = 0.10;               % s (debounce)
    params.minSwingDur  = 0.10;               % s (debounce)
    params.edgeWindowHS = 0.08;               % s (refine window around stance start)
    params.edgeWindowTO = 0.08;               % s (refine window around stance end)
    params.useAccForHS  = ~isempty(acc);

    % -----------------------------
    % 3) Normalize + sign-continuous quaternion
    % -----------------------------
    q = normalize_quat(q);
    q = enforce_quat_continuity(q);

    % -----------------------------
    % 4) Compute pitch from quaternion (ZYX convention)
    % pitch = asin(2*(w*y - z*x))
    % -----------------------------
    w = q(:,1); x = q(:,2); y = q(:,3); z = q(:,4);
    sinp = 2*(w.*y - z.*x);
    sinp = max(-1, min(1, sinp));
    pitch = asin(sinp);               % rad
    pitch_f = lowpass1(pitch, params.fcutPitch, Fs);
    pitch_rate = gradient(pitch_f) * Fs;   % rad/s

    % -----------------------------
    % 5) Stance/swing from gyro magnitude
    % -----------------------------
    omega_mag = sqrt(sum(gyro.^2, 2));
    omega_f = lowpass1(omega_mag, params.fcutGyro, Fs);

    medO = median(omega_f);
    madO = mad(omega_f, 1);                 % robust spread (raw MAD)
    Th = medO + params.kMad * madO;

    stance_raw = omega_f < Th;

    % Debounce: remove short stance fragments and fill short gaps
    stance = clean_binary_segments(stance_raw, Fs, params.minStanceDur, params.minSwingDur);

    % Stance runs
    [stanceStarts, stanceEnds] = binary_runs(stance);

    % Edge candidates
    HS = stanceStarts;   % swing->stance
    TO = stanceEnds;     % stance->swing

    % -----------------------------
    % 6) Refine HS/TO around edges
    % -----------------------------
    winHS = round(params.edgeWindowHS * Fs);
    winTO = round(params.edgeWindowTO * Fs);

    if params.useAccForHS
        acc_mag = sqrt(sum(acc.^2, 2));
        acc_f = lowpass1(acc_mag, params.fcutAccMag, Fs);
    else
        acc_f = [];
    end

    HS_ref = zeros(size(HS));
    TO_ref = zeros(size(TO));

    for i = 1:numel(HS)
        idx0 = HS(i);
        i1 = max(1, idx0 - winHS);
        i2 = min(N, idx0 + winHS);

        if params.useAccForHS
            % HS refinement: impact-like feature (max accel magnitude)
            [~, k] = max(acc_f(i1:i2));
        else
            % fallback: strongest pitch-rate change
            [~, k] = max(abs(pitch_rate(i1:i2)));
        end
        HS_ref(i) = i1 + k - 1;
    end

    for i = 1:numel(TO)
        idx0 = TO(i);
        i1 = max(1, idx0 - winTO);
        i2 = min(N, idx0 + winTO);

        % TO refinement: strongest pitch-rate change near stance end
        [~, k] = max(abs(pitch_rate(i1:i2)));
        TO_ref(i) = i1 + k - 1;
    end

    % -----------------------------
    % 7) Enforce ordering and plausibility
    % -----------------------------
    [HS_final, TO_final] = enforce_hs_to_ordering(HS_ref, TO_ref, Fs, params.minStepTime);

    % -----------------------------
    % Pack outputs
    % -----------------------------
    events.HS = HS_final(:);
    events.TO = TO_final(:);
    events.stance = stance(:);

    events.Fs = Fs;
    events.threshold_omega = Th;
    events.omega_mag_f = omega_f(:);

    events.pitch = pitch_f(:);
    events.pitch_rate = pitch_rate(:);
end

%% ---------------- helper functions ----------------

function qn = normalize_quat(q)
    n = sqrt(sum(q.^2, 2));
    n(n==0) = 1;
    qn = q ./ n;
end

function qc = enforce_quat_continuity(q)
    qc = q;
    for i = 2:size(q,1)
        if dot(qc(i,:), qc(i-1,:)) < 0
            qc(i,:) = -qc(i,:);
        end
    end
end

function y = lowpass1(x, fcut, Fs)
    if fcut >= Fs/2
        y = x;
        return;
    end
    [b,a] = butter(4, fcut/(Fs/2), 'low');
    y = filtfilt(b,a, x);
end

function [starts, ends] = binary_runs(b)
    b = b(:) ~= 0;
    db = diff([false; b; false]);
    starts = find(db == 1);
    ends   = find(db == -1) - 1;
end

function bout = clean_binary_segments(b, Fs, minTrueDur, minFalseDur)
    % Remove short true segments, fill short false gaps (debounce).
    b = b(:) ~= 0;

    % Remove short true segments
    [s,e] = binary_runs(b);
    for i = 1:numel(s)
        if (e(i) - s(i) + 1) < round(minTrueDur * Fs)
            b(s(i):e(i)) = false;
        end
    end

    % Fill short false gaps
    bInv = ~b;
    [s2,e2] = binary_runs(bInv);
    for i = 1:numel(s2)
        if (e2(i) - s2(i) + 1) < round(minFalseDur * Fs)
            b(s2(i):e2(i)) = true;
        end
    end

    bout = b;
end

function [HS_out, TO_out] = enforce_hs_to_ordering(HS, TO, Fs, minStepTime)
    HS = sort(unique(HS(:)));
    TO = sort(unique(TO(:)));

    HS_out = [];
    TO_out = [];

    minHSsep = round(minStepTime * Fs);

    iHS = 1;
    while iHS <= numel(HS)
        hs = HS(iHS);

        % Minimum separation between consecutive HS for same foot
        if ~isempty(HS_out) && (hs - HS_out(end) < minHSsep)
            iHS = iHS + 1;
            continue;
        end

        % First TO after HS
        jTO = find(TO > hs, 1, 'first');
        if isempty(jTO)
            break;
        end
        to = TO(jTO);

        % Next HS after TO (sanity)
        jHS2 = find(HS > to, 1, 'first');
        if isempty(jHS2)
            % accept last partial cycle
            HS_out(end+1,1) = hs;
            TO_out(end+1,1) = to;
            break;
        end
        hs2 = HS(jHS2);

        % Reject weird ordering / too-short intervals
        if (to - hs) < round(0.05 * Fs) || to > hs2
            iHS = iHS + 1;
            continue;
        end

        HS_out(end+1,1) = hs;
        TO_out(end+1,1) = to;

        iHS = jHS2;
    end
end
