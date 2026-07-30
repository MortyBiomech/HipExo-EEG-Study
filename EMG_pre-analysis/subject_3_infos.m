% 1. Define data arrays of subject 3
data_names_day1 = {
    '3_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '12_Delsys_(12)AvantiSensor_Pair12_EMG'; 
    '10_Delsys_(10)AvantiSensor_Pair10_EMG'; 
    '13_Delsys_(13)AvantiSensor_Pair13_EMG';
    '15_Delsys_(15)AvantiSensor_Pair15_EMG';
    '14_Delsys_(14)AvantiSensor_Pair14_EMG';
    '5_Delsys_(4)AvantiSensor_Pair4_EMG';
    '7_Delsys_(7)AvantiSensor_Pair7_EMG';
    '18_Delsys_(19)DuoSensor_Pair19_EMG';
    '16_Delsys_(17)DuoSensor_Pair17_EMG';
    '9_Delsys_(9)AvantiSensor_Pair9_EMG';
    '6_Delsys_(5)AvantiSensor_Pair5_EMG';
    '2_Delsys_(0)AvantiSensor_Pair0_EMG';
    '1_Delsys_(0)AvantiSensor_Pair0_EMG';
    '8_Delsys_(8)AvantiSensor_Pair8_EMG';
    '4_Delsys_(0)AvantiSensor_Pair0_EMG';
    '11_Delsys_(11)AvantiSensor_Pair11_EMG';
    '17_Delsys_(18)DuoSensor_Pair18_EMG';
    'None';
    
};

uid_day1 = {
    '85699541-0c21-4386-8032-e30545dd4728'; % 1
    'ab32dae5-4f60-4aa1-93f9-0761fc5d44cc'; % 2
    '52838f78-11b7-4511-bc09-3450739e2fc4'; % 3
    '31efc7e4-81b2-4170-9477-bd9d5b8c21a2'; % 4
    '5e814c88-13dc-44e8-8153-30e9c648fc55'; % 5
    '44f61ff3-7762-4cde-bb9a-284f1eee9cbc'; % 6
    'e7d9dc14-d373-4e80-a590-ff8f01a901dd'; % 7
    '9625b22a-33ca-4880-b988-3168321ec879'; % 8
    'a27eeec1-d75c-495a-890e-8a75cc7301e4'; % 9
    'c7f4bf05-9143-4f05-b6a3-20e23acb3287'; % 10
    'd8874bf6-397f-44a7-9782-efab6ebd3508'; % 11
    '20554eec-6169-45cb-9b60-61276b9a2345'; % 12
    'b1db6476-0f24-4f2d-bf89-fc156de4558b'; % 13
    'ac4fc6d5-ce87-4ebf-8bc5-31276c7c48a4'; % 14
    '7ab00fba-129b-4cde-a45c-fc18fade3305'; % 15
    'c9a10910-99b4-49c0-81f0-60a5de25d095'; % 16
    'c18e2369-809c-4a13-ab64-52c2b0833a77'; % 17
    '3b77bf58-158e-4ad4-b8ce-ded438a0d008'; % 18
    'None'; % 19
};

data_names_day2 = {
    '3_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '4_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '5_Delsys_(0)AvantiSensor_Pair0_EMG'; 
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
    '2_Delsys_(0)AvantiSensor_Pair0_EMG'; 
    '17_Delsys_(17)DuoSensor_Pair17_EMG'; 
    '18_Delsys_(18)DuoSensor_Pair18_EMG';
    '19_Delsys_(19)DuoSensor_Pair19_EMG'
};

uid_day2 = {
    '4eb8baab-6229-47b5-bf79-91dc890a1189' % 1
    '147b8d7f-b455-4414-a7ca-7c36c2556797' % 2
    '8f832fe2-0dcd-4f61-8923-188c1d8a24f1' % 3
    'dc879849-082d-45f1-b517-867225f172f1' % 4
    '481ca5d1-65a7-4762-bcf6-a61f7960117d' % 5
    '1fbf41b7-bedb-40b1-8d4c-edebc2f28bc8' % 6
    'a823ca4f-8e29-4605-8825-c7ca7ba7c88a' % 7
    '0e69aff0-e139-4abb-93c2-e76e1e24b9a7' % 8
    '170e43c9-573c-42b7-a000-0c31c9695f08' % 9
    '59832f6f-5f0d-495e-a4ed-51fa566cf03d' % 10
    '3f97b753-2862-4a73-bd15-440ad9761dbb' % 11
    '7f4afdc6-e536-4f3d-a5a3-3a0085cc15d1' % 12
    'cbe48b4e-0765-4f01-97b5-3ea34d9c1d53' % 13
    '5730acaa-9a44-47cd-a224-599c3d86d225' % 14
    '0e9cf733-3240-4105-bdc7-b2e5fb861b8e' % 15
    '204b0fd5-0700-427f-9656-5783deb63551' % 16
    'ef1ed774-a160-4fe8-932f-94d04e01dfb3' % 17
    '31d2895a-c568-4db9-b419-e111322beede' % 18
    '02067069-22e6-401e-8622-5e59031cc80e' % 19
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
subject_3 = table(sensor_ids, muscle_name, data_names_day1, uid_day1, data_names_day2, uid_day2,  ...
    'VariableNames', {'SensorID', 'MuscleName', 'SignalName_1', 'UID_1', 'SignalName_2', 'UID_2'});

% Display the entire table in the command window
 disp(subject_3);