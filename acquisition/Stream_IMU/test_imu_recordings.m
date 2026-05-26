clc
clear

%% add required paths
addpath(genpath('D:\Morteza\LSL\xdf-Matlab-master'))

%% load the sample data
% filePath = 'D:\Morteza\MyProjects\PassiveExo_EEG\Pilot tests\1) IMU and LSL\sub-P001\ses-S001\eeg';
% fileName = 'sub-P001_ses-S001_task-walking_IMU_GRF_run-001_eeg.xdf';
fileName = 'sub-P001_ses-S001_task-testing_srate_run-001_eeg.xdf';
% file_path = fullfile(filePath, fileName);
current_stream = load_xdf(fileName);

% ==============================
% %% check timing of IMU streams
% figure()
% timeIMU1 = current_stream{1,1}.time_stamps;
% % plot(1:length(timeIMU1), timeIMU1)
% plot(timeIMU1, 1*ones(1, length(timeIMU1)), 'LineWidth',2)
% hold on
% timeIMU2 = current_stream{1,2}.time_stamps;
% % plot(1:length(timeIMU2), timeIMU2)
% plot(timeIMU2, 2*ones(1, length(timeIMU2)), 'LineWidth',2)
% ylim([-5 9])
% ==============================


%% identify the indexes of each stream
Left_foot_IMU = '00B4D0C2';
Right_foot_IMU = '00B4D0D0';
N = length(current_stream);
for i = 1:N
    type = current_stream{1, i}.info.type;
    name = current_stream{1, i}.info.name;
    if strcmp(type, 'IMU')
        if contains(name, Left_foot_IMU)
            Left_foot_idx = i;
        elseif contains(name, Right_foot_IMU)
            Right_foot_idx = i;
        end
    elseif strcmp(type, 'Force') && strcmp(name, 'GRF')
        grf_idx = i;
    end
end


%% reconstruct right and left foot GRF
L_grf_idx = [2 3 6 7];
R_grf_idx = [1 4 5 8];

L_GRF = sum(current_stream{1, grf_idx}.time_series(L_grf_idx, :), 1);
R_GRF = sum(current_stream{1, grf_idx}.time_series(R_grf_idx, :), 1);


%% plot some figures to see the IMU and GRF streams
T = 95200; % cut the starting point in IMU timestamps
duration = 5; % second
[~, Left_IMU_indx_start] = min(abs(current_stream{1, Left_foot_idx}.time_stamps - T));
[~, Right_IMU_indx_start] = min(abs(current_stream{1, Right_foot_idx}.time_stamps - T));
[~, Left_IMU_indx_end] = min(abs(current_stream{1, Left_foot_idx}.time_stamps - T - duration));
[~, Right_IMU_indx_end] = min(abs(current_stream{1, Right_foot_idx}.time_stamps - T - duration));

% check IMU (9 channels: qx, qy, qz, ax, ay, az, gx, gy, gz)
figure()
tiledlayout(3, 12, "TileSpacing", "compact", "Padding", "compact");
for i = 1:10
    label = current_stream{1, Left_foot_idx}.info.desc.channels.channel{1,i}.label;
    if i <=4
        nexttile(3*i-2, [1, 3])
        sig = current_stream{1, Left_foot_idx}.time_series(i, Left_IMU_indx_start-100:Left_IMU_indx_end+100);
        % sig = sig - mean(sig);
        plot(current_stream{1, Left_foot_idx}.time_stamps(Left_IMU_indx_start-100:Left_IMU_indx_end+100) - T, ...
            sig, ...
            'Color', 'b');
        hold on
        sig = current_stream{1, Right_foot_idx}.time_series(i, Right_IMU_indx_start-100:Right_IMU_indx_end+100);
        % sig = sig - mean(sig);
        plot(current_stream{1, Right_foot_idx}.time_stamps(Right_IMU_indx_start-100:Right_IMU_indx_end+100) - T, ...
            sig, ...
            'Color', 'r');
        title(label, 'FontWeight', 'bold')
        xlim([0, duration])
        xlabel('Time (s)')

    else
        nexttile(4*(i-1)-3, [1, 4])
        sig = current_stream{1, Left_foot_idx}.time_series(i, Left_IMU_indx_start-100:Left_IMU_indx_end+100);
        % sig = sig - mean(sig);
        plot(current_stream{1, Left_foot_idx}.time_stamps(Left_IMU_indx_start-100:Left_IMU_indx_end+100) - T, ...
            sig, ...
            'Color', 'b');
        hold on
        sig = current_stream{1, Right_foot_idx}.time_series(i, Right_IMU_indx_start-100:Right_IMU_indx_end+100);
        % sig = sig - mean(sig);
        plot(current_stream{1, Right_foot_idx}.time_stamps(Right_IMU_indx_start-100:Right_IMU_indx_end+100) - T, ...
            sig, ...
            'Color', 'r');
        title(label, 'FontWeight', 'bold')
        xlim([0, duration])
    end

    if i > 7
        xlabel('Time (s)')
    end

    set(gca, 'FontSize', 14)
    % YLimit = get(gca, 'YLim');
    % new_ylim = [-max(abs(YLimit)) max(abs(YLimit))];
    % set(gca, 'YLim', new_ylim)
end



% %% Plot a figure showing qx and GRF
% 
% figure()
% plot(current_stream{1, 3}.time_stamps, L_GRF, 'Color', 'b');
% hold on
% plot(current_stream{1, 3}.time_stamps, R_GRF, 'Color', 'r');
% legend({'Left', 'Right'})



%% Try the function from ChatGPT

% using gyro
% % Right foot
% tR = current_stream{1, Right_foot_idx}.time_stamps';
% qR = current_stream{1, Right_foot_idx}.time_series(1:4, :)';
% accR = current_stream{1, Right_foot_idx}.time_series(5:7, :)';
% gyroR = current_stream{1, Right_foot_idx}.time_series(8:10, :)';
% evR = detect_gait_events_imu(tR, qR, gyroR, accR);
% 
% % Left foot
% tL = current_stream{1, Left_foot_idx}.time_stamps';
% qL = current_stream{1, Left_foot_idx}.time_series(1:4, :)';
% accL = current_stream{1, Left_foot_idx}.time_series(5:7, :)';
% gyroL = current_stream{1, Left_foot_idx}.time_series(8:10, :)';
% evL = detect_gait_events_imu(tL, qL, gyroL, accL);
% 
% % Plot quick check
% FsR = evR.Fs;
% tRu = (0:size(qR,1)-1)/FsR; % (approx) if you want sample time; better: use tR
% figure; plot(evR.omega_mag_f); hold on; yline(evR.threshold_omega,'--');
% stem(evR.HS, evR.omega_mag_f(evR.HS), 'g');
% stem(evR.TO, evR.omega_mag_f(evR.TO), 'r');
% legend('|omega| LPF','threshold','HS','TO'); xlabel('sample');


% % use acc + pitch angle
% % Right foot
% tR = current_stream{1, Right_foot_idx}.time_stamps';
% qR = current_stream{1, Right_foot_idx}.time_series(1:4, :)';
% accR = current_stream{1, Right_foot_idx}.time_series(5:7, :)';
% gyroR = current_stream{1, Right_foot_idx}.time_series(8:10, :)';
% ev = detect_gait_events_pitch_acc(tR, qR, accR);
% 
% figure;
% plot(ev.pitch); hold on;
% stem(ev.HS, ev.pitch(ev.HS), 'g');
% stem(ev.TO, ev.pitch(ev.TO), 'r');
% legend('pitch','HS','TO'); xlabel('sample');
% 
% figure;
% plot(ev.acc_mag); hold on;
% stem(ev.HS, ev.acc_mag(ev.HS), 'g');
% legend('|acc| (LPF)','HS'); xlabel('sample');


% Right foot
tR = current_stream{1, Right_foot_idx}.time_stamps';
qR = current_stream{1, Right_foot_idx}.time_series(1:4, :)';
accR = current_stream{1, Right_foot_idx}.time_series(5:7, :)';
gyroR = current_stream{1, Right_foot_idx}.time_series(8:10, :)';
ev = detect_gait_events_pitch_only(tR, qR);

figure;
plot(ev.pitch); hold on;
stem(ev.TO, ev.pitch(ev.TO), 'r', 'filled');   % minima (TO proxy)
stem(ev.HS, ev.pitch(ev.HS), 'g', 'filled');   % maxima (HS proxy)
legend('pitch','TO (min)','HS (max)');
xlabel('sample'); ylabel('rad');

