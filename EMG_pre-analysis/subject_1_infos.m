% 1. Define data arrays of subject 1
data_names = {
    'Delsys_S3_EMG'; 
    'Delsys_S4_EMG'; 
    'Delsys_S1_EMG'; 
    'Delsys_S5_EMG'; 
    'Delsys_S6_EMG'; 
    'Delsys_S0_EMG'; 
    'Delsys_S7_EMG'; 
    'Delsys_S8_EMG'; 
    'Delsys_S9_EMG'; 
    'Delsys_S10_EMG'; 
    'Delsys_S11_EMG'; 
    'Delsys_S12_EMG'; 
    'Delsys_S13_EMG'; 
    'Delsys_S14_EMG'; 
    'Delsys_S15_EMG'; 
    'Delsys_S2_EMG'; 
    'Delsys_S16_EMG'; 
    'Delsys_S17_EMG';
    'Delsys_S18_EMG'
};

muscle_name = {
    % Right leg 1-7
    'Tibialis anterior R'; 
    'Soleus R'; 
    'Gastrocnemius cap. mediale R'; 
    'Vastus medialis R'; 
    'Rectus femoris R'; 
    'Biceps femoris R'; 
    'Glutaeus maximus R';
    % Left leg 8-14
    'Tibialis anterior L'; 
    'Soleus L'; 
    'Gastrocnemius cap. mediale L'; 
    'Vastus medialis L'; 
    'Rectus femoris L'; 
    'Biceps femoris L'; 
    'Glutaeus maximus L';
    % Neck
    'Trapezius R'; 
    'Trapezius L'; 
    'SCM R'; 
    'SCM L'; 
    % Face
    'Zygomaticus'

     % 'Tib_ant_R',  # 对应 Tibialis anterior R
        % 'Soleus_R',  # 对应 Soleus R
        % 'Gast_med_R',  # 对应 Gastrocnemius cap. mediale R
        % 'Vastus_med_R',  # 对应 Vastus medialis R
        % 'Rect_fem_R',  # 对应 Rectus femoris R
        % 'Biceps_fem_R',  # 对应 Biceps femoris R
        % 'Glut_max_R',  # 对应 Glutaeus maximus R
        % 'Tib_ant_L',  # 对应 Tibialis anterior L
        % 'Soleus_L',  # 对应 Soleus L
        % 'Gast_med_L',  # 对应 Gastrocnemius cap. mediale L
        % 'Vastus_med_L',  # 对应 Vastus medialis L
        % 'Rect_fem_L',  # 对应 Rectus femoris L
        % 'Biceps_fem_L',  # 对应 Biceps femoris L
        % 'Glut_max_L',  # 对应 Glutaeus maximus L
        % 'Trapezius_R',  # 对应 Trapezius R (11字符)
        % 'Trapezius_L',  # 对应 Trapezius L (11字符)
        % 'SCM_R',  # 对应 SCM R
        % 'SCM_L',  # 对应 SCM L
        % 'Zygomaticus'  # 对应 Zygomaticus (11字符)
};

% Generate sensor IDs 1 to 19 as a numeric array
sensor_ids = (1:19)'; 

% Combine into a Table
subject_1 = table(sensor_ids, muscle_name, data_names, ...
    'VariableNames', {'SensorID', 'MuscleName', 'SignalName'});

% Display the entire table in the command window
 disp(subject_1);