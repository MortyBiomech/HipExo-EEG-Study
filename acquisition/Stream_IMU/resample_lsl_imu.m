function [tU, qU, gyroU, accU, FsEff] = resample_lsl_imu(t, q, gyro, acc, FsTarget)
%RESAMPLE_LSL_IMU Resample irregularly sampled LSL IMU data to uniform grid.
%
% Inputs:
%   t        Nx1 timestamps (seconds, from LSL)
%   q        Nx4 quaternion [w x y z]
%   gyro     Nx3 gyroscope
%   acc      Nx3 accelerometer (can be [])
%   FsTarget target uniform sampling rate (e.g., 50 or 100)
%
% Outputs:
%   tU       Mx1 uniform timestamps
%   qU       Mx4 resampled quaternion (renormalized, continuous sign)
%   gyroU    Mx3 resampled gyro
%   accU     Mx3 resampled acc (or [])
%   FsEff    effective rate computed from timestamps

    t = double(t(:));
    assert(size(q,1)==numel(t), 'q length must match t.');
    assert(size(gyro,1)==numel(t), 'gyro length must match t.');
    if ~isempty(acc)
        assert(size(acc,1)==numel(t), 'acc length must match t.');
    end

    % Sort by time (LSL usually already sorted, but be safe)
    [t, idx] = sort(t, 'ascend');
    q    = q(idx,:);
    gyro = gyro(idx,:);
    if ~isempty(acc), acc = acc(idx,:); end

    % Remove non-increasing timestamps (duplicates/backward steps)
    dt = diff(t);
    good = [true; dt > 0];
    t = t(good);
    q = q(good,:);
    gyro = gyro(good,:);
    if ~isempty(acc), acc = acc(good,:); end

    % Effective sampling rate estimate
    FsEff = 1 / median(diff(t));

    % Build uniform time grid
    t0 = t(1);
    t1 = t(end);
    tU = (t0 : 1/FsTarget : t1).';

    % Interpolate gyro/acc linearly (good enough for gait @ low freq)
    gyroU = interp1(t, gyro, tU, 'linear', 'extrap');
    if ~isempty(acc)
        accU  = interp1(t, acc,  tU, 'linear', 'extrap');
    else
        accU = [];
    end

    % Quaternion: interpolate then renormalize + enforce sign continuity
    % NOTE: This is a pragmatic approach. For maximum rigor use SLERP, but this
    % works well for smooth gait motion when resampling moderately.
    q = normalize_quat(q);
    q = enforce_quat_continuity(q);

    qU = interp1(t, q, tU, 'linear', 'extrap');
    qU = normalize_quat(qU);
    qU = enforce_quat_continuity(qU);
end

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
