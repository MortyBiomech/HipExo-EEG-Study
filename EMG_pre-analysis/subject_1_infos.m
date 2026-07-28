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
};

% Generate sensor IDs 1 to 19 as a numeric array
sensor_ids = (1:19)'; 

% Combine into a Table
subject_1 = table(sensor_ids, muscle_name, data_names, ...
    'VariableNames', {'SensorID', 'MuscleName', 'SignalName'});

% Display the entire table in the command window
 disp(subject_1);