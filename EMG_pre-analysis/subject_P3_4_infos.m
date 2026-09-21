% Subject P3_4:  mapping from muscles to physical Delsys sensors.
%
% IMPORTANT:
%   SensorID is the unique Delsys DEC ID. 

muscle_name = {
    % Right leg
    'Tibialis anterior R';
    'Soleus R';
    'Gastrocnemius cap. mediale R';
    'Vastus medialis R';
    'Rectus femoris R';
    'Biceps femoris R';
    'Glutaeus maximus R';
    % Left leg
    'Tibialis anterior L';
    'Soleus L';
    'Gastrocnemius cap. mediale L';
    'Vastus medialis L';
    'Rectus femoris L';
    'Biceps femoris L';
    'Glutaeus maximus L';

    % Neck 
    'Trapezius R'; % 15
    'Trapezius L'; % 16
    'around Trapezius R'; % duo 1
    'around Trapezius L'; % duo 2
    'above Trapezius' % ch1 right， ch2 left % duo 3 
};

% The DEC IDs below correspond one-to-one to muscle_name rows 1-19.
sensor_dec_id = [
    88600; 88596; 88693; 88657; 88562; 88666; 88594;
    88668; 88514; 88530; 88545; 88592; 88667; 88519;
    88658; 88659; 76614; 76573; 76624
];

sensor_type = [
    repmat({'AvantiSensor'}, 16, 1);
    repmat({'DuoSensor'},     3, 1)
];

subject_P3_4 = table(sensor_dec_id, muscle_name, sensor_type, ...
    'VariableNames', {'SensorID', 'MuscleName', 'SensorType'});

% Uncomment for a quick mapping check in MATLAB:
% disp(subject_4);
