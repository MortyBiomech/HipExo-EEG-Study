% 1. Define data arrays of subject 1
data_names = {
    'Delays_S3_EMG'; 
    'Delays_S4_EMG'; 
    'Delays_S1_EMG'; 
    'Delays_S5_EMG'; 
    'Delays_S6_EMG'; 
    'Delays_S0_EMG'; 
    'Delays_S7_EMG'; 
    'Delays_S8_EMG'; 
    'Delays_S9_EMG'; 
    'Delays_S10_EMG'; 
    'Delays_S11_EMG'; 
    'Delays_S12_EMG'; 
    'Delays_S13_EMG'; 
    'Delays_S14_EMG'; 
    'Delays_S15_EMG'; 
    'Delays_S2_EMG'; 
    'Delays_S16_EMG'; 
    'Delays_S17_EMG';
    'Delays_S18_EMG'
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
};

% Generate sensor IDs 1 to 19 as a numeric array
sensor_ids = (1:19)'; 

% Combine into a Table
subject_1 = table(sensor_ids, muscle_name, data_names, ...
    'VariableNames', {'SensorID', 'MuscleName', 'SignalName'});

% Display the entire table in the command window
% disp(subject_1);