% 1. Define data arrays of subject 2
data_names = {
    '4_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '5_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '2_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '6_Delsys_(4)AvantiSensor_Pair4_EMG'; 
    '7_Delsys_(5)AvantiSensor_Pair5_EMG'; 
    '1_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '8_Delsys_(7)AvantiSensor_Pair7_EMG'; 
    '9_Delsys_(8)AvantiSensor_Pair8_EMG'; 
    '10_Delsys_(9)AvantiSensor_Pair9_EMG'; 
    '11_Delsys_(10)AvantiSensor_Pair10_EMG'; 
    '12_Delsys_(11)AvantiSensor_Pair11_EMG'; 
    '13_Delsys_(12)AvantiSensor_Pair12_EMG'; 
    '14_Delsys_(13)AvantiSensor_Pair13_EMG'; 
    '15_Delsys_(14)AvantiSensor_Pair14_EMG'; 
    '16_Delsys_(15)AvantiSensor_Pair15_EMG'; 
    '3_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '17_Delsys_(17)DuoSensor_Pair17_EMG'; 
    '18_Delsys_(18)DuoSensor_Pair18_EMG';
    '19_Delsys_(19)DuoSensor_Pair19_EMG'
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
subject_2 = table(sensor_ids, muscle_name, data_names, ...
    'VariableNames', {'SensorID', 'MuscleName', 'SignalName'});

% Display the entire table in the command window
 disp(subject_2);