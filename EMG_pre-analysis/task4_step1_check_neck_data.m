function varargout = task4_step1_check_neck_data(configFile)
% CHECK_NECK_EMG_CHANNELS  Task 4a: raw XDF neck-channel audit (v1.5.1).
% v1.5.1: also recognize <condition>_walking_Start/End suffix markers.
% v1.5.0: add last valid non-standing marker-defined walking interval.
% Marker streams: IMU_Markers and GRF_Markers; compare if both exist.
% Never fall back to the full recording when markers fail.
% neck_qc.confirmedEMGUnit = 'mV'; % P3 user-confirmed, label only, no scaling
% neck_qc.markerAgreementTolerance_s = 0.001; % agreement between marker streams
% Walking outputs: walking_intervals.tsv, walking_neck_channel_qc.tsv,
% walking_session_overview.tsv, walking_human_review.tsv, *_walking_neck.png.
% Full-record outputs retain their existing names and meaning.
% Every selected XDF is loaded twice with clock sync explicitly ON:
% HandleJitterRemoval=false for diagnostics, true for duration/gap checks.
% No signal resampling or timestamp sorting. Both time axes are saved.
% Status/ChannelStatus describe signal integrity, NOT readiness for CMC.
% TimingStatus is separate; SynchronizationStatus remains NOT_VALIDATED.
% XDF basenames containing 'old' (case-insensitive) are always excluded
% before load_xdf. Exclusions remain documented in file_selection.tsv.
% MATLAB R2020b+; requires EEGLAB's load_xdf on the MATLAB path.
% Usage: check_neck_emg_channels('config_paths.m'); % compact display only
% [report, overview] = check_neck_emg_channels('config_paths.m');
% report retains detailed per-channel data; overview has one row per XDF/run.
% With no argument, searches for config_path.m, then config_paths.m.
%
% Default mapping: last five physical sensors in subject_P3_N_infos.m.
% IDs are matched independently in every XDF; raw column order is irrelevant.
% A Duo's two matched outputs are ordered by raw column, NOT assumed CH1/CH2.
% Placement text is source-file provenance, not a verified day-specific label.
% Add the following settings to your path configuration:
% neck_qc.subjectInfoFile = 'subject_P3_1_infos.m'; % or full path
% Default filename is inferred from subject_id Pilot3_1 / P3_1.
% neck_qc.mappingMode = 'sensor_id'; % default; 'manual' for legacy mappings
% Optional manual-mode settings only:
% neck_qc.streamName = 'EXACT name shown in stream_inventory.tsv';
% neck_qc.channelLabels = {'label1','label2',...,'label8'}; % exact XDF labels
% OR (only after verifying the acquisition wiring/order):
% neck_qc.channelIndices = 15:22; % EXAMPLE ONLY, NOT a verified mapping!
% neck_qc.expectedChannelCount = 22;
% neck_qc.scanRoot = data_path; % default: current experiment day only
% neck_qc.runFilter = run_id; % default: config run_id; use '' for all runs
% neck_qc.sessionFilter = ''; % optional session-name substring
% neck_qc.excludedSessionKeywords = {'calibration','calib','setup'};
% neck_qc.derivativesContainer = 'C:\2026SSArbeit\data\PilotTest3_BIDS';
% neck_qc.excludeRegex = ''; % optional additional exclusion; logged in manifest
% neck_qc.flatSeconds = 1; % repeated identical samples -> REVIEW, not exclusion
% neck_qc.gapFactor = 5;   % after-dejitter interval > 5*median -> timing REVIEW
%
% No filtering, resampling, calibration, ICA or coherence is performed.
% Outputs: session_overview.tsv (separate channel/timing status),
% neck_channel_qc.tsv (Status = ChannelStatus, basic signal integrity),
% session_timing_status.tsv, timestamp_comparison.tsv, numbered before/after
% timestamp diagnostics/examples, time_axes.mat and raw neck PNGs.
% Two imports per selected file cost extra time; no calibration/old files loaded.
% Full recordings are assessed, including resting periods. Flat stretches
% can be intentional rest: REVIEW is a flag, not a physiological conclusion.
% Presence alone does not establish usability. AUTO_PASS needs visual review.
% No mapping supplied: inventory is saved, all eight channels are NOT_ASSESSED.
% Index mapping is refused when total channel count changes (shift risk).
% Coverage is existing XDFs under scanRoot, not an expected-session registry.

if nargin < 1 || isempty(configFile)
    configFile = which('config_path.m');
    if isempty(configFile), configFile = which('config_paths.m'); end
    if isempty(configFile), error('Specify the full path to your config file.'); end
end
configFile = char(configFile);
if ~isfile(configFile), error('Configuration not found: %s',configFile); end
[ok,attr] = fileattrib(configFile); if ok, configFile = attr.Name; end
% Your existing config runs its own day/run validation before this audit.
run(configFile);
if ~exist('load_xdf','file'), error('Add the folder containing load_xdf.m to the MATLAB path.'); end
if ~exist('subject_id','var'), error('Config must define subject_id.'); end
if ~exist('neck_qc','var'), neck_qc = struct; end
q = neck_qc;
if ~isfield(q,'scanRoot')
    if exist('data_path','var')
        q.scanRoot = data_path;
    elseif exist('data_root','var') && exist('subject_folder','var') && exist('experiment_day','var')
        q.scanRoot = fullfile(data_root,subject_folder,experiment_day,'data');
    else
        error('Config must define data_path, or data_root + subject_folder + experiment_day.');
    end
end
q = defaultField(q,'outputRoot',fullfile(q.scanRoot,'neck_emg_QC'));
q = defaultField(q,'streamName','');
q = defaultField(q,'channelLabels',{});
q = defaultField(q,'channelIndices',[]);
q = defaultField(q,'mappingMode','sensor_id');
q.mappingMode=char(q.mappingMode);
assert(ismember(string(q.mappingMode),["sensor_id","manual"]),'Invalid mappingMode.');
q = defaultField(q,'subjectInfoFile','');
subjectMap=table; neckMap=table;
if strcmp(q.mappingMode,'sensor_id')
    if isempty(q.subjectInfoFile)
        token=regexp(char(subject_id),'(?:Pilot|P)3[_-]?(\d+)$','tokens','once');
        if isempty(token)
            error('Cannot infer P3 subject. Set neck_qc.subjectInfoFile explicitly.');
        end
        q.subjectInfoFile=['subject_P3_' token{1} '_infos.m'];
    end
    infoPath=which(char(q.subjectInfoFile));
    if isempty(infoPath), infoPath=char(q.subjectInfoFile); end
    if ~isfile(infoPath), infoPath=fullfile(fileparts(configFile),char(q.subjectInfoFile)); end
    assert(isfile(infoPath),'Subject info not found. Set neck_qc.subjectInfoFile to its full path.');
    [~,infoAttr]=fileattrib(infoPath); q.subjectInfoFile=infoAttr.Name;
    subjectMap=readSubjectInfo(q.subjectInfoFile);
    neckMap=expandNeckSensors(subjectMap);
    q.channelLabels={}; q.channelIndices=[]; % ID mode overrides old column settings.
    fprintf('ID mapping source: %s\n',q.subjectInfoFile);
    disp(neckMap(:,{'SensorID','SensorType','OutputOrdinal','PlacementFromInfo'}));
end
q = defaultField(q,'expectedChannelCount',22);
q = defaultField(q,'excludeRegex','');
q = defaultField(q,'excludedSessionKeywords',{'calibration','calib','setup'});
q = defaultField(q,'sessionFilter','');
if exist('run_id','var'), defaultRun=char(string(run_id)); else, defaultRun=''; end
q = defaultField(q,'runFilter',defaultRun);
q.streamName=char(q.streamName); q.excludeRegex=char(q.excludeRegex);
q.sessionFilter=char(q.sessionFilter); q.runFilter=char(string(q.runFilter));
q = defaultField(q,'flatSeconds',1);
q = defaultField(q,'gapFactor',5);
if strcmp(q.mappingMode,'sensor_id'), defaultUnit='mV'; else, defaultUnit=''; end
q = defaultField(q,'confirmedEMGUnit',defaultUnit);
q = defaultField(q,'markerAgreementTolerance_s',0.001);
assert(isscalar(q.markerAgreementTolerance_s) && isfinite(q.markerAgreementTolerance_s) && ...
    q.markerAgreementTolerance_s>=0,'Invalid marker agreement tolerance.');
if strcmp(q.mappingMode,'manual')
if ~isempty(q.channelLabels) && ~isempty(q.channelIndices)
    error('Set channelLabels OR channelIndices, not both.');
end
if ~isempty(q.channelLabels)
    q.channelLabels = reshape(string(q.channelLabels),1,[]);
    assert(numel(q.channelLabels)==8 && numel(unique(q.channelLabels))==8 && ...
        all(strlength(q.channelLabels)>0),'Provide eight unique nonempty labels.');
elseif ~isempty(q.channelIndices)
    q.channelIndices = reshape(q.channelIndices,1,[]);
    assert(numel(q.channelIndices)==8 && numel(unique(q.channelIndices))==8 && ...
        all(q.channelIndices>=1 & mod(q.channelIndices,1)==0),'Provide eight unique positive indices.');
else
    warning('NeckQC:Mapping','Neck mapping not set: inventory mode. Set channelLabels OR verified channelIndices in the config. This does NOT mean channels are missing.');
end
end % manual mapping validation
assert(isfolder(q.scanRoot),'scanRoot does not exist.');
assert(q.flatSeconds>0 && q.gapFactor>1,'Invalid QC thresholds.');
% Stable subject/day/run report destination; no version or date folders.
derivativesContainer = bids_root;

assert(~isempty(regexp(char(subject_id),'^Pilot3_?\d+$','once')), 'PilotTest3 only.');

assert(exist('experiment_day','var')==1,'Config must define experiment_day.');

qcRoot=directDataset(derivativesContainer,'p3neckqc');

subLabel=regexprep(char(subject_id),'[^A-Za-z0-9]','');

scopeLabel=regexprep([char(experiment_day) 'Run' q.runFilter 'Session' q.sessionFilter], ...
    '[^A-Za-z0-9]','');
out=fullfile(qcRoot,['sub-' subLabel],'reports',['desc-' scopeLabel]);
if ~isfolder(out), mkdir(out); end
q.outputRoot=out;
copyfile(configFile,fullfile(out,'configuration_used.m'));
if strcmp(q.mappingMode,'sensor_id')
    copyfile(q.subjectInfoFile,fullfile(out,'subject_info_used.m'));
    writeDerivativeTable(neckMap,fullfile(out,'expected_neck_sensors.tsv'));
end
copyfile([mfilename('fullpath') '.m'],fullfile(out,'audit_code_used.m'));
files = dir(fullfile(q.scanRoot,'**','*.xdf'));
if isempty(files), error('No XDF files found under %s. No sessions assessed.',q.scanRoot); end
[files,manifest] = selectFiles(files,q);
writeDerivativeTable(manifest,fullfile(out,'file_selection.tsv'));
fprintf('Scan root: %s\nRun filter: %s\n',q.scanRoot,q.runFilter);
fprintf('Discovered %d XDFs; selected %d; excluded %d.\n',height(manifest),numel(files),sum(~manifest.Selected));
fprintf('Full inclusion/exclusion list: %s\n',fullfile(out,'file_selection.tsv'));
if isempty(files)
    error('No XDFs remain after filtering. Inspect %s',fullfile(out,'file_selection.tsv'));
end
for sourceIndex=1:numel(files)
    identity=directIdentity(fullfile(files(sourceIndex).folder,files(sourceIndex).name),struct);
    assert(strcmp(identity.Subject,subLabel)&&strcmp(identity.Day,char(experiment_day)), ...
        'Selected source is outside configured subject/day: %s',identity.SourceFile);
end
selected=manifest(manifest.Selected,:);
sessionKeys=unique(selected.SessionKey,'stable');
fprintf('Selected session groups: %d; XDF files: %d (not necessarily equal).\n',numel(sessionKeys),numel(files));
for j=1:numel(sessionKeys)
    count=sum(selected.SessionKey==sessionKeys(j));
    if count>1
        warning('NeckQC:MultipleFiles','%s has %d selected XDFs. All are audited; check duplicates/runs in file_selection.tsv.',sessionKeys(j),count);
    end
end
timingRows={}; walkingRows=repmat(blankRow(),0,1); walkingIntervals={};
q.loadXdfPath=which('load_xdf');
copyfile(q.loadXdfPath,fullfile(out,'load_xdf_used.m'));
rows = repmat(blankRow(),0,1); inventory = struct('File',{},'Stream',{},'Type',{},'Channel',{},'Label',{},'Unit',{},'MetadataJSON',{});
logfile = fullfile(out,'alerts.txt'); fid=fopen(logfile,'w'); assert(fid>=0);
closer = onCleanup(@() fclose(fid)); 
fprintf(fid,'Subject: %s\nRoot: %s\nFull recordings; existing XDF files only.\n',subject_id,q.scanRoot);
fprintf('Auditing subject %s: %d XDF files under %s\n',subject_id,numel(files),q.scanRoot);
for f = 1:numel(files)
    clear streams st x t; % release preceding recording before next import
    path = fullfile(files(f).folder,files(f).name);
    walk=blankWalking(); walk.File=string(path); walk.Session=selected.Session(f); walk.Run=selected.Run(f);
    walkBase=[];
    base = repmat(blankRow(),8,1);
    for k=1:8
        base(k).Subject=string(subject_id); base(k).File=string(path); base(k).NeckSlot=k;
        base(k).Session=selected.Session(f); base(k).Run=selected.Run(f);
        if ~isempty(q.channelLabels), base(k).ExpectedLabel=q.channelLabels(k); end
        if strcmp(q.mappingMode,'sensor_id')
            base(k).SensorID=neckMap.SensorID(k);
            base(k).SensorType=neckMap.SensorType(k);
            base(k).OutputOrdinal=neckMap.OutputOrdinal(k);
            base(k).PlacementFromInfo=neckMap.PlacementFromInfo(k);
        end
    end
    try
        sessionIndex=find(sessionKeys==selected.SessionKey(f),1);
        fprintf('[File %d/%d | Session %d/%d: %s | Run %s] %s\n',...
            f,numel(files),sessionIndex,numel(sessionKeys),selected.Session(f),selected.Run(f),files(f).name);
        % Disable timestamp dejittering so gaps/irregularity are not hidden.
        streams=load_xdf(path,'HandleClockSynchronization',true,'HandleJitterRemoval',false);
        if ~iscell(streams), streams=num2cell(streams); end
        candidates=[];
        for s=1:numel(streams)
            st=streams{s}; name=infoText(st,'name'); typ=infoText(st,'type');
            n=size(st.time_series,1); [labels,units,metadata]=channelMeta(st,n);
            for c=1:n
                inventory(end+1)=struct('File',string(path),'Stream',name,'Type',typ,...
                    'Channel',c,'Label',labels(c),'Unit',units(c),'MetadataJSON',string(jsonencode(metadata{c}))); %#ok<AGROW>
            end
            if (~isempty(q.streamName) && name==string(q.streamName)) || ...
                    (isempty(q.streamName) && strcmpi(typ,'EMG'))
                candidates(end+1)=s; %#ok<AGROW>
            end
        end
        if isempty(candidates)
            base=setStatus(base,'MISSING_STREAM','Expected EMG stream not found; inspect inventory/streamName.');
        elseif numel(candidates)>1
            base=setStatus(base,'NOT_ASSESSED','Multiple matching EMG streams; specify exact streamName.');
        else
            st=streams{candidates}; x=st.time_series; t=double(st.time_stamps(:));
            assert(isnumeric(x)&&ismatrix(x),'EMG time_series must be numeric channels x samples.');
            % Release other streams before the second import (large XDFs).
            clear streams;
            [t,timingStatus,timingNote,pair,walk]=compareTimeAxes(st,path,out,f,selected.Session(f),selected.Run(f),q);
            timingRows{end+1}=pair; %#ok<AGROW>
            writeDerivativeTable(struct2table(vertcat(timingRows{:})),fullfile(out,'timestamp_comparison.tsv'));
            for kk=1:8
                base(kk).TimingStatus=timingStatus;
                base(kk).TimingNotes=timingNote;
                base(kk).BeforeBackward=pair.BeforeBackward;
                base(kk).AfterBackward=pair.AfterBackward;
            end
            fprintf('  TIME AXIS | %s | before backward=%g | after backward=%g\n',...
                timingStatus,pair.BeforeBackward,pair.AfterBackward);
            fprintf('  %s\n',timingNote);
            n=size(x,1); [labels,units,metadata]=channelMeta(st,n); indices=nan(1,8);
            streamInfo=st.info; %#ok<NASGU>
            save(fullfile(out,sprintf('%04d_stream_metadata.mat',f)),'streamInfo');
            fprintf('  EMG stream: %s | actual channels: %d | expected: %d\n',infoText(st,'name'),n,q.expectedChannelCount);
            if strcmp(q.mappingMode,'sensor_id')
                for kk=1:8, base(kk).Stream=infoText(st,'name'); end
                base=assessBySensorID(base,x,t,labels,units,metadata,subjectMap,neckMap,q);
            else
            if ~isempty(q.channelLabels)
                for k=1:8
                    matches=find(labels==q.channelLabels(k));
                    if numel(matches)==1, indices(k)=matches;
                    elseif numel(matches)>1, indices(k)=-1; end
                end
            elseif ~isempty(q.channelIndices) && n==q.expectedChannelCount
                indices=q.channelIndices;
            end
            for k=1:8
                base(k).Stream=infoText(st,'name'); base(k).StreamChannels=n;
                if isempty(q.channelLabels) && isempty(q.channelIndices)
                    base(k).Status="NOT_ASSESSED";
                    base(k).Notes="MAPPING_NOT_SET: set eight verified labels or indices in neck_qc.";
                elseif isempty(q.channelLabels) && n~=q.expectedChannelCount
                    base(k).Status="NOT_ASSESSED";
                    base(k).Notes=string(sprintf('CHANNEL_COUNT_MISMATCH: actual %d, expected %d; index mapping disabled to avoid shifted columns.',n,q.expectedChannelCount));
                elseif indices(k)==-1
                    base(k).Status="NOT_ASSESSED"; base(k).Notes="Duplicate matching channel labels.";
                elseif isnan(indices(k)) || indices(k)>n
                    base(k).Status="MISSING_CHANNEL"; base(k).Notes="Expected channel absent.";
                else
                    c=indices(k); base(k).Channel=c; base(k).Label=labels(c); base(k).Unit=units(c);
                    base(k)=assess(base(k),double(x(c,:)),t,q);
                end
            end
            end % mapping mode
            for kk=1:8
                base(kk).OriginalUnit=base(kk).Unit;
                if isfinite(base(kk).Channel) && strlength(string(q.confirmedEMGUnit))>0
                    base(kk).Unit=string(q.confirmedEMGUnit);
                    base(kk).UnitSource="User-confirmed input unit; label override only; no scaling";
                end
            end
            [walkBase,walk]=assessWalking(base,x,t,walk,q);
            fprintf('  WALKING | %s | %s\n',walk.Status,walk.Notes);
            if walk.Status=="SELECTED"
                fprintf('  %s: %.6f to %.6f (shared XDF seconds), %d samples\n',...
                    walk.MarkerStream,walk.StartTime_s,walk.EndTime_s,walk.SelectedSamples);
            end
            try
                if walk.Status=="SELECTED" && any(isfinite([walkBase.Channel]))
                    mask=t>=walk.StartTime_s & t<=walk.EndTime_s;
                    plotChannels(x(:,mask),t(mask),walkBase,fullfile(out,sprintf('%04d_walking_neck.png',f)),files(f).name);
                end
            catch plotErr
                fprintf(fid,'WALKING_PLOT_ERROR %s: %s\n',path,plotErr.message);
            end
            try
                if any(isfinite([base.Channel]))
                plotChannels(x,t,base,fullfile(out,sprintf('%04d_raw_neck.png',f)),files(f).name);
                end
            catch plotErr
                fprintf(2,'Plot failed: %s\n',plotErr.message);
                fprintf(fid,'PLOT_ERROR %s: %s\n',path,plotErr.message);
            end
        end
    catch err
        base=setStatus(base,'ERROR',err.message);
    end
    if isempty(walkBase)
        walkBase=base;
        for kk=1:8
            walkBase(kk)=resetMetrics(walkBase(kk));
            walkBase(kk).Scope="walking";
            walkBase(kk).Status="NOT_ASSESSED";
            walkBase(kk).Notes="Walking assessment unavailable: "+walk.Notes;
        end
    end
    for kk=1:8
        base(kk).ChannelStatus=base(kk).Status;
        walkBase(kk).ChannelStatus=walkBase(kk).Status;
    end
    walkingRows=[walkingRows;walkBase]; %#ok<AGROW>
    walkingIntervals{end+1}=walk; %#ok<AGROW>
    walkingReport=struct2table(walkingRows);
    walkingTable=struct2table(vertcat(walkingIntervals{:}));
    writeDerivativeTable(walkingReport,fullfile(out,'walking_neck_channel_qc.tsv'));
    writeDerivativeTable(walkingTable,fullfile(out,'walking_intervals.tsv'));
    if walk.Status~="SELECTED", fprintf(fid,'WALKING %s | %s | %s\n',path,walk.Status,walk.Notes); end
    rows=[rows;base]; %#ok<AGROW>
    sameMessage=all([base.Status]==base(1).Status) && all([base.Notes]==base(1).Notes);
    for k=1:8
        if base(k).Status~="AUTO_PASS"
            msg=sprintf('%s | %s / run-%s | Neck%02d | %s',base(k).Status,selected.Session(f),selected.Run(f),k,base(k).Notes);
            if ~sameMessage || k==1
                if sameMessage, msg=[msg ' (applies to all 8 neck slots)']; end
                if base(k).Status=="NOT_ASSESSED", fprintf('%s\n',msg);
                else, fprintf(2,'%s\n',msg); end
            end
            fprintf(fid,'%s\n',msg);
        end
    end
    % Checkpoint after every file, so missing-channel results survive later errors.
    report=struct2table(rows);
    writeDerivativeTable(report,fullfile(out,'neck_channel_qc.tsv'));
    writeDerivativeTable(report(:,{'Session','Run','NeckSlot','SensorID','SensorType','OutputOrdinal',...
        'PlacementFromInfo','Channel','Label','MappingEvidence','Status','Notes'}),...
        fullfile(out,'neck_id_mapping.tsv'));
    if ~isempty(inventory), writeDerivativeTable(struct2table(inventory),fullfile(out,'stream_inventory.tsv')); end
end
missing=report(startsWith(report.Status,'MISSING'),:);
writeDerivativeTable(missing,fullfile(out,'missing_channels.tsv'));
sessionFiles=unique(report.File,'stable');
summary=table(sessionFiles,'VariableNames',{'File'});
summary.Session=strings(height(summary),1); summary.Run=summary.Session;
for j=1:height(summary)
    first=find(report.File==summary.File(j),1);
    summary.Session(j)=report.Session(first); summary.Run(j)=report.Run(first);
end
states=["AUTO_PASS","REVIEW","UNUSABLE","MISSING_CHANNEL","MISSING_STREAM","NOT_ASSESSED","ERROR","EXCLUDED"];
for s=1:numel(states)
    counts=zeros(height(summary),1);
    for j=1:height(summary)
        counts(j)=sum(report.File==summary.File(j) & report.Status==states(s));
    end
    summary.(char(states(s)))=counts;
end
writeDerivativeTable(summary,fullfile(out,'session_summary.tsv'));
review=report; review.HumanDecision=repmat("",height(review),1);
review.Reviewer=repmat("",height(review),1); review.ReviewDate=repmat("",height(review),1);
review.ReviewComment=repmat("",height(review),1);
if ~isfile(fullfile(out,'human_review.tsv'))
    writeDerivativeTable(review,fullfile(out,'human_review.tsv'));
else
    warning('Existing human_review.tsv retained; reconcile it with the new audit.');
end
overview=makeOverview(report,summary);
writeDerivativeTable(overview,fullfile(out,'session_overview.tsv'),'Encoding','UTF-8');
writeDerivativeTable(overview(:,{'Session','Run','TimingStatus','BeforeBackward','AfterBackward',...
    'SynchronizationStatus','TimingNotes','File'}),fullfile(out,'session_timing_status.tsv'),'Encoding','UTF-8');
walkingSummary=summary;
for ss=1:numel(states)
    for jj=1:height(walkingSummary)
        walkingSummary.(char(states(ss)))(jj)=sum(walkingReport.File==walkingSummary.File(jj) & walkingReport.Status==states(ss));
    end
end
walkingOverview=makeOverview(walkingReport,walkingSummary);
walkingOverview.WalkingStatus=walkingTable.Status;
walkingOverview.WalkingNotes=walkingTable.Notes;
writeDerivativeTable(walkingOverview,fullfile(out,'walking_session_overview.tsv'),'Encoding','UTF-8');
walkingReview=walkingReport;
walkingReview.HumanDecision=repmat("",height(walkingReview),1);
walkingReview.Reviewer=repmat("",height(walkingReview),1);
walkingReview.ReviewDate=repmat("",height(walkingReview),1);
walkingReview.ReviewComment=repmat("",height(walkingReview),1);
if ~isfile(fullfile(out,'walking_human_review.tsv'))
    writeDerivativeTable(walkingReview,fullfile(out,'walking_human_review.tsv'));
else
    warning('Existing walking_human_review.tsv retained; reconcile it with the new audit.');
end
save(fullfile(out,'walking_qc.mat'),'walkingReport','walkingTable','walkingOverview','q');
fprintf('\n===== 步行区间汇总（不自动回退到全程）=====\n');
for jj=1:height(walkingTable)
    fprintf('%s | %s | %.3f s | Pass=%d Review=%d Bad=%d Pending=%d\n',...
        walkingTable.Session(jj),walkingTable.Status(jj),walkingTable.Duration_s(jj),...
        walkingOverview.AutoPass(jj),walkingOverview.Review(jj),walkingOverview.Unusable(jj),walkingOverview.Pending(jj));
end
save(fullfile(out,'neck_qc.mat'),'report','summary','overview','inventory','q','configFile','manifest','subjectMap','neckMap','timingRows');
showOverview(overview);
clear closer; % flush/close alerts before publishing
p3Sources=arrayfun(@(f)fullfile(f.folder,f.name),files,'UniformOutput',false);
directJSON(fullfile(out,'desc-neckQC_provenance.json'), ...
    struct('SourceFiles',{p3Sources},'Subject',subject_id,'Day',experiment_day,'Options',q));
fprintf('\nSaved: %s\nMissing-channel/stream rows: %d\n',out,height(missing));
fprintf('AUTO_PASS is provisional. Review PNGs and record decisions in human_review.tsv.\n');
% No output requested: do not flood the command window with an ans table.
if nargout>=1, varargout{1}=report; end
if nargout>=2, varargout{2}=overview; end
if nargout>=3, varargout{3}=walkingReport; end
if nargout>=4, varargout{4}=out; end
end

function r=blankRow()
r=struct('Scope',"full_recording",'OriginalUnit',"",'UnitSource',"XDF metadata",'Subject',"",'File',"",'Session',"",'Run',"",'NeckSlot',NaN,'SensorID',"",'SensorType',"",...
    'OutputOrdinal',NaN,'PlacementFromInfo',"",'MappingEvidence',"",'ExpectedLabel',"",'Stream',"",...
    'StreamChannels',NaN,'Channel',NaN,'Label',"",'Unit',"",'Samples',NaN,...
    'Duration_s',NaN,'MedianRate_Hz',NaN,'Nonfinite_pct',NaN,'Zero_pct',NaN,...
    'SD_native',NaN,'LongestFlat_s',NaN,'TimestampGaps',NaN,'MaxGap_s',NaN,...
    'Status',"NOT_ASSESSED",'ChannelStatus',"NOT_ASSESSED",'Notes',"",...
    'TimingStatus',"NOT_ASSESSED",'TimingNotes',"No unique EMG stream assessed.",...
    'BeforeBackward',NaN,'AfterBackward',NaN,'LongestFlat_samples',NaN,...
    'TimeBasedChecks',"NOT_ASSESSED",'SynchronizationStatus',"NOT_VALIDATED");
end
function q=defaultField(q,name,value)
if ~isfield(q,name), q.(name)=value; end
end
function r=setStatus(r,status,note)
for k=1:numel(r), r(k).Status=string(status); r(k).Notes=string(note); end
end
function v=asText(v)
while iscell(v)&&numel(v)==1, v=v{1}; end
if isempty(v), v=""; else, v=string(v); v=v(1); end
end
function v=infoText(st,key)
v=""; if isfield(st,'info')&&isfield(st.info,key), v=asText(st.info.(key)); end
end
function [labels,units,metadata]=channelMeta(st,n)
labels=repmat("",1,n); units=labels; metadata=repmat({struct},1,n);
try
    desc=st.info.desc; while iscell(desc), desc=desc{1}; end
    ch=desc.channels; while iscell(ch), ch=ch{1}; end
    ch=ch.channel;
    for k=1:min(n,numel(ch))
        if iscell(ch), item=ch{k}; else, item=ch(k); end
        metadata{k}=item;
        if isfield(item,'label'), labels(k)=asText(item.label); end
        if isfield(item,'unit'), units(k)=asText(item.unit); end
    end
catch
    % Missing metadata stays empty: never fabricate a label or unit.
end
end
function r=assess(r,x,t,q)
% Signal integrity is evaluated even if the time axis cannot be used.
x=double(x(:)'); t=double(t(:));
r.Samples=numel(x); r.Nonfinite_pct=100*mean(~isfinite(x));
r.Zero_pct=100*mean(x==0); good=x(isfinite(x)); notes=strings(0,1);
if numel(good)>=2, r.SD_native=std(good); end
validTime=numel(t)==numel(x) && numel(t)>=2 && ...
    all(isfinite(t)) && all(diff(t)>0);
if validTime
    dt=diff(t); step=median(dt);
    r.Duration_s=t(end)-t(1); r.MedianRate_Hz=1/step;
    r.TimestampGaps=sum(dt>q.gapFactor*step); r.MaxGap_s=max(dt);
    r.TimeBasedChecks="COMPLETED_AFTER_DEJITTER";
else
    r.TimeBasedChecks="NOT_ASSESSED_INVALID_TIME_AXIS";
    notes(end+1)="Time-based checks pending; see TimingStatus (amplitude checks still performed)";
end
% Repeated-value runs remain inspectable in sample units without valid time.
eq=diff(x)==0 & isfinite(x(1:end-1)) & isfinite(x(2:end));
if validTime, eq=eq & (dt'<=q.gapFactor*step); end
bounds=diff([false eq false]); a=find(bounds==1); b=find(bounds==-1);
if isempty(a)
    r.LongestFlat_samples=0;
    if validTime, r.LongestFlat_s=0; end
else
    r.LongestFlat_samples=max(b-a+1);
    if validTime, r.LongestFlat_s=max(t(b)-t(a)); end
end
if numel(good)<2 || max(good)==min(good)
    r.Status="UNUSABLE";
    r.Notes="No usable variation: empty, insufficient finite samples, all-zero or constant signal.";
    return;
end
if r.Nonfinite_pct>0, notes(end+1)="Nonfinite signal samples"; end
if validTime
    if r.LongestFlat_s>=q.flatSeconds
        notes(end+1)="Long identical-value stretch (review rest/dropout)";
    end
    if r.Duration_s<5, notes(end+1)="Recording shorter than 5 seconds"; end
end
% Gaps and timestamp irregularity are reported separately in TimingStatus.
if isempty(notes)
    r.Status="AUTO_PASS";
    r.Notes="Basic signal checks passed; visual/anatomical review still required. TimingStatus is separate; EEG synchronization not validated.";
else
    r.Status="REVIEW"; r.Notes=strjoin(notes,'; ');
end
end
function plotChannels(x,t,rows,file,titleText)
f=figure('Visible','off','Color','w','Position',[30 30 1400 1100]);
cleanup=onCleanup(@() close(f)); %#ok<NASGU>
for k=1:8
    subplot(4,2,k); c=rows(k).Channel;
    if isfinite(c) && size(x,2)>1
        y=double(x(c,:));
        if numel(t)~=numel(y) || any(~isfinite(t)) || any(diff(t)<=0)
            tt=(1:numel(y))'; xLabel='Sample index (timestamp issue; NOT seconds)';
        else
            tt=t-t(1); xLabel='Dejittered time from first sample (s)';
        end
        % Min/max per block preserves brief spikes (unlike simple subsampling).
        edges=unique(round(linspace(1,numel(y)+1,min(2000,numel(y))+1)));
        px=nan(1,2*(numel(edges)-1)); py=px;
        for j=1:numel(edges)-1
            idx=edges(j):edges(j+1)-1;
            if any(~isfinite(y(idx))) || any(~isfinite(tt(idx))), continue; end
            [lo,il]=min(y(idx)); [hi,ih]=max(y(idx));
            [positions,ord]=sort([idx(il) idx(ih)]); vals=[lo hi];
            px(2*j-1:2*j)=tt(positions); py(2*j-1:2*j)=vals(ord);
        end
        plot(px,py,'Color',[0.15 0.3 0.65]); xlabel(xLabel);
        unit=rows(k).Unit; if strlength(unit)==0, unit="native unit (unspecified)"; end
        ylabel(unit,'Interpreter','none');
    else
        text(0.05,0.5,rows(k).Notes,'Units','normalized','Interpreter','none'); axis off;
    end
    title(sprintf('Neck%02d | %s | %s',k,rows(k).Label,rows(k).Status),'Interpreter','none');
end
sgtitle(sprintf('%s | %s | inspect timing flags in CSV',titleText,rows(1).Scope),'Interpreter','none');
exportgraphics(f,file,'Resolution',150);
end

function [files,manifest]=selectFiles(files,q)
% Session groups use the actual ses-* directory where available. Never cap
% the file list at eight: multiple runs or duplicates must remain visible.
[~,order]=sort(string(fullfile({files.folder},{files.name}))); files=files(order);
N=numel(files); File=strings(N,1); Session=File; Run=File; SessionKey=File;
Selected=true(N,1); Reason=repmat("included",N,1);
keywords=string(q.excludedSessionKeywords); keywords=keywords(strlength(keywords)>0);
for i=1:N
    File(i)=string(fullfile(files(i).folder,files(i).name));
    normalized=strrep(char(File(i)),'\','/');
    % Prefer the folder name: condition labels may themselves contain '_'.
    [~,b,tokens]=regexp(normalized,'(?:^|/)ses-([^/]+)(?=/)','start','end','tokens');
    if ~isempty(tokens)
        Session(i)=string(tokens{end}{1});
        SessionKey(i)=string(normalized(1:b(end)));
    else
        tok=regexp(files(i).name,'(?:^|_)ses-(.*?)(?=_(?:task|run|acq|desc)-|\.xdf$)','tokens','once');
        if isempty(tok), Session(i)="UNKNOWN"; else, Session(i)=string(tok{1}); end
        SessionKey(i)=string(files(i).folder)+"/ses-"+Session(i);
    end
    tok=regexp(files(i).name,'(?:^|_)run-([^_.]+)','tokens','once');
    if isempty(tok), Run(i)="UNKNOWN"; else, Run(i)=string(tok{1}); end
    % Match within scanRoot, avoiding exclusion due to an ancestor lab name.
    relative=extractAfter(File(i),strlength(string(q.scanRoot)));
    if contains(files(i).name,'old','IgnoreCase',true)
        Selected(i)=false; Reason(i)="filename contains old";
        fprintf('Skipping OLD XDF (not loaded): %s\n',files(i).name);
    elseif ~isempty(keywords) && any(contains(relative,keywords,'IgnoreCase',true))
        Selected(i)=false; Reason(i)="calibration/setup keyword";
    elseif ~isempty(q.excludeRegex) && ~isempty(regexp(char(relative),q.excludeRegex,'once'))
        Selected(i)=false; Reason(i)="excludeRegex";
    elseif ~isempty(q.sessionFilter) && ~contains(Session(i),q.sessionFilter,'IgnoreCase',true)
        Selected(i)=false; Reason(i)="sessionFilter";
    elseif ~isempty(q.runFilter) && Run(i)~=string(q.runFilter)
        Selected(i)=false; Reason(i)="runFilter (or missing run label)";
    end
end
manifest=table(File,Session,Run,SessionKey,Selected,Reason);
files=files(Selected);
end

function overview=makeOverview(report,summary)
% One row per XDF: repeated runs/copies are NOT collapsed into one session.
N=height(summary);
overview=table((1:N)',summary.Session,summary.Run,'VariableNames',{'Record','Session','Run'});
overview.EMGChannels=strings(N,1);
overview.Assessed=zeros(N,1); overview.AutoPass=summary.AUTO_PASS;
overview.Review=summary.REVIEW; overview.Unusable=summary.UNUSABLE;
overview.Missing=summary.MISSING_CHANNEL+summary.MISSING_STREAM;
overview.Pending=summary.NOT_ASSESSED+summary.ERROR+summary.EXCLUDED;
overview.Conclusion=strings(N,1); overview.NextStep=strings(N,1);
overview.TimingStatus=strings(N,1); overview.TimingNotes=strings(N,1);
overview.BeforeBackward=nan(N,1); overview.AfterBackward=nan(N,1);
overview.SynchronizationStatus=repmat("NOT_VALIDATED",N,1);
for j=1:N
    r=report(report.File==summary.File(j),:);
    overview.TimingStatus(j)=r.TimingStatus(1);
    overview.TimingNotes(j)=r.TimingNotes(1);
    overview.BeforeBackward(j)=r.BeforeBackward(1); overview.AfterBackward(j)=r.AfterBackward(1);
    n=unique(r.StreamChannels(isfinite(r.StreamChannels)));
    if isempty(n), overview.EMGChannels(j)="未确定";
    else, overview.EMGChannels(j)=strjoin(string(n),'/'); end
    overview.Assessed(j)=sum(ismember(r.Status,["AUTO_PASS","REVIEW","UNUSABLE"]));
    if any(startsWith(r.Status,'MISSING'))
        overview.Conclusion(j)="缺失报警"; overview.NextStep(j)="核对流名/标签及采集记录，确认后报告缺失";
    elseif any(r.Status=="ERROR")
        overview.Conclusion(j)="读取或检查出错"; overview.NextStep(j)="查看 alerts.txt 中的错误";
    elseif any(contains(r.Notes,'MAPPING_NOT_SET'))
        overview.Conclusion(j)="未设置颈部映射"; overview.NextStep(j)="在配置中填写8个已核实的通道标签或编号";
    elseif any(contains(r.Notes,'CHANNEL_COUNT_MISMATCH'))
        overview.Conclusion(j)="总通道数不符"; overview.NextStep(j)="核对实际通道数和通道顺序";
    elseif any(contains(r.Notes,'ID_METADATA'))
        overview.Conclusion(j)="ID元数据不足或冲突"; overview.NextStep(j)="查看 neck_id_mapping.tsv 和 stream_inventory.tsv，不能据此断言传感器缺失";
    elseif any(contains(r.Notes,'TIMESTAMP_CHECK_REQUIRED'))
        overview.Conclusion(j)="共享时间轴需核查"; overview.NextStep(j)="查看 timestamp_diagnostics.tsv；不能据此判定8路EMG都坏了";
    elseif any(r.Status=="NOT_ASSESSED")
        overview.Conclusion(j)="尚未完成评估"; overview.NextStep(j)="查看详细表 Notes 和通道清单";
    elseif any(r.Status=="UNUSABLE")
        overview.Conclusion(j)="存在不可用通道"; overview.NextStep(j)="查看对应波形，记录人工判定";
    elseif any(r.Status=="REVIEW")
        overview.Conclusion(j)="存在待复核通道"; overview.NextStep(j)="查看平线/断流等标记和波形";
    elseif all(r.Status=="AUTO_PASS")
        overview.Conclusion(j)="自动初检通过"; overview.NextStep(j)="仍需人工确认波形及传感器位置";
    else
        overview.Conclusion(j)="未评估"; overview.NextStep(j)="查看详细表";
    end
end
overview.File=summary.File; % Keep traceability in the file, not the console.
end
function showOverview(t)
fprintf('\n===== 颈部EMG检查汇总（每个XDF/run一行）=====\n');
fprintf('%-3s %-20s %-5s %-6s %-8s %-5s %-5s %-5s %-5s %-7s\n',...
    '#','Session','Run','EMGch','Assessed','Pass','Review','Bad','Miss','Pending');
for j=1:height(t)
    fprintf('%-3d %-20s %-5s %-6s %d/8      %-5d %-5d %-5d %-5d %-7d\n',...
        t.Record(j),t.Session(j),t.Run(j),t.EMGChannels(j),t.Assessed(j),...
        t.AutoPass(j),t.Review(j),t.Unusable(j),t.Missing(j),t.Pending(j));
end
fprintf('EMGch=流内总通道数；Assessed=已检查的颈部通道数/8。\n');
fprintf('Pass=自动初检通过；Review=待复核；Bad=不可用；Miss=缺失；Pending=未评估/出错。\n');
fprintf('Pass+Review+Bad=Assessed；这三项与Miss、Pending合计为8。\n\n');
% Shared conclusions are printed once; session-specific problems stay visible.
conclusions=unique(t.Conclusion,'stable');
for k=1:numel(conclusions)
    mask=t.Conclusion==conclusions(k); first=find(mask,1);
    names=t.Session(mask)+"/run-"+t.Run(mask);
    fprintf('%s：%s\n',conclusions(k),strjoin(names,', '));
    fprintf('  下一步：%s\n',t.NextStep(first));
end
fprintf('\n===== 共享时间轴（与通道状态分开）=====\n');
for j=1:height(t)
    fprintf('%s / run-%s | %s | backward %g -> %g\n',...
        t.Session(j),t.Run(j),t.TimingStatus(j),t.BeforeBackward(j),t.AfterBackward(j));
end
fprintf('时间轴状态不代表EEG同步已验证；信号Pass也不代表可直接计算CMC。\n');
fprintf('详细指标：neck_channel_qc.tsv；易读汇总：session_overview.tsv；时间轴：session_timing_status.tsv。\n');
end

function map=readSubjectInfo(infoFile)
% Execute in an isolated workspace and require the table belonging to this file.
[~,stem]=fileparts(infoFile); tableName=regexprep(stem,'_infos$','');
assert(isvarname(tableName),'Invalid subject-info filename.');
run(infoFile);
assert(exist(tableName,'var')==1,'Expected subject table is missing from info file.');
map=eval(tableName);
assert(istable(map) && all(ismember({'SensorID','MuscleName','SensorType'},map.Properties.VariableNames)),...
    'Subject info must contain SensorID, MuscleName, SensorType.');
assert(height(map)>=5,'Subject info has fewer than five sensors.');
map.SensorID=string(map.SensorID); map.SensorType=string(map.SensorType);
map.MuscleName=string(map.MuscleName);
assert(numel(unique(map.SensorID))==height(map),'Repeated sensor DEC IDs in subject info.');
for j=1:height(map)
    assert(~isempty(regexp(char(map.SensorID(j)),'^[0-9]+$','once')), ...
        'SensorID must be a decimal hardware ID.');
end
end
function neck=expandNeckSensors(map)
% The user's confirmed convention: last five physical sensors are neck units.
last=map(end-4:end,:); rows=struct('SensorID',{},'SensorType',{},'OutputOrdinal',{},'PlacementFromInfo',{});
for j=1:5
    if strcmpi(last.SensorType(j),'AvantiSensor'), count=1;
    elseif strcmpi(last.SensorType(j),'DuoSensor'), count=2;
    else, error('Unknown sensor type for DEC %s.',last.SensorID(j)); end
    for k=1:count
        rows(end+1)=struct('SensorID',last.SensorID(j),'SensorType',last.SensorType(j),...
            'OutputOrdinal',k,'PlacementFromInfo',last.MuscleName(j)); %#ok<AGROW>
    end
end
neck=struct2table(rows);
assert(height(neck)==8,'Last five sensors do not expand to eight EMG outputs. Check sensor types.');
end
function rows=assessBySensorID(rows,x,t,labels,units,metadata,allSensors,neck,q)
% Read only per-channel metadata. Never use a stream-wide list to infer order.
n=size(x,1); ids=repmat("",1,n); evidence=ids;
for c=1:n
    textFields=idText(metadata{c},'');
    hits=strings(0,1);
    for j=1:height(allSensors)
        id=allSensors.SensorID(j);
        % Decimal boundaries avoid matching 88658 inside 1886580.
        pattern=['(?<![0-9])' char(id) '(?![0-9])'];
        if any(~cellfun(@isempty,regexp(cellstr(textFields),pattern,'once')))
            hits(end+1)=id; %#ok<AGROW>
        end
    end
    if numel(hits)==1
        ids(c)=hits(1); evidence(c)=strjoin(textFields,' | ');
    elseif numel(hits)>1
        ids(c)="CONFLICT";
    end
end
% Unidentified channels could contain an apparently missing output; do not
% label it missing unless all observed columns have unambiguous known IDs.
completeIDMetadata=all(strlength(ids)>0 & ids~="CONFLICT");
for j=1:5
    target=unique(neck.SensorID,'stable'); id=target(j);
    slots=find(neck.SensorID==id); found=find(ids==id); expected=numel(slots);
    fprintf('  DEC %s | expected %d | matched columns: %s\n',id,expected,mat2str(found));
    for a=1:expected
        k=slots(a); rows(k).StreamChannels=n;
        if numel(found)>expected
            rows(k).Status="NOT_ASSESSED";
            rows(k).Notes="ID_METADATA_AMBIGUOUS: too many outputs with this sensor ID.";
        elseif a<=numel(found)
            c=found(a); rows(k).Channel=c; rows(k).Label=labels(c); rows(k).Unit=units(c);
            rows(k).MappingEvidence=evidence(c);
            rows(k)=assess(rows(k),double(x(c,:)),t,q);
            if expected==2
                rows(k).Notes=rows(k).Notes+" OutputOrdinal is matched-column order, not verified hardware CH1/CH2 or anatomy.";
            end
        elseif completeIDMetadata
            rows(k).Status="MISSING_CHANNEL";
            rows(k).Notes=string(sprintf('DEC %s: expected %d outputs, found %d. Missing output identity within Duo may be unknown.',id,expected,numel(found)));
        else
            rows(k).Status="NOT_ASSESSED";
            rows(k).Notes="ID_METADATA_INCOMPLETE: unresolved columns could contain this output; inspect inventory/metadata.";
        end
    end
end
end
function values=idText(node,key)
% Supported metadata: channel label/name or explicit sensor serial/DEC fields.
% Other leaves (units, sampling rates, channel-number fields) are excluded.
values=strings(0,1);
if iscell(node)
    for j=1:numel(node), values=[values;idText(node{j},key)]; end %#ok<AGROW>
elseif isstruct(node)
    fields=fieldnames(node);
    for a=1:numel(node)
        for j=1:numel(fields)
            values=[values;idText(node(a).(fields{j}),fields{j})]; %#ok<AGROW>
        end
    end
else
    normalized=lower(regexprep(key,'[^a-zA-Z0-9]',''));
    allowed={'label','name','sensorid','sensordecid','decid','serial','serialnumber','sensorserial','sensorserialnumber'};
    if ismember(normalized,allowed) && (ischar(node)||isstring(node)||isnumeric(node))
        v=string(node); values=v(:); values=values(strlength(values)>0);
    end
end
end

function d=timingDiagnostic(t,samples,nominal,session,runLabel,path,out,fileIndex,stage)
% Diagnose the imported shared time axis without sorting, deleting samples,
% interpolating, resampling, or silently enabling timestamp dejittering.
t=t(:); dt=diff(t); valid=isfinite(t); positive=dt(isfinite(dt)&dt>0);
d=struct('Stage',string(stage),'Session',session,'Run',runLabel,'SignalSamples',samples,...
    'TimestampCount',numel(t),'CountMatches',samples==numel(t),...
    'NonfiniteTimestamps',sum(~valid),'AdjacentDuplicatePairs',sum(dt==0),...
    'BackwardIntervals',sum(dt<0),'NominalRate_Hz',str2double(nominal),...
    'FirstTimestamp',NaN,'LastTimestamp',NaN,'MinDelta_s',NaN,...
    'MaxDelta_s',NaN,'MedianPositiveDelta_s',NaN,'File',string(path));
if ~isempty(t), d.FirstTimestamp=t(1); d.LastTimestamp=t(end); end
finiteDt=dt(isfinite(dt));
if ~isempty(finiteDt), d.MinDelta_s=min(finiteDt); d.MaxDelta_s=max(finiteDt); end
if ~isempty(positive), d.MedianPositiveDelta_s=median(positive); end
fprintf('  TIMING %s | samples=%d | timestamps=%d | nonfinite=%d | adjacent duplicates=%d | backward=%d\n',...
    stage,samples,numel(t),d.NonfiniteTimestamps,d.AdjacentDuplicatePairs,d.BackwardIntervals);
% Save the first twenty examples of each anomaly class, with indices and values.
examples=struct('Kind',{},'SampleIndex',{},'PreviousTimestamp',{},'Timestamp',{},'Delta_s',{});
groups={find(~valid),find(dt==0)+1,find(dt<0)+1};
kinds=["NONFINITE","DUPLICATE","BACKWARD"];
for g=1:3
    indices=groups{g}; indices=indices(1:min(20,numel(indices)));
    for a=1:numel(indices)
        k=indices(a); prev=NaN; delta=NaN;
        if k>1, prev=t(k-1); delta=t(k)-prev; end
        examples(end+1)=struct('Kind',kinds(g),'SampleIndex',k,...
            'PreviousTimestamp',prev,'Timestamp',t(k),'Delta_s',delta); %#ok<AGROW>
    end
end
if ~isempty(examples)
    writeDerivativeTable(struct2table(examples),fullfile(out,sprintf('%04d_%s_timestamp_examples.tsv',fileIndex,stage)));
end
end

function [tAfter,status,note,p,walk]=compareTimeAxes(before,path,out,fileIndex,session,runLabel,q)
% "Before" means before dejittering, NOT untouched device timestamps:
% clock synchronization is explicitly enabled for BOTH imports.
% No ordering, interpolation or sample deletion is performed by this script.
walk=blankWalking(); walk.File=string(path); walk.Session=session; walk.Run=runLabel;
tBefore=double(before.time_stamps(:)); tAfter=[]; timeCorrection_s=[];
segmentsBefore=[]; segmentsAfter=[];
if isfield(before,'segments'), segmentsBefore=before.segments; end
nSamples=size(before.time_series,2); nominal=infoText(before,'nominal_srate');
dBefore=timingDiagnostic(tBefore,nSamples,nominal,session,runLabel,path,out,fileIndex,'before');
dAfter=dBefore; dAfter.Stage="after";
numFields={'SignalSamples','TimestampCount','NonfiniteTimestamps','AdjacentDuplicatePairs',...
    'BackwardIntervals','FirstTimestamp','LastTimestamp','MinDelta_s','MaxDelta_s','MedianPositiveDelta_s'};
for j=1:numel(numFields), dAfter.(numFields{j})=NaN; end
dAfter.CountMatches=false;
status="NOT_ASSESSED"; note="After-dejitter import not completed.";
p=struct('Session',session,'Run',runLabel,'TimingStatus',status,...
    'BeforeSamples',nSamples,'AfterSamples',NaN,'BeforeCount',numel(tBefore),'AfterCount',NaN,...
    'BeforeBackward',dBefore.BackwardIntervals,'AfterBackward',NaN,...
    'BeforeNonfinite',dBefore.NonfiniteTimestamps,'AfterNonfinite',NaN,...
    'BeforeDuplicates',dBefore.AdjacentDuplicatePairs,'AfterDuplicates',NaN,...
    'BeforeMinDelta_ms',dBefore.MinDelta_s*1000,'AfterMinDelta_ms',NaN,...
    'SignalIdentical',false,'AfterDuration_s',NaN,'AfterRate_Hz',NaN,...
    'AfterGaps',NaN,'AfterMaxGap_ms',NaN,'AfterIrregularIntervals',NaN,...
    'CorrectionMedian_ms',NaN,'CorrectionP95Abs_ms',NaN,'CorrectionMaxAbs_ms',NaN,...
    'CorrectionFirst_ms',NaN,'CorrectionLast_ms',NaN,...
    'SynchronizationStatus',"NOT_VALIDATED",'Notes',note,'File',string(path));
axesFile=fullfile(out,sprintf('%04d_time_axes.mat',fileIndex));
diagnosticFile=fullfile(out,sprintf('%04d_timestamp_diagnostics.tsv',fileIndex));
importSettings=struct('HandleClockSynchronization',true,...
    'BeforeHandleJitterRemoval',false,'AfterHandleJitterRemoval',true,...
    'LoadXdfPath',q.loadXdfPath,'StreamName',infoText(before,'name'));
% Save evidence before the second import; preserve diagnostics if it fails.
save(axesFile,'tBefore','segmentsBefore','importSettings','path');
writeDerivativeTable(struct2table(dBefore),diagnosticFile);
try
    afterStreams=load_xdf(path,'HandleClockSynchronization',true,'HandleJitterRemoval',true);
    if ~iscell(afterStreams), afterStreams=num2cell(afterStreams); end
    name=infoText(before,'name'); typ=infoText(before,'type'); matches=[];
    for j=1:numel(afterStreams)
        if infoText(afterStreams{j},'name')==name && infoText(afterStreams{j},'type')==typ
            matches(end+1)=j; %#ok<AGROW>
        end
    end
    assert(isscalar(matches),'Second import does not contain a unique matching EMG stream.');
    after=afterStreams{matches};
    try
        walk=selectWalking(afterStreams,walk,q,out,fileIndex);
    catch markerErr
        walk.Status="MARKER_PARSE_ERROR"; walk.Notes=string(markerErr.message);
    end
    clear afterStreams;
    tAfter=double(after.time_stamps(:));
    if isfield(after,'segments'), segmentsAfter=after.segments; end
    p.SignalIdentical=isequaln(before.time_series,after.time_series);
    p.AfterSamples=size(after.time_series,2); p.AfterCount=numel(tAfter);
    dAfter=timingDiagnostic(tAfter,p.AfterSamples,nominal,session,runLabel,path,out,fileIndex,'after');
    p.AfterBackward=dAfter.BackwardIntervals; p.AfterNonfinite=dAfter.NonfiniteTimestamps;
    p.AfterDuplicates=dAfter.AdjacentDuplicatePairs; p.AfterMinDelta_ms=dAfter.MinDelta_s*1000;
    if numel(tBefore)==numel(tAfter)
        timeCorrection_s=tAfter-tBefore;
        finiteCorrection=timeCorrection_s(isfinite(timeCorrection_s));
        if ~isempty(finiteCorrection)
            absSorted=sort(abs(finiteCorrection));
            p.CorrectionMedian_ms=median(finiteCorrection)*1000;
            p.CorrectionP95Abs_ms=absSorted(max(1,ceil(0.95*numel(absSorted))))*1000;
            p.CorrectionMaxAbs_ms=max(absSorted)*1000;
        end
        if ~isempty(timeCorrection_s)
            p.CorrectionFirst_ms=timeCorrection_s(1)*1000;
            p.CorrectionLast_ms=timeCorrection_s(end)*1000;
        end
    end
    validAfter=p.SignalIdentical && dAfter.CountMatches && numel(tAfter)>=2 && ...
        all(isfinite(tAfter)) && all(diff(tAfter)>0);
    if ~validAfter
        status="INVALID_AFTER_DEJITTER";
        note="After axis invalid or signal/sample correspondence changed; time-based channel checks withheld. Inspect diagnostics.";
    else
        dt=diff(tAfter); step=median(dt);
        p.AfterDuration_s=tAfter(end)-tAfter(1); p.AfterRate_Hz=1/step;
        p.AfterGaps=sum(dt>q.gapFactor*step); p.AfterMaxGap_ms=max(dt)*1000;
        p.AfterIrregularIntervals=sum(abs(dt-step)>0.2*step);
        beforeNeedsReview=~dBefore.CountMatches || dBefore.NonfiniteTimestamps>0 || ...
            dBefore.AdjacentDuplicatePairs>0 || dBefore.BackwardIntervals>0;
        if p.AfterGaps>0 || p.AfterIrregularIntervals>0
            status="REVIEW_AFTER_DEJITTER";
            note="After axis monotonic but has gaps/irregular intervals. Inspect segments and time axes; EEG synchronization not validated.";
        elseif beforeNeedsReview
            status="REVIEW_CORRECTED";
            note="Before axis flagged; after axis monotonic with identical signal values/order. Duration checks allowed; inspect timing corrections. EEG synchronization not validated.";
        else
            status="MONOTONIC_AFTER_DEJITTER";
            note="After axis passes basic checks with identical signal values/order; this does not validate EEG synchronization or absence of dropouts.";
        end
    end
catch err
    validAfter=false;
    walk.Status="AFTER_IMPORT_ERROR"; walk.Notes=string(err.message);
    status="AFTER_IMPORT_ERROR";
    note="Second import/comparison failed: "+string(err.message)+". Amplitude checks continue using first-import signal.";
end
p.TimingStatus=status; p.Notes=note;
% Full before/after axes and elementwise correction retained for later review.
save(axesFile,'tBefore','tAfter','timeCorrection_s','segmentsBefore','segmentsAfter',...
    'importSettings','path','p','-v7.3');
writeDerivativeTable(struct2table([dBefore;dAfter]),diagnosticFile);
if ~validAfter, tAfter=[]; end % no fabricated times for channel duration checks
end

function w=blankWalking()
w=struct('File',"",'Session',"",'Run',"",'Status',"NOT_ASSESSED",...
    'MarkerStream',"",'StartLabel',"",'EndLabel',"",'StartEventIndex',NaN,'EndEventIndex',NaN,...
    'StartTime_s',NaN,'EndTime_s',NaN,'Duration_s',NaN,'SelectedSamples',0,...
    'FirstSampleIndex',NaN,'LastSampleIndex',NaN,'FirstSampleTime_s',NaN,'LastSampleTime_s',NaN,...
    'StartRelativeToEMG_s',NaN,'EndRelativeToEMG_s',NaN,...
    'TimeBasis',"XDF shared clock; clock synchronization ON; no per-stream zeroing",...
    'Rule',"Last complete matching non-standing Start/End pair; compare both marker streams",...
    'Notes',"No walking interval assessed.");
end

function w=selectWalking(streams,w,q,out,fileIndex)
% Recognize Start_trial/End_trial, START_<name>/END_<name>, Start/End,
% and <name>_Start/<name>_End, including Aquaplus_walking_Start/End.
% Condition keys must match. Unknown names stay in the inventory for review.
% Event order is preserved: never silently sort malformed marker timestamps.
streamNames=strings(numel(streams),1);
for j=1:numel(streams), streamNames(j)=strtrim(infoText(streams{j},'name')); end
selected=find(strcmpi(streamNames,'IMU_Markers') | strcmpi(streamNames,'GRF_Markers'));
if isempty(selected)
    w.Status="MISSING_MARKERS"; w.Notes="Neither IMU_Markers nor GRF_Markers found; no full-record fallback."; return;
end
inventory=struct('Stream',{},'EventIndex',{},'Label',{},'Timestamp_s',{});
pairs=struct('Stream',{},'StartIndex',{},'EndIndex',{},'StartLabel',{},'EndLabel',{},...
    'StartTime_s',{},'EndTime_s',{},'Standing',{},'SelectedWithinStream',{});
chosen=[]; problems=strings(0,1);
for si=selected(:)'
    st=streams{si}; name=streamNames(si); ts=double(st.time_stamps(:));
    labels=markerStrings(st.time_series);
    if numel(labels)~=numel(ts)
        problems(end+1)=name+": event/timestamp counts differ or marker stream is multichannel"; continue;
    end
    for j=1:numel(ts)
        inventory(end+1)=struct('Stream',name,'EventIndex',j,'Label',labels(j),'Timestamp_s',ts(j)); %#ok<AGROW>
    end
    if isempty(ts) || any(~isfinite(ts)) || any(diff(ts)<0)
        problems(end+1)=name+": empty/nonfinite/nonmonotonic marker times"; continue;
    end
    if sum(strcmpi(streamNames(selected),name))>1
        problems(end+1)=name+": duplicate named streams"; continue;
    end
    pending=0; pendingKey=""; candidates=[]; malformed=false;
    for j=1:numel(labels)
        textLabel=char(lower(strtrim(labels(j))));
        tok=regexp(textLabel,'^(start|end)(?:[\s_:\-]+(.*))?$','tokens','once');
        if isempty(tok)
            suffixTok=regexp(textLabel,'^(.+?)[\s_:\-]+(start|end)$','tokens','once');
            if ~isempty(suffixTok)
                tok={suffixTok{2},suffixTok{1}};
            end
        end
        if isempty(tok), continue; end
        key="";
        if numel(tok)>=2, key=string(regexprep(strtrim(tok{2}),'[\s_:\-]+','_')); end
        if strcmp(tok{1},'start')
            if pending~=0, malformed=true; end % nested/repeated start is ambiguous
            pending=j; pendingKey=key;
        else
            if pending==0 || key~=pendingKey || ts(j)<=ts(pending)
                malformed=true; pending=0; continue;
            end
            standing=contains(pendingKey,'standing') || contains(pendingKey,'standstill');
            % Standing labels inside a nominal walking pair also need review.
            inner=lower(labels(pending:j));
            standing=standing || any(contains(inner,'standing') | contains(inner,'standstill'));
            pairs(end+1)=struct('Stream',name,'StartIndex',pending,'EndIndex',j,...
                'StartLabel',labels(pending),'EndLabel',labels(j),'StartTime_s',ts(pending),...
                'EndTime_s',ts(j),'Standing',standing,'SelectedWithinStream',false); %#ok<AGROW>
            if ~standing, candidates(end+1)=numel(pairs); end %#ok<AGROW>
            pending=0;
        end
    end
    if pending~=0, malformed=true; end
    if malformed
        problems(end+1)=name+": unpaired, nested, mismatched or non-positive-duration Start/End events";
    elseif isempty(candidates)
        problems(end+1)=name+": no complete non-standing Start/End pair";
    else
        chosen(end+1)=candidates(end); %#ok<AGROW>
        pairs(candidates(end)).SelectedWithinStream=true;
    end
end
if ~isempty(inventory)
    writeDerivativeTable(struct2table(inventory),fullfile(out,sprintf('%04d_marker_inventory.tsv',fileIndex)));
end
if ~isempty(pairs)
    writeDerivativeTable(struct2table(pairs),fullfile(out,sprintf('%04d_marker_pairs.tsv',fileIndex)));
end
if ~isempty(problems)
    w.Status="MARKER_REVIEW_REQUIRED"; w.Notes=strjoin(problems,'; '); return;
end
if isempty(chosen)
    w.Status="NO_VALID_WALKING_PAIR"; w.Notes="No walking pair selected; no full-record fallback."; return;
end
c=pairs(chosen);
if numel(c)>1
    if max([c.StartTime_s])-min([c.StartTime_s])>q.markerAgreementTolerance_s || ...
            max([c.EndTime_s])-min([c.EndTime_s])>q.markerAgreementTolerance_s
        w.Status="MARKER_STREAM_CONFLICT";
        w.Notes="IMU_Markers and GRF_Markers selected different intervals; inspect marker_pairs.tsv."; return;
    end
end
% Both streams agree: choose IMU deterministically; otherwise use available one.
i=find(strcmpi([c.Stream],'IMU_Markers'),1); if isempty(i), i=1; end
c=c(i); w.MarkerStream=c.Stream; w.StartLabel=c.StartLabel; w.EndLabel=c.EndLabel;
w.StartEventIndex=c.StartIndex; w.EndEventIndex=c.EndIndex;
w.StartTime_s=c.StartTime_s; w.EndTime_s=c.EndTime_s;
w.Duration_s=w.EndTime_s-w.StartTime_s;
w.Status="MARKERS_SELECTED";
w.Notes="Last complete non-standing pair selected; EMG coverage check pending.";
end

function labels=markerStrings(data)
% Typical XDF marker data are 1xN cells; allow singleton-nested cells.
while iscell(data) && isscalar(data) && iscell(data{1}), data=data{1}; end
if iscell(data)
    labels=strings(numel(data),1);
    for j=1:numel(data)
        item=data{j};
        while iscell(item) && isscalar(item), item=item{1}; end
        if ~(ischar(item) || (isstring(item) && isscalar(item)))
            error('Marker event must be scalar text.');
        end
        labels(j)=string(item);
    end
elseif isstring(data)
    labels=data(:);
elseif ischar(data)
    labels=string(cellstr(data)); labels=labels(:);
else
    error('Unsupported marker payload; inspect stream time_series.');
end
end

function r=resetMetrics(r)
fields={'Samples','Duration_s','MedianRate_Hz','Nonfinite_pct','Zero_pct','SD_native',...
    'LongestFlat_s','LongestFlat_samples','TimestampGaps','MaxGap_s'};
for j=1:numel(fields), r.(fields{j})=NaN; end
r.TimeBasedChecks="NOT_ASSESSED";
end

function [rows,w]=assessWalking(base,x,t,w,q)
rows=base; t=t(:);
for k=1:numel(rows)
    rows(k)=resetMetrics(rows(k)); rows(k).Scope="walking";
end
if w.Status=="MARKERS_SELECTED"
    if numel(t)~=size(x,2) || numel(t)<2 || any(~isfinite(t)) || any(diff(t)<=0)
        w.Status="INVALID_EMG_TIME_AXIS"; w.Notes="Cannot select walking samples on invalid after-dejitter axis.";
    else
        step=median(diff(t));
        % Allow only the normal sub-sample endpoint offset. Do not silently
        % clip a materially incomplete walking interval to EMG coverage.
        if w.StartTime_s<t(1)-step || w.EndTime_s>t(end)+step
            w.Status="INCOMPLETE_EMG_COVERAGE";
            w.Notes="Marker interval extends beyond EMG coverage by more than one sample; no silent clipping.";
        else
            mask=t>=w.StartTime_s & t<=w.EndTime_s;
            idx=find(mask);
            if numel(idx)<2
                w.Status="TOO_FEW_WALKING_SAMPLES"; w.Notes="Fewer than two EMG samples in selected marker interval.";
            else
                w.Status="SELECTED"; w.SelectedSamples=numel(idx);
                w.FirstSampleIndex=idx(1); w.LastSampleIndex=idx(end);
                w.FirstSampleTime_s=t(idx(1)); w.LastSampleTime_s=t(idx(end));
                w.StartRelativeToEMG_s=w.StartTime_s-t(1); w.EndRelativeToEMG_s=w.EndTime_s-t(1);
                w.Notes="Marker-defined walking interval; shared XDF clock preserved. No waveform samples modified.";
            end
        end
    end
end
for k=1:numel(rows)
    if isfinite(rows(k).Channel) && w.Status=="SELECTED"
        rows(k)=assess(rows(k),double(x(rows(k).Channel,mask)),t(mask),q);
        if rows(k).SensorType=="DuoSensor"
            rows(k).Notes=rows(k).Notes+" OutputOrdinal is matched-column order; see original Label for hardware channel metadata.";
        end
    elseif startsWith(base(k).Status,"MISSING")
        rows(k).Status=base(k).Status; rows(k).Notes=base(k).Notes;
    else
        rows(k).Status="NOT_ASSESSED";
        if ~isfinite(rows(k).Channel), rows(k).Notes=base(k).Notes;
        else, rows(k).Notes="Walking interval unavailable: "+w.Status+". "+w.Notes; end
    end
end
end

function root=directDataset(container,pipeline)
% Final destination: no staging, restoration, copying or migration.
root=fullfile(char(container),'derivatives',char(pipeline));
if ~isfolder(root), mkdir(root); end
description=struct('Name',['PilotTest3 ' pipeline], ...
    'BIDSVersion','1.11.2','DatasetType','derivative', ...
    'GeneratedBy',{{struct('Name',pipeline)}});
directJSON(fullfile(root,'dataset_description.json'),description);
end

function directJSON(path,value)
fid=fopen(path,'w','n','UTF-8');
assert(fid>=0,'Cannot write: %s',path);
cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function id=directIdentity(source,cfg)
% Reversible source-label mapping is written into every export manifest.
source=char(source); [~,name,~]=fileparts(strrep(source,'\','/'));
s=regexp(name,'sub-(.*?)_ses-','tokens','once');
c=regexp(name,'_ses-(.*?)_task-','tokens','once');
r=regexp(name,'_run-(\d+)(?:_|$)','tokens','once');
t=regexp(name,'_task-([A-Za-z0-9]+)','tokens','once');
assert(~isempty(s)&&~isempty(c)&&~isempty(r),'Cannot identify source: %s',source);
sub=s{1};
assert(~isempty(regexp(sub,'^(?:Pilot3_\d+|Pilot3\d+|P3_\d+)$','once')), ...
    'PilotTest3 source required, got subject %s. PilotTest2 is excluded.',sub);
d=regexp(strrep(source,'\','/'),'(?:^|/)(day\d+)(?:/|$)','tokens','once');
if isempty(d)
    d=regexp(c{1},'^(day\d+)(?=[A-Z])','tokens','once');
end
if isempty(d)
    assert(isfield(cfg,'fallbackDay')&&~isempty(cfg.fallbackDay), ...
        'Experiment day missing from source path. Set cfg.fallbackDay explicitly: %s',source);
    day=char(cfg.fallbackDay);
else, day=d{1}; end
assert(~isempty(regexp(day,'^day\d+$','once')),'Day must be day1, day2, etc.');
condition=regexprep(c{1},['^' day],'');
if isempty(t), task='Default'; else, task=t{1}; end
id=struct('OriginalSubject',sub,'Subject',regexprep(sub,'[^A-Za-z0-9]',''), ...
    'Day',day,'OriginalSession',condition,'Session',[day regexprep(condition,'[^A-Za-z0-9]','')], ...
    'Task',task,'Run',sprintf('%03d',str2double(r{1})), 'SourceFile',source);
id.Prefix=sprintf('sub-%s_ses-%s_task-%s_run-%s',id.Subject,id.Session,id.Task,id.Run);
end

function writeDerivativeTable(T,path,varargin)
writetable(T,path,'FileType','text','Delimiter','\t',varargin{:});
end
