function rootFolder = project_root()
%PROJECT_ROOT Return the HipExo-EEG source root independent of caller folder.
packageFolder = fileparts(mfilename('fullpath'));
rootFolder = fileparts(packageFolder);
end
