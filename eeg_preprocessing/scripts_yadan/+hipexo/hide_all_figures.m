function hide_all_figures()
% GOAL
%   Hide and close EEGLAB/BeMoBIL figures during unattended batch processing.
%
% METHOD
%   Disable default figure visibility, expose hidden figure handles, and
%   close currently open figures without failing the processing stage if a
%   graphics operation itself raises an error.

try
    set(0, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureVisible', 'off');
    set(0, 'ShowHiddenHandles', 'on');
catch
end

try
    figs = findall(groot, 'Type', 'figure');

    if ~isempty(figs)
        set(figs, 'Visible', 'off');
        close(figs);
    end

catch
    try
        close all force;
    catch
    end
end

end
