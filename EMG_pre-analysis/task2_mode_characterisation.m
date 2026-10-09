function outDir = task2_mode_characterisation(inputRoot,opt)
% TASK2_MODE_CHARACTERISATION v1.1.0 | MATLAB + EEGLAB
% Use existing 8-Hz linear ENVELOPES, not raw EMG or coherence inputs.
% Example:
  % opt = struct('subjects',"Pilot33",'runs',"001");
  % outDir = task2_mode_characterisation( ...
  % 'C:\2026SSArbeit\data\PilotTest3_BIDS\derivatives\p3emgprep\sub-Pilot33');
% No arguments: choose p3emgprep or its sub-Pilot33 folder.
% Empty subjects/runs means all discovered subjects/runs. No config_paths needed.
%
% Input: **/*_desc-Epoched_emg.set from load_emg_data_eeg_structure_V2.m.
% Uses original time in each RHS-to-RHS cycle; does NOT integrate warped time.
% Each epoch must contain HS_R at zero and HS_R->TO_L->HS_L->TO_R->HS_R.
% Prefers CleanEpochedWithEvents input (existing rejection retained); falls back
% to Epoched only if no clean sets found. Structural cycle QC always applied.
% Actual sensor IDs are metadata here, NEVER assumed to be channel row numbers.
% Match exact muscle labels produced by your Python BDF export instead.
%
% Primary metrics: per-cycle integral (native amplitude*s), envelope peak,
% and phase of envelope peak relative to ipsilateral heel strike (0..100%).
% Integral/peak: mean across retained cycles, /same subject+day+run baseline *100.
% Timing: circular mean of cycle peak phases; signed circular difference
% to baseline in percentage points (-50..50), NOT a timing ratio.
% This is peak activation timing, NOT EMG onset/offset detection.
% NoExoPre must be available in the same subject, day and run.
% Different runs are kept separate; do not pool repeated days into one run.
% Input amplitudes must be comparable across conditions (no per-condition scaling).
%
% opt fields (all optional): subjects, runs (string arrays); outputRoot (BIDS output container);
% durationRange [0.4 3] seconds; minCycles 10; rejectAmplitudeOutliers [];
% [] = false for CleanEpochedWithEvents, true for original Epoched inputs.
% amplitudeSD 3; minTimingResultant 0.2; envelopeConfirmed false;
% labelOverride strings(1,8) exact labels in order R VM RF BF GM, L VM RF BF GM.
% envelopeConfirmed is ONLY needed for legacy sets missing etc.is_envelope.
% Files with an explicit false envelope flag are always rejected.
% Outputs: ONE combined figure PNG/FIG, ONE summary TSV, cycle audit TSV,
% input audit TSV, protocol/caption TXT and MAT including individual curves.
% Direct input: select p3emgprep or one subject folder; no manifest needed.
% No inferential statistics; mode names do not demonstrate torque direction.

% 
if nargin < 1
    inputRoot = '';
end
if nargin < 2 || isempty(opt)
    opt = struct;
end

needInput = isempty(inputRoot);
needOutput = ~isfield(opt,'outputRoot') || ...
    strlength(string(opt.outputRoot)) == 0;

if needInput || needOutput
    
    scriptDir = fileparts(mfilename('fullpath'));
    configFile = fullfile(scriptDir,'config_paths.m');

    if ~isfile(configFile)
        configFile = which('config_paths.m');
    end

    assert(~isempty(configFile) && isfile(configFile), ...
        'config_paths.m not found; please place it next to the script or in the MATLAB path.');

    run(configFile);

    if needInput
        inputRoot = fullfile(bids_root,'derivatives', ...
            'p3emgprep',['sub-' bids_subject_id]);

    
        selectedDay = char(experiment_day);
        opt.runs = string(run_id);
    end

    if needOutput
        opt.outputRoot = bids_root;
    end
end

inputRoot = char(inputRoot);
derivativesContainer = char(opt.outputRoot);

fprintf('input of task 2：%s\n',inputRoot);
fprintf('BIDS root：%s\n',derivativesContainer);

D=struct('subjects',strings(0,1),'runs',strings(0,1),'outputRoot','', ...
    'durationRange',[0.4 3],'minCycles',10,'rejectAmplitudeOutliers',[], ...
    'amplitudeSD',3,'minTimingResultant',0.2,'envelopeConfirmed',false, ...
    'labelOverride',strings(1,8));
for f=fieldnames(opt)'
    assert(isfield(D,f{1}),'Unknown option: %s',f{1});
    D.(f{1})=opt.(f{1});
end
opt=D;
assert(exist('pop_loadset','file')==2,'Add EEGLAB to your MATLAB path first.');
assert(isfolder(inputRoot),'Input folder does not exist.');
assert(numel(opt.labelOverride)==8,'labelOverride must have eight entries.');
assert(numel(opt.durationRange)==2 && all(opt.durationRange>0) && diff(opt.durationRange)>0);
assert(opt.minCycles>=2 && opt.amplitudeSD>0);

% Restrict to 'day' when reading automatically; retain the original search method when manually passing 'inputRoot'.
if exist('selectedDay','var')
   
    sessionDirs = dir(fullfile(inputRoot,'ses-*'));
    sessionDirs = sessionDirs([sessionDirs.isdir]);

    pattern = ['^ses-' regexptranslate('escape',selectedDay) ...
        '(?=[A-Za-z])'];

    keep = ~cellfun('isempty', ...
        regexp({sessionDirs.name},pattern,'once'));

    sessionDirs = sessionDirs(keep);
    assert(~isempty(sessionDirs), ...
        'Could not find the session corresponding to %s.：%s',selectedDay,inputRoot);

    searchRoots = arrayfun(@(s) fullfile(s.folder,s.name), ...
        sessionDirs,'UniformOutput',false);
else
    searchRoots = {inputRoot};
end

% First, collect the files; then, filter by run; and finally, decide whether to use the backup epoched data.
cleanFiles = [];
epochFiles = [];

for k = 1:numel(searchRoots)
    cleanFiles = [cleanFiles; dir(fullfile(searchRoots{k},'**', ...
        '*_desc-CleanEpochedWithEvents_emg.set'))];

    epochFiles = [epochFiles; dir(fullfile(searchRoots{k},'**', ...
        '*_desc-Epoched_emg.set'))];
end

fileGroups = {cleanFiles,epochFiles};

for g = 1:numel(fileGroups)
    candidates = fileGroups{g};

    if ~isempty(candidates) && ~isempty(opt.runs)
        keep = false(numel(candidates),1);

        for k = 1:numel(candidates)
            token = regexp(candidates(k).name, ...
                '_run-(\d+)_','tokens','once');

            if ~isempty(token)
                keep(k) = ismember(str2double(token{1}), ...
                    str2double(string(opt.runs)));
            end
        end

        candidates = candidates(keep);
    end

    fileGroups{g} = candidates;
end

files = fileGroups{1};
if isempty(files)
    files = fileGroups{2};
end

assert(~isempty(files),'No CleanEpochedWithEvents or Epoched EMG .set found. Select your EMG results folder.');

assert(strlength(string(opt.outputRoot)) > 0, ...
    'Please pass the bids_root from config_paths.m via opt.outputRoot.');
derivativesContainer = char(opt.outputRoot);

stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
% Separate execution datasets keep earlier task2 results intact.
resultRoot = directDataset(derivativesContainer,'p3modecharacterisation');

outDir=fullfile(resultRoot,'reports');
if ~isfolder(outDir), mkdir(outDir); end
p3Sources={};
modeNames=["NoExoPre","aquaplus","aqua","transparent","eco","sport","boost","NoExoPost"];
modeClass=["baseline","resistive","resistive","transparent","assistive","assistive","assistive","post-control"];
modeSymbol=["Pre","--","-","0","+","++","+++","Post"];
muscles=["Vastus medialis","Rectus femoris","Biceps femoris","Gluteus maximus"];
sensors=[4 5 6 7 11 12 13 14]; anatomy=[46 44 13 12 46 44 13 12];
short=["Vastus_med","Rect_fem","Biceps_fem","Glut_max"];
records=struct([]); audit=struct([]); cycles=struct([]); seen=strings(0,1);
for fi=1:numel(files)
    path=fullfile(files(fi).folder,files(fi).name);
    sourcePath=path;
    sourceIdentity=directIdentity(sourcePath,struct);
    sourceDay=string(sourceIdentity.Day);
    a=struct('File',string(sourcePath),'Status',"",'Detail',"",'TotalEpochs',0,'RetainedCycles',0);
    try
        sub=regexp(files(fi).name,'sub-(.*?)_ses-','tokens','once');
        ses=regexp(files(fi).name,'_ses-(.*?)_task-','tokens','once');
        runToken=regexp(files(fi).name,'_run-(\d+)_','tokens','once');
        assert(~isempty(sub)&&~isempty(ses)&&~isempty(runToken),'Cannot parse BIDS subject/session/run.');
        sub=string(sub{1}); ses=string(ses{1}); runLabel=compose('%03d',str2double(runToken{1}));
        if (~isempty(opt.subjects)&&~ismember(sub,string(opt.subjects))) || ...
                (~isempty(opt.runs)&&~ismember(str2double(runLabel),str2double(string(opt.runs))))
            continue
        end
        compact=regexprep(lower(ses),'[^a-z0-9]','');
        % endsWith(scalar, patternArray) returns ANY-match, not a per-pattern mask.
        conditionMatches=cellfun(@(name) endsWith(char(compact),name), ...
            cellstr(lower(modeNames)));
        ci=find(conditionMatches);
        assert(isscalar(ci),'Unrecognized or ambiguous condition: %s',ses);
        key=sub+"|"+sourceDay+"|"+runLabel+"|"+modeNames(ci);
        assert(~ismember(key,seen),'Duplicate subject/run/condition. Analyze days separately: %s',key);
        seen(end+1)=key;
        p3Sources{end+1}=sourcePath;
        E=pop_loadset('filename',files(fi).name,'filepath',files(fi).folder);
        a.TotalEpochs=E.trials;
        assert(E.trials>1 && ndims(E.data)==3,'Input must contain multiple original epochs.');
        if isfield(E,'etc') && isfield(E.etc,'is_envelope')
            assert(isequal(E.etc.is_envelope,true),'Dataset explicitly not marked as envelope.');
        else
            assert(opt.envelopeConfirmed,'Missing envelope metadata. Verify preprocessing before setting envelopeConfirmed=true.');
        end
        labels=string({E.chanlocs.labels}); idx=zeros(1,8);
        inventory=table((1:numel(labels))',labels(:),'VariableNames',{'ChannelIndex','ChannelLabel'});
        writetable(inventory,fullfile(outDir,sprintf('desc-channelInventory%03d_table.tsv',fi)),'FileType','text','Delimiter','\t');
        isPrecleaned=contains(files(fi).name,'_desc-CleanEpochedWithEvents_');
        rejectAmp=opt.rejectAmplitudeOutliers;
        if isempty(rejectAmp), rejectAmp=~isPrecleaned; end
        fprintf('  Input precleaned=%d | additional amplitude rejection=%d\n',isPrecleaned,rejectAmp);
        for ch=1:8
            m=mod(ch-1,4)+1; side="R"; if ch>4, side="L"; end
            pipelineShort=["VastMed","RectFem","BicepsFem","GlutMax"];
            aliases=[short(m)+"_"+side,muscles(m)+" "+side,pipelineShort(m)+"_"+side];
            if m==4, aliases(end+1)="Glutaeus maximus "+side; end
            if strlength(string(opt.labelOverride(ch)))>0, aliases=string(opt.labelOverride(ch)); end
            hit=find(ismember(normalizeLabel(labels),normalizeLabel(aliases)));
            assert(isscalar(hit),'Missing/ambiguous muscle %s %s. Use labelOverride; do not assume row=sensor ID.',muscles(m),side);
            idx(ch)=hit;
        end
        assert(numel(unique(idx))==8,'Muscle labels map to repeated data rows.');
        ts=double(E.times(:)')/1000;
        assert(numel(ts)==E.pnts && all(diff(ts)>0),'Invalid original epoch time axis.');
        n=E.trials; integ=nan(n,8); peaks=nan(n,8); phase=nan(n,8);
        duration=nan(n,1); reason=repmat("",n,1); curves=nan(n,101,8);
        for ep=1:n
            try
                [et,el]=epochEvents(E,ep);
                rr=sort(el(et=="HS_R")); zero=rr(abs(rr)<=1.5/E.srate);
                assert(isscalar(zero),'No unique HS_R at epoch zero.');
                t0=zero(1); next=rr(rr>t0+1.5/E.srate);
                assert(~isempty(next),'No next HS_R.'); t1=next(1);
                duration(ep)=t1-t0;
                assert(duration(ep)>=opt.durationRange(1)&&duration(ep)<=opt.durationRange(2),'Cycle duration outside range.');
                mid=zeros(1,3); types=["TO_L","HS_L","TO_R"];
                for j=1:3
                    x=el(et==types(j)&el>t0&el<t1);
                    assert(isscalar(x),'Missing/duplicate gait event within cycle.'); mid(j)=x;
                end
                assert(all(diff([t0 mid t1])>0),'Gait events out of order.');
                assert(ts(1)<=t0 && ts(end)>=t1,'Incomplete cycle in epoch.');
                interior=ts(ts>t0 & ts<t1); tt=[t0 interior t1];
                y=interp1(ts,double(E.data(idx,:,ep))',tt,'linear')';
                assert(all(isfinite(y),'all') && all(y>=0,'all'),'Nonfinite or negative envelope samples.');
                assert(all(max(y,[],2)>0),'Flat/zero envelope channel.');
                integ(ep,:)=trapz(tt,y,2)';
                [p,ix]=max(y,[],2); peaks(ep,:)=p';
                ref=[repmat(t0,1,4) repmat(mid(2),1,4)];
                phase(ep,:)=mod(100*(tt(ix)-ref)/duration(ep),100);
                curves(ep,:,:)=reshape(interp1(tt,y',linspace(t0,t1,101),'linear'),1,101,8);
            catch ME
                reason(ep)=string(ME.message);
            end
        end
        eligible=reason=="";
        if rejectAmp && nnz(eligible)>=opt.minCycles
            limit=mean(peaks(eligible,:),1)+opt.amplitudeSD*std(peaks(eligible,:),0,1);
            amp=eligible & any(peaks>limit,2); reason(amp)="Peak > mean + configured SD in at least one of 8 muscles";
        end
        keep=reason=="";
        for ep=1:n
            for ch=1:8
                cycleRow=struct('Subject',sub,'Day',sourceDay,'Run',runLabel,'Condition',modeNames(ci), ...
                    'File',string(sourcePath),'Epoch',ep,'SensorID',sensors(ch),'Retained',keep(ep), ...
                    'Reason',reason(ep),'Duration_s',duration(ep),'Integral_native_s',integ(ep,ch), ...
                    'Peak_native',peaks(ep,ch),'PeakPhase_pct',phase(ep,ch));
                cycles=appendRecord(cycles,cycleRow);
            end
        end
        a.RetainedCycles=nnz(keep);
        assert(nnz(keep)>=opt.minCycles,'Too few retained cycles (%d < %d).',nnz(keep),opt.minCycles);
        for ch=1:8
            m=mod(ch-1,4)+1; side="R"; if ch>4, side="L"; end
            [pm,pr]=circularMean(phase(keep,ch));
            if pr<opt.minTimingResultant, pm=NaN; end
            recordRow=struct('Subject',sub,'Day',sourceDay,'Run',runLabel,'Condition',modeNames(ci), ...
                'ModeClass',modeClass(ci),'ModeSymbol',modeSymbol(ci),'ConditionIndex',ci, ...
                'Muscle',muscles(m),'Side',side,'SensorID',sensors(ch),'AnatomyNumber',anatomy(ch), ...
                'ChannelIndex',idx(ch),'ChannelLabel',labels(idx(ch)),'Ncycles',nnz(keep), ...
                'MeanCycleDuration_s',mean(duration(keep)), ...
                'Integral_native_s',mean(integ(keep,ch)),'IntegralSD_native_s',std(integ(keep,ch)), ...
                'Peak_native',mean(peaks(keep,ch)),'PeakSD_native',std(peaks(keep,ch)), ...
                'PeakPhase_pct',pm,'TimingResultant',pr,'InputFile',string(sourcePath), ...
                'Integral_pctPre',NaN,'Peak_pctPre',NaN,'PeakPhaseShift_pp',NaN, ...
                'BaselineCycles',0,'Status',"PENDING_BASELINE", ...
                'MeanCurve_RHS',mean(curves(keep,:,ch),1));
            records=appendRecord(records,recordRow);
        end
        a.Status="OK"; a.Detail="Precleaned="+string(isPrecleaned)+"; additional amplitude rejection="+string(rejectAmp);
    catch ME
        a.Status="ERROR"; a.Detail=string(ME.message);
        warning('Task2:Input','%s: %s',files(fi).name,ME.message);
    end
    audit=appendRecord(audit,a);
end
assert(~isempty(audit),'No files matched subjects/runs filters.');
writetable(struct2table(audit),fullfile(outDir,'desc-inputAudit_table.tsv'),'FileType','text','Delimiter','\t');
if ~isempty(cycles), writetable(struct2table(cycles),fullfile(outDir,'desc-cycleAudit_table.tsv'),'FileType','text','Delimiter','\t'); end
assert(~isempty(records),'No usable datasets. Read desc-inputAudit_table.tsv in %s',outDir);
% struct2table may retain string scalar fields inside cell columns.
% Enforce column types once before baseline matching and all later plotting.
T=struct2table(records(:));
meanCurves=T.MeanCurve_RHS;
if iscell(meanCurves), meanCurves=vertcat(meanCurves{:}); end
T.MeanCurve_RHS=[];
textColumns=["Subject","Day","Run","Condition","ModeClass","ModeSymbol", ...
    "Muscle","Side","ChannelLabel","InputFile","Status"];
for columnName=string(T.Properties.VariableNames)
    v=T.(columnName);
    if ismember(columnName,textColumns)
        if iscell(v)
            converted=strings(numel(v),1);
            for rowIndex=1:numel(v)
                item=v{rowIndex};
                while iscell(item)&&isscalar(item), item=item{1}; end
                item=string(item);
                assert(isscalar(item),'Text field %s must contain one value per row.',columnName);
                converted(rowIndex)=item;
            end
            v=converted;
        else
            v=string(v);
        end
    else
        if iscell(v)
            assert(all(cellfun(@(x) isnumeric(x)&&isscalar(x),v)), ...
                'Numeric field %s contains a nonnumeric or nonscalar value.',columnName);
            v=vertcat(v{:});
        end
        assert(isnumeric(v),'Expected numeric column: %s',columnName);
        v=double(v);
    end
    assert(numel(v)==height(T),'Column %s must contain one value per row.',columnName);
    T.(columnName)=v(:);
end
for i=1:height(T)
    b=find(T.Subject==T.Subject(i)&T.Day==T.Day(i)&T.Run==T.Run(i)&T.SensorID==T.SensorID(i)&T.Condition=="NoExoPre");
    if numel(b)~=1, continue; end
    if T.Integral_native_s(b)<=0 || T.Peak_native(b)<=0, T.Status(i)="INVALID_BASELINE"; continue; end
    T.Integral_pctPre(i)=100*T.Integral_native_s(i)/T.Integral_native_s(b);
    T.Peak_pctPre(i)=100*T.Peak_native(i)/T.Peak_native(b);
    T.PeakPhaseShift_pp(i)=mod(T.PeakPhase_pct(i)-T.PeakPhase_pct(b)+50,100)-50;
    T.BaselineCycles(i)=T.Ncycles(b); T.Status(i)="OK";
    if ~isfinite(T.PeakPhaseShift_pp(i)), T.Status(i)="TIMING_DISPERSED"; end
end
writetable(T,fullfile(outDir,'desc-modeSummary_table.tsv'),'FileType','text','Delimiter','\t');
protocol=struct('options',opt,'inputRoot',inputRoot,'created',stamp, ...
    'modeNames',modeNames,'modeClass',modeClass,'modeSymbol',modeSymbol, ...
    'sensorIDs',sensors,'anatomyNumbers',anatomy,'amplitudeUnits','native .set units; ratios dimensionless');
save(fullfile(outDir,'desc-modecharacterisation_data.mat'),'T','records','cycles','audit','meanCurves','protocol','-v7.3');
fig=figure('Color','w','Position',[60 40 1500 1900],'Visible','off');
closer=onCleanup(@()close(fig));
tl=tiledlayout(fig,8,3,'TileSpacing','compact','Padding','compact');
keys=unique(T.Subject+" / "+T.Day+" / run "+T.Run,'stable'); colors=lines(numel(keys));
fields=["Integral_pctPre","Peak_pctPre","PeakPhaseShift_pp"];
ylabels=["Integral (% Pre)","Peak (% Pre)","Peak timing shift (pp)"];
legendHandles=gobjects(0); legendText=strings(0);
for ch=1:8
    for metric=1:3
        ax=nexttile(tl); hold(ax,'on');
        for k=1:numel(keys)
            select=(T.Subject+" / "+T.Day+" / run "+T.Run)==keys(k)&T.SensorID==sensors(ch);
            values=nan(1,8); values(T.ConditionIndex(select))=T.(fields(metric))(select);
            h=plot(ax,1:8,values,'-o','Color',colors(k,:),'LineWidth',1.2,'MarkerSize',4);
            if ch==1&&metric==1, legendHandles(end+1)=h; legendText(end+1)=keys(k); end
        end
        baseline=100; if metric==3, baseline=0; end
        yline(ax,baseline,':','Color',[.35 .35 .35]);
        xlim(ax,[.7 8.3]); xticks(ax,1:8); xticklabels(ax,modeSymbol); grid(ax,'on');
        side='R'; if ch>4, side='L'; end
        title(ax,sprintf('%s %s | %s',muscles(mod(ch-1,4)+1),side,ylabels(metric)),'Interpreter','none');
        ylabel(ax,ylabels(metric));
    end
end
lg=legend(legendHandles,legendText,'Interpreter','none','Orientation','horizontal'); lg.Layout.Tile='south';
title(tl,'Mode characterisation | individual subject/run | baseline = NoExoPre','Interpreter','none');
subtitle(tl,'-- aquaplus | - aqua | 0 transparent | + eco | ++ sport | +++ boost | Pre/Post no exoskeleton');
exportgraphics(fig,fullfile(outDir,'desc-modecharacterisation_figure.png'),'Resolution',180);
savefig(fig,fullfile(outDir,'desc-modecharacterisation_figure.fig'));

caption=[ ...
"Task2. Each line is one subject/run; no pooling across subjects or runs."; ...
"R: sensor IDs 4,5,6,7; L: 11,12,13,14. Muscles: vastus medialis (46), rectus femoris (44), biceps femoris (13), gluteus maximus (12)."; ...
"Sensor IDs describe experimental placement, not row indices or Delsys Pair numbers. Channels matched by saved muscle labels."; ...
"Data: pre-existing linear envelopes (provided preprocessing: rectification then 8-Hz low-pass). No re-filtering or new rectification."; ...
"Cycles: original HS_R to next HS_R; require ordered HS_R,TO_L,HS_L,TO_R,HS_R. Integrals use real seconds, not warped phase."; ...
"Peak amplitude and integral computed per cycle, then arithmetic means. Plot 100*condition mean / same subject/day/run/muscle NoExoPre mean."; ...
"Activation timing defined as envelope peak phase, NOT onset/offset. Right phase reference HS_R, left reference HS_L within the same right stride."; ...
"Timing uses circular mean; positive signed circular difference is later, negative earlier; units percentage points, range [-50,50)."; ...
"Broad/multiple peaks may make peak timing unstable. Timing omitted when circular resultant < "+string(opt.minTimingResultant)+"; resultant saved in table."; ...
"Cycle QC: complete ordered events, duration "+join(string(opt.durationRange)," to ")+" s, finite nonnegative nonzero signals in all eight muscles."; ...
"Additional amplitude rejection: auto (off for clean input, on for original) unless overridden; one-pass peak > mean + "+string(opt.amplitudeSD)+" SD in any target muscle; minimum "+string(opt.minCycles)+" cycles."; ...
"Clean input retains prior rejection; structural checks always applied. desc-inputAudit_table.tsv records extra amplitude rejection per file; desc-cycleAudit_table.tsv documents current decisions."; ...
"Curves in MAT are linearly resampled RHS-cycle envelopes for audit; metrics are computed before resampling. Native amplitudes are not relabelled as uV or mV."; ...
"Missing baseline leaves normalized cells empty, not zero. Missing/failed datasets in desc-inputAudit_table.tsv. Unequal cycle counts recorded; no independent-cycle hypothesis tests."; ...
"Mode order/classes supplied by investigator. EMG changes characterize responses; they do not establish delivered controller torque or assistance direction."; ...
"No walking-boundary re-selection performed: input event epochs must already represent the intended walking trial. Review preprocessing and sensor placement before interpretation." ];
fid=fopen(fullfile(outDir,'desc-protocol_report.txt'),'w','n','UTF-8'); assert(fid>=0);

for k=1:numel(caption)
    fprintf(fid,'%s\n',caption(k)); 
end
fclose(fid);
directJSON(fullfile(outDir,'desc-modecharacterisation_provenance.json'), ...
    struct('SourceFiles',{p3Sources},'PipelineVersion','1.1.0','Options',opt));
fprintf('\nTASK2 %s saved: %s\n',outDir);
fprintf('Usable datasets: %d | input errors: %d | summary rows: %d\n',nnz(string({audit.Status})=="OK"),nnz(string({audit.Status})=="ERROR"),height(T));
fprintf('Rows without baseline normalization: %d | undefined timing: %d\n',nnz(~isfinite(T.Integral_pctPre)),nnz(~isfinite(T.PeakPhaseShift_pp)));
end

function [types,latencies]=epochEvents(E,ep)

% Read epoch.eventtype/eventlatency; latencies are milliseconds relative to epoch zero.
assert(isfield(E.epoch,'eventtype')&&isfield(E.epoch,'eventlatency'),'Missing epoch event metadata.');
t=E.epoch(ep).eventtype; l=E.epoch(ep).eventlatency;

if ~iscell(t), t=cellstr(string(t)); 
end
if ~iscell(l), l=num2cell(l); 
end

assert(numel(t)==numel(l),'Event type/latency length mismatch.');

types=strings(1,numel(t)); latencies=nan(1,numel(t));

for k=1:numel(t)
    types(k)=strtrim(string(t{k}));
    q=l{k}; 
    if ischar(q)||isstring(q)
        q=str2double(q); 
    end
    assert(isnumeric(q)&&isscalar(q)&&isfinite(q),'Invalid event latency.'); latencies(k)=double(q)/1000;
end
end

function [m,r]=circularMean(p)

z=mean(exp(1i*2*pi*p/100)); r=abs(z); m=mod(angle(z)*100/(2*pi),100);

end

function s=normalizeLabel(s)

s=regexprep(lower(strtrim(string(s))),'[^a-z0-9]','');

end

function rows=appendRecord(rows,row)

% First row establishes the schema, avoiding fieldless struct-array assignment.
if isempty(rows)
    rows=row;
else
    assert(isequal(sort(fieldnames(rows)),sort(fieldnames(row))), ...
        'Internal record schema mismatch.');
    rows(end+1)=orderfields(row,rows);
end

end


function root=directDataset(container,pipeline)

% Final destination: no staging, restoration, copying or migration.
root = fullfile(char(container), 'derivatives', char(pipeline));

if ~isfolder(root)
    mkdir(root);
end

description = struct( ...
    'Name', ['PilotTest3 ' char(pipeline)], ...
    'BIDSVersion', '1.11.2', ...
    'DatasetType', 'derivative', ...
    'GeneratedBy', {{struct('Name', char(pipeline))}});

directJSON(fullfile(root, 'dataset_description.json'), description);
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
else, day=d{1}; 
end
assert(~isempty(regexp(day,'^day\d+$','once')),'Day must be day1, day2, etc.');
condition=regexprep(c{1},['^' day],'');

if isempty(t), task='Default'; 
else, task=t{1}; 
end

id=struct('OriginalSubject',sub,'Subject',regexprep(sub,'[^A-Za-z0-9]',''), ...
    'Day',day,'OriginalSession',condition,'Session',[day regexprep(condition,'[^A-Za-z0-9]','')], ...
    'Task',task,'Run',sprintf('%03d',str2double(r{1})), 'SourceFile',source);
id.Prefix=sprintf('sub-%s_ses-%s_task-%s_run-%s',id.Subject,id.Session,id.Task,id.Run);
end
