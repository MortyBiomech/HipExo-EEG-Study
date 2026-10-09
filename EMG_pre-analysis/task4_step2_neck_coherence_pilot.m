function out=task4_step2_neck_coherence_pilot(inputDir,opt)
% STEP 2 v0.3.0: neck-contamination report directly from Step-1 QC outputs.
% INPUT: Step-1 QC folder containing walking_intervals.tsv and walking_neck_channel_qc.tsv.
% Loads original XDF referenced by Step 1 automatically. Old aligned folders still work.
% Usage: task_b_neck_coherence_pilot; % select Step-1 QC folder
% Default session=NoExoPre, run=001; override via opt.session and opt.run.
% opt.eegChannels=1:64, opt.eegStreamName='', opt.fs=500, opt.xdfFile=''.
% These raw-input defaults apply to the 64 EEG + 3 ACC acquisition; verify inventory.
% Requires Signal Processing Toolbox; EEGLAB topoplot/readlocs for scalp maps.
% opt fields (all optional):
%   chanlocsFile: .ced/.loc/.sfp/.elc, .mat containing chanlocs or EEG, or .set
%   eventsFile: .mat containing all_events(type,time), HS_R.timestamps, or rhsTime
%               OR CSV containing Type,Time_s. ALL event times must be XDF seconds.
%   postFile: task-c cleaned_eeg.mat (must retain sharedTime and matching provenance)
%   commonProtocolFile: prior *_desc-commonProtocol_data.mat for EXACT reuse of windows
%   windowSeconds=2, nfft=[] (=window samples), phasePercent=0:10:100
%   notchBands=[49 51;99 101], filterGuardSeconds=2
%   excludedLabels={}, interpolatedLabels={}, channelReviewConfirmed=false
%   badIntervalsXDF=[] (Nx2, shared XDF clock), rhsDurationRange=[0.4 3]
%   commonProtocolConfirmed=false: set true ONLY after agreeing leg-CMC protocol
%   segmentIndependenceAssumed=false: true ONLY when scientific assumption accepted
%   locationsConfirmed=false: confirm label-matched supplied positions
%   phaseResolutionConfirmed=false: acknowledge window width vs stride duration
%   promptForAuxiliary=true: cancel either optional picker to run partial report
% Outputs: ONE combined PNG+FIG, full pairwise MSC MAT, caption TXT, metrics CSV,
%          common protocol MAT (window indices/phase indices/filtering for leg CMC).
% Missing post/maps/phase are explicitly labelled pending, not fabricated.
% Nonoverlap removes sample reuse WITHIN an estimate, but does not prove independence.
% Halliday CL is nominal pointwise, NOT corrected for max of 8, bins or electrodes.
% Band black dots compare mean transformed z with transformed nominal Halliday CL.
% This is a requested descriptive rule, NOT a calibrated band-level hypothesis test.
% High gamma is a contamination-reference band, NOT proof of artifact origin.
% Scalp z uses MAX across neck at EACH frequency, THEN transform, THEN band mean.
% Ordinary Cz beta summary is inverse-transform(mean z), not mean raw MSC.
% Phase spectra: fixed-duration physical-time windows, ensemble averaged across
% nonoverlapping stride neighborhoods. No signal time-warping (preserves Hz).
% Window length/taper/nfft are identical for spectra and phase estimates; L differs.
% Long windows blur gait phase. No claim of fine phase resolution is made.
% References: Halliday et al. 1995; EEGLAB topoplot; MATLAB butter/filtfilt.

eeglab nogui;
if nargin<1 || isempty(inputDir)
 inputDir=uigetdir(pwd,'Select STEP-1 output folder containing walking_intervals.tsv');
 if isequal(inputDir,0),out='';return;end
end
if nargin<2,opt=struct;end
fprintf('STEP 2 v0.3.0 | %s\n',mfilename('fullpath'));

opt=defaults(opt,'session','NoExoPre','run','001','eegChannels',1:64,...
 'eegStreamName','','fs',500,'xdfFile','','chanlocsFile','','eventsFile','','postFile','','commonProtocolFile','',...
 'windowSeconds',2,'nfft',[],'phasePercent',0:10:100,'notchBands',[49 51;99 101],...
 'filterGuardSeconds',2,'excludedLabels',{},'interpolatedLabels',{},...
 'channelReviewConfirmed',false,'badIntervalsXDF',zeros(0,2),'rhsDurationRange',[0.4 3],...
 'commonProtocolConfirmed',false,'segmentIndependenceAssumed',false,...
 'locationsConfirmed',false,'phaseResolutionConfirmed',false,'promptForAuxiliary',true, ...
 'derivativesContainer','');

assert(strlength(string(opt.derivativesContainer)) > 0, ...
    'Please pass the bids_root from config_paths.m via opt.derivativesContainer.');

for fn={'butter','filtfilt','hann'}
 assert(exist(fn{1},'file')~=0,'Missing %s (Signal Processing Toolbox).',fn{1});
end
inputDir=char(inputDir);
if (isfile(fullfile(inputDir,'walking_intervals.tsv')) || isfile(fullfile(inputDir,'walking_intervals.csv')))
 [A,B,~]=prepareStep1(inputDir,opt);
elseif isfile(fullfile(inputDir,'aligned_pre.mat')) && isfile(fullfile(inputDir,'coherence_pre.mat'))
 A=load(fullfile(inputDir,'aligned_pre.mat'));
 B=load(fullfile(inputDir,'coherence_pre.mat'),'eegLabels','neckLabels','q','w','provenance');
else
 % Recover an accidental selection of task_b_pilot or its run folder.
 parent=inputDir; found=false;
 for k=1:3
  parent=fileparts(parent);
  if (isfile(fullfile(parent,'walking_intervals.tsv')) || isfile(fullfile(parent,'walking_intervals.csv')))
   fprintf('Using Step-1 folder: %s\n',parent);
   [A,B,inputDir]=prepareStep1(parent,opt);found=true;break;
  end
 end
 assert(found,['Select the Step-1 v1.5.1 output folder containing walking_intervals.tsv ' ...
  'and walking_neck_channel_qc.tsv. Do not select the neck_emg_QC parent.']);
end
assert(all(isfield(A,{'xe','xm','sharedTime','opt','provenance'})) && ...
 all(isfield(B,{'eegLabels','neckLabels','q','w','provenance'})),'Wrong input folder.');
assert(strcmp(A.provenance.xdfFile,B.provenance.xdfFile),'Input provenance mismatch.');
x=double(A.xe); m=double(A.xm); t=double(A.sharedTime(:)); fs=A.opt.fs;
[n,nE]=size(x); labels=string(B.eegLabels(:)); neckLabels=string(B.neckLabels(:));
assert(size(m,1)==n && size(m,2)==8 && numel(t)==n && numel(labels)==nE,...
 'Aligned input dimensions do not match.');
assert(all(isfinite(x(:))) && all(isfinite(m(:))) && all(isfinite(t)) && ...
 all(diff(t)>0) && max(abs(diff(t)-1/fs))<1e-6,'Invalid input/time grid.');
assert(numel(unique(lower(labels)))==nE,'Duplicate EEG labels.');
assert(all(ismember(lower(string([opt.excludedLabels(:);opt.interpolatedLabels(:)])),lower(labels))),...
 'Unknown excluded/interpolated label; check spelling.');
assert(size(opt.badIntervalsXDF,2)==2 && all(isfinite(opt.badIntervalsXDF(:))) && ...
 all(opt.badIntervalsXDF(:,2)>opt.badIntervalsXDF(:,1)),'Invalid bad intervals.');
subject=string(B.q.Subject(1)); session=string(B.w.Session(1)); runID=string(B.w.Run(1));
identity=directIdentity(A.provenance.xdfFile,struct);
base=identity.Prefix;

resultRoot = directDataset(opt.derivativesContainer,'p3neckcoherence');
out=fullfile(resultRoot,['sub-' identity.Subject],['ses-' identity.Session], ...
    'eeg');
if ~isfolder(out), mkdir(out); end
copyfile([mfilename('fullpath') '.m'],fullfile(out,[base '_code.m']));
if opt.promptForAuxiliary
 if isempty(opt.chanlocsFile),opt.chanlocsFile=pick('*.ced;*.loc;*.locs;*.sfp;*.elc;*.mat;*.set','Choose electrode coordinates; Cancel = pending maps');end
 if isempty(opt.eventsFile),opt.eventsFile=pick('*.mat;*.csv;*.tsv','Choose RHS events in XDF seconds; Cancel = pending phase panel');end
end
% Same native values/reference as input; notch applies equally to both conditions.
hasPost=~isempty(opt.postFile); y=[];
if hasPost
 P=load(opt.postFile);
 assert(all(isfield(P,{'y','sharedTime','meta'})),'Post file must be task-c cleaned_eeg.mat.');
 assert(isequal(size(P.y),size(x)) && numel(P.sharedTime)==n && ...
 max(abs(double(P.sharedTime(:))-t))<1e-6,'Post timing/dimensions differ.');
 assert(isfield(P.meta,'sourceProvenance') && ...
 strcmp(P.meta.sourceProvenance.xdfFile,A.provenance.xdfFile),'Post source mismatch.');
 assert(isfield(P,'EEGpost') && isequal(string({P.EEGpost.chanlocs(1:nE).labels})',labels),...
 'Post channel labels/order mismatch.');
 y=double(P.y); assert(all(isfinite(y(:))),'Invalid cleaned samples.');
end
if ~isempty(opt.commonProtocolFile)
 H=load(opt.commonProtocolFile,'protocol'); protocol=H.protocol;
 assert(protocol.fs==fs && protocol.nSamples==n && ...
 max(abs(protocol.sharedTime-t))<1e-6 && strcmp(protocol.xdfFile,A.provenance.xdfFile),...
 'Protocol belongs to different samples or recording.');
 opt.windowSeconds=protocol.windowSeconds;opt.nfft=protocol.nfft;
 opt.phasePercent=protocol.phasePercent;opt.notchBands=protocol.notchBands;
 opt.filterGuardSeconds=protocol.filterGuardSeconds;opt.badIntervalsXDF=protocol.badIntervalsXDF;
end
N=round(opt.windowSeconds*fs);assert(N>=4,'Window too short.');
if isempty(opt.nfft),opt.nfft=N;end
assert(opt.nfft>=N && opt.nfft==fix(opt.nfft),'nfft must be integer >= window samples.');
assert(fs/2>100,'Input Nyquist must exceed 100 Hz.');
assert(all(opt.phasePercent>=0 & opt.phasePercent<=100) && all(diff(opt.phasePercent)>0),...
 'Invalid phasePercent.');
assert(size(opt.notchBands,2)==2 && all(opt.notchBands(:,1)>0) && ...
 all(opt.notchBands(:,2)<fs/2) && all(diff(opt.notchBands,1,2)>0),'Invalid notch bands.');
assert(all(isfinite(opt.notchBands(:))),'Nonfinite notch limits.');
x=notch(x,fs,opt.notchBands);m=notch(m,fs,opt.notchBands);
if hasPost,y=notch(y,fs,opt.notchBands);end
bad=ismember(lower(labels),lower(string([opt.excludedLabels(:);opt.interpolatedLabels(:)])));
assert(nnz(~bad)>=5,'Fewer than five usable EEG channels.');
assert(all(std(x(:,~bad))>0) && all(std(m)>0),'Constant included signal.');
if hasPost,assert(all(std(y(:,~bad))>0),'Constant post EEG.');end
valid=true(n,1); guard=ceil(opt.filterGuardSeconds*fs);
assert(guard>=0 && 2*guard<n,'Invalid edge guard.');
valid(1:guard)=false;valid(end-guard+1:end)=false;
for k=1:size(opt.badIntervalsXDF,1)
 % Guard against filtering leakage adjacent to excluded data.
 valid(t>=opt.badIntervalsXDF(k,1)-opt.filterGuardSeconds & ...
       t<=opt.badIntervalsXDF(k,2)+opt.filterGuardSeconds)=false;
end
if isempty(opt.commonProtocolFile)
 starts=(guard+1:N:n-guard-N+1)';starts=keepWindows(starts,N,valid);
 rhs=readRHS(opt.eventsFile,t);phaseStarts=[];selectedStrides=[];strideDuration=[];
 if numel(rhs)>=3
  [phaseStarts,selectedStrides,strideDuration]=phaseWindows(rhs,t,fs,N,opt,valid);
 end
 protocol=struct('fs',fs,'nSamples',n,'sharedTime',t,'xdfFile',A.provenance.xdfFile,...
  'windowSeconds',N/fs,'windowSamples',N,'nfft',opt.nfft,'taper','periodic Hann',...
  'detrend','per-window mean removal','overlap',0,'starts',starts,...
  'phasePercent',opt.phasePercent,'phaseStarts',phaseStarts,'selectedStrides',selectedStrides,...
  'strideDuration',strideDuration,'rhsTime',rhs,'notchBands',opt.notchBands,...
  'filterGuardSeconds',opt.filterGuardSeconds,'badIntervalsXDF',opt.badIntervalsXDF,...
  'independence','Nonoverlapping segments; independence remains an assumption',...
  'phaseMethod','Fixed physical-time windows; stride neighborhoods thinned to avoid sample reuse');
else
 starts=protocol.starts;phaseStarts=protocol.phaseStarts;
 assert(isequal(starts,keepWindows(starts,N,valid)) && all(diff(starts)>=N),...
 'Protocol windows invalid for current mask.');
end
if ~isempty(protocol.strideDuration) && N/fs>=median(protocol.strideDuration)
 warning('Step2:PhaseSmoothing','Spectral window spans >= one median stride. Phase map is strongly smoothed; finalize the common neck/leg protocol before interpretation.');
end
L=numel(starts);assert(L>2,'Need at least three retained segments.');
windowTable=table(starts,starts+N-1,t(starts),t(starts+N-1),...
 'VariableNames',{'StartSample','EndSample','StartXDF_s','LastSampleXDF_s'});
writeDerivativeTable(windowTable,fullfile(out,[base '_desc-windows_table.tsv']));
save(fullfile(out,[base '_desc-commonProtocol_data.mat']),'protocol','-v7.3');
fprintf('Step2: %d nonoverlapping segments, %.3f s Hann, frequency spacing %.3f Hz\n',L,N/fs,fs/opt.nfft);
[Cpre,f]=estimate(x,m,starts,N,opt.nfft); Cpre(:,bad,:)=NaN;
Cpost=[];if hasPost,Cpost=estimate(y,m,starts,N,opt.nfft);Cpost(:,bad,:)=NaN;end
f=f*fs; alpha=0.05; CL=1-alpha^(1/(L-1));zCL=atanh(sqrt(CL))*sqrt(2*L-2);
maxPre=max(Cpre,[],3);zPre=toZ(maxPre,L);
maxPost=[];zPost=[];if hasPost,maxPost=max(Cpost,[],3);zPost=toZ(maxPost,L);end
bands=[13 30;30 45;55 95]; bandNames={'Beta 13-30 Hz','Low gamma 30-45 Hz','High gamma 55-95 Hz'};
bandZpre=nan(nE,3);bandZpost=bandZpre;binMasks=false(numel(f),3);
for k=1:3
 % Half-open first band avoids double counting 30 Hz; others include upper edge.
 if k==1, mask=f>=bands(k,1)&f<bands(k,2);else,mask=f>=bands(k,1)&f<=bands(k,2);end
 assert(any(mask),'No frequency bins in a requested band.');binMasks(:,k)=mask;
 bandZpre(:,k)=mean(zPre(mask,:),1)';
 if hasPost,bandZpost(:,k)=mean(zPost(mask,:),1)';end
end
sigPre=bandZpre>zCL;sigPost=bandZpost>zCL;
cz=find(strcmpi(labels,'Cz'));assert(isscalar(cz),'Cz missing or duplicated.');
pctPre=100*nnz(sigPre(~bad,1))/nnz(~bad);
czBetaPre=tanh(bandZpre(cz,1)/sqrt(2*L-2))^2;
pctPost=NaN;czBetaPost=NaN;
if hasPost,pctPost=100*nnz(sigPost(~bad,1))/nnz(~bad);czBetaPost=tanh(bandZpost(cz,1)/sqrt(2*L-2))^2;end
metrics=table(["Pre";"Post"],[L;L],[pctPre;pctPost],[czBetaPre;czBetaPost],...
 'VariableNames',{'Stage','L_assuming_independence','BetaPercent_nominal_z_rule','CzBeta_backtransformed_meanZ'});
writeDerivativeTable(metrics,fullfile(out,[base '_desc-metrics_table.tsv']));
% Phase panel: same spectral estimator; independent stride ensembles per phase.
phaseC=[];phaseMax=[];Lphase=size(phaseStarts,1);phaseCL=NaN;
if Lphase>2 && ~bad(cz)
 phaseC=nan(numel(f),numel(opt.phasePercent),8);
 for k=1:numel(opt.phasePercent)
  v=estimate(x(:,cz),m,phaseStarts(:,k),N,opt.nfft);
  phaseC(:,k,:)=v;
 end
 phaseMax=max(phaseC,[],3);phaseCL=1-alpha^(1/(Lphase-1));
end
[locs,locationsReady,locationNote]=locations(opt.chanlocsFile,labels);
phaseReady=~isempty(phaseMax);
complete=hasPost && locationsReady && phaseReady && opt.commonProtocolConfirmed && ...
 opt.segmentIndependenceAssumed && opt.channelReviewConfirmed && ...
 opt.locationsConfirmed && opt.phaseResolutionConfirmed;
status='DRAFT: inputs or method confirmations pending';if complete,status='All configured panels generated; nominal statistical caveats still apply';end
excludedText=strjoin(labels(bad),', ');if strlength(excludedText)==0,excludedText="none supplied";end
notchText=mat2str(opt.notchBands);
caption=sprintf(['%s | %s | %s.\n' ...
 'Maximum across 8 neck channels at EACH frequency, then z=atanh(sqrt(C))*sqrt(2L-2); band maps show mean z.\n' ...
 'L=%d nonoverlapping segments, independence ASSUMED (not proven); %.3f-s periodic Hann, per-window demeaning, NFFT=%d, grid spacing %.3f Hz.\n' ...
 'Halliday nominal pointwise 95%% CL=%.6g; transformed threshold=%.6g. Black dots and beta percentages use mean band z > this threshold.\n' ...
 'This is a DESCRIPTIVE UNCORRECTED rule, not a calibrated band-level test; no correction for max over 8, frequency bins or electrodes.\n' ...
 'Band bins: [13,30), [30,45], [55,95] Hz. Notch stop bands %s Hz, butter(2,...,stop) plus filtfilt, applied to analysis copies of EEG/EMG (pre and post).\n' ...
 'Notch is analysis-stage only; it does not imply notch was applied before iCanClean fitting. High gamma is a contamination reference, not proof of origin.\n' ...
 'Bad/interpolated electrodes omitted from maps and percentage denominator: %s. Channel review confirmed=%d.\n' ...
 'Colour limits per band are [0,max(before z)] and shared across rows; post values above that maximum saturate and are counted in saved data.\n' ...
 'Cz beta MSC summary is tanh(mean z/sqrt(2L-2))^2 (not arithmetic mean raw MSC).\n' ...
 'Phase: RHS-to-next-RHS, fixed physical-time windows, no signal warping; same taper/window/NFFT, Lphase=%d, nominal CLphase=%.6g.\n' ...
 'Stride neighborhoods thinned to avoid sample reuse across retained strides. Adjacent phase estimates are correlated. Long windows blur phase.\n' ...
 'Neck/leg common protocol confirmed=%d; segment independence assumption accepted=%d; phase resolution confirmed=%d.\n' ...
 'Locations: %s; confirmed=%d. EEG-EMG hardware synchronization remains unvalidated.\n'],...
 char(subject),char(session),status,L,N/fs,opt.nfft,fs/opt.nfft,CL,zCL,notchText,...
 char(excludedText),opt.channelReviewConfirmed,Lphase,phaseCL,opt.commonProtocolConfirmed,...
 opt.segmentIndependenceAssumed,opt.phaseResolutionConfirmed,locationNote,opt.locationsConfirmed);
if ~isempty(protocol.strideDuration)
 caption=[caption sprintf('Retained stride median %.3f s; spectral window %.3f s.\n',median(protocol.strideDuration),N/fs)];
end
if ~phaseReady,caption=[caption 'Panel 3 pending: supply valid RHS in shared XDF seconds with >=3 retained stride neighborhoods.' newline];end
if ~hasPost,caption=[caption 'After-cleaning row pending: no post file supplied.' newline];end
fid=fopen(fullfile(out,[base '_desc-caption_report.txt']),'w','n','UTF-8');assert(fid>0);fprintf(fid,'%s',caption);fclose(fid);
postSaturated=sum(bandZpost>max(bandZpre,[],1,'omitnan'),1);
result=struct('Cpre',Cpre,'Cpost',Cpost,'f',f,'labels',labels,'neckLabels',neckLabels,...
 'maxPre',maxPre,'maxPost',maxPost,'zPre',zPre,'zPost',zPost,...
 'bandZpre',bandZpre,'bandZpost',bandZpost,'bands',bands,'binMasks',binMasks,...
 'L',L,'CL',CL,'zCL',zCL,'sigPre',sigPre,'sigPost',sigPost,'bad',bad,...
 'phaseC',phaseC,'phaseMax',phaseMax,'Lphase',Lphase,'phaseCL',phaseCL,...
 'postSaturated',postSaturated,'metrics',metrics,'caption',caption,'status',status,...
 'opt',opt,'protocol',protocol,'source',A.provenance,'locs',locs);
save(fullfile(out,[base '_desc-neckCoherence_data.mat']),'result','-v7.3');
% One composite figure: spectrum top; 2x3 maps middle; phase and numbers bottom.
fig=figure('Visible','off','Color','w','Position',[30 30 1600 1400]);
tl=tiledlayout(5,3,'TileSpacing','compact','Padding','compact');
nexttile([1 3]);hold on; names=["Cz","C3","C4","T7","T8"]; leg={};
view=f>=2 & f<=100;
for k=1:numel(names)
 j=find(strcmpi(labels,names(k)));
 if isscalar(j) && ~bad(j),plot(f(view),maxPre(view,j),'LineWidth',1.1);leg{end+1}=char(names(k));end
end
yline(CL,'k--','LineWidth',1.3);leg{end+1}='Nominal Halliday 95%';
legend(leg,'Location','eastoutside');xlim([2 100]);xlabel('Frequency (Hz)');ylabel('Maximum neck MSC');
title(sprintf('Panel 1 | Before cleaning | max over 8 neck channels | L=%d (assumed independent)',L));
for row=1:2
 for k=1:3
  nexttile;stage='Before';v=bandZpre(:,k);sig=sigPre(:,k);
  if row==2,stage='After';v=bandZpost(:,k);sig=sigPost(:,k);end
  lim=max(bandZpre(~bad,k));if ~isfinite(lim)||lim<=0,lim=eps;end
  if locationsReady && (row==1 || hasPost)
   included=find(~bad); dots=find(sig(included));
   topoplot(v(included),locs(included),'maplimits',[0 lim],'electrodes','off',...
    'emarker2',{dots,'.','k',10,1});
   caxis([0 lim]);cb=colorbar;cb.Ticks=[0 lim];cb.TickLabels={sprintf('%.3g',0),sprintf('%.3g',lim)};
   ylabel(cb,'Mean z');
  else
   axis off;msg='Coordinates pending';if row==2 && ~hasPost,msg='After cleaning pending';end
   text(.5,.5,msg,'HorizontalAlignment','center');
  end
  title(sprintf('Panel 2 | %s | %s',stage,bandNames{k}));
 end
end
nexttile([1 2]);
if phaseReady
 imagesc(opt.phasePercent,f(view),phaseMax(view,:));axis xy;colorbar;
 xlabel('Gait cycle (%), RHS to RHS');ylabel('Frequency (Hz)');
 title(sprintf('Panel 3 | Cz max neck MSC | Lphase=%d | window %.2f s',Lphase,N/fs));
else
 axis off;text(.05,.5,'Panel 3 pending: RHS events / sufficient usable strides required.');
end
nexttile;axis off;
text(0,1,sprintf(['Pre: L=%d\nBeta channels above nominal z rule: %.2f%%\nCz beta MSC (back-transformed): %.5f\n' ...
 'Post: beta %.2f%%; Cz %.5f\nLphase=%d\nBlack dots: uncorrected nominal rule\n%s'],...
 L,pctPre,czBetaPre,pctPost,czBetaPost,Lphase,status),'VerticalAlignment','top','Interpreter','none','FontSize',10);
nexttile([1 3]);axis off;
shortCaption=sprintf(['Max across 8 neck channels before z transform; mean z in [13,30), [30,45], [55,95] Hz.\n' ...
 'L=%d; Lphase=%d; %.2f-s Hann; df=%.3f Hz. Notch %s Hz. Bad/interpolated omitted: %s.\n' ...
 'Each column uses before-map limits for both rows. Post saturation counts: %s.\n' ...
 'Halliday line/dots are nominal and uncorrected for max selection/band averaging/multiple testing.\n' ...
 'Protocol confirmed=%d; locations confirmed=%d; phase resolution confirmed=%d. Full caption saved alongside figure.'],...
 L,Lphase,N/fs,fs/opt.nfft,notchText,char(excludedText),mat2str(postSaturated),...
 opt.commonProtocolConfirmed,opt.locationsConfirmed,opt.phaseResolutionConfirmed);
text(0,1,shortCaption,'Interpreter','none','VerticalAlignment','top','FontSize',10);
title(tl,char(subject+' | '+session),'Interpreter','none');
savefig(fig,fullfile(out,[base '_desc-neckCoherence_figure.fig']));exportgraphics(fig,fullfile(out,[base '_desc-neckCoherence_figure.png']),'Resolution',180);close(fig);
directJSON(fullfile(out,[base '_desc-neckCoherence_provenance.json']), ...
    struct('SourceFiles',{{A.provenance.xdfFile}},'Options',opt,'Identity',identity));
fprintf('%s\nSaved: %s\n',status,out);
end

function [C,f]=estimate(x,m,starts,N,nfft)
% Average cross/auto spectra over segments BEFORE forming MSC.
assert(numel(starts)>2 && all(diff(starts)>=N),'Segments must not overlap.');
f=(0:floor(nfft/2))'/nfft;nf=numel(f);win=hann(N,'periodic');
xx=zeros(nf,size(x,2));mm=zeros(nf,size(m,2));xm=complex(zeros(nf,size(x,2),size(m,2)));
for s=starts(:)'
 a=x(s:s+N-1,:);b=m(s:s+N-1,:);a=a-mean(a,1);b=b-mean(b,1);
 a=fft(a.*win,nfft,1);b=fft(b.*win,nfft,1);a=a(1:nf,:);b=b(1:nf,:);
 xx=xx+abs(a).^2;mm=mm+abs(b).^2;
 for k=1:size(m,2),xm(:,:,k)=xm(:,:,k)+a.*conj(b(:,k));end
end
C=nan(size(xm));for k=1:size(m,2),C(:,:,k)=abs(xm(:,:,k)).^2./(xx.*mm(:,k));end
missing=~isfinite(C);C=min(max(C,0),1);C(missing)=NaN; % preserve undefined zero-power bins
end
function z=toZ(c,L)
z=atanh(sqrt(min(c,1-1e-12)))*sqrt(2*L-2);
end
function x=notch(x,fs,bands)
for k=1:size(bands,1),[b,a]=butter(2,bands(k,:)/(fs/2),'stop');x=filtfilt(b,a,x);end
end
function s=keepWindows(s,N,valid)
s=s(:);good=false(size(s));for k=1:numel(s),good(k)=s(k)>=1 && s(k)+N-1<=numel(valid) && all(valid(s(k):s(k)+N-1));end
s=s(good);
end
function rhs=readRHS(file,t)
rhs=[];if isempty(file),return;end
[~,~,ext]=fileparts(file);
if ismember(lower(ext),{'.csv','.tsv'})
 if strcmpi(ext,'.tsv'), delimiter='\t'; else, delimiter=','; end
 T=readtable(file,'FileType','text','Delimiter',delimiter,'TextType','string');
 if all(ismember({'trial_type','lsl_time'},T.Properties.VariableNames))
  T.Type=T.trial_type; T.Time_s=T.lsl_time;
 end
 assert(all(ismember({'Type','Time_s'},T.Properties.VariableNames)),'Event table requires Type,Time_s or trial_type,lsl_time; relative onset alone is insufficient.');
 rhs=double(T.Time_s(ismember(upper(string(T.Type)),["RHS","HS_R"])));
else
 S=load(file);
 if isfield(S,'rhsTime'),rhs=double(S.rhsTime(:));
 elseif isfield(S,'HS_R') && isfield(S.HS_R,'timestamps'),rhs=double(S.HS_R.timestamps(:));
 elseif isfield(S,'all_events')
  ev=S.all_events;sel=ismember(upper(string({ev.type})),["RHS","HS_R"]);rhs=double([ev(sel).time]');
 else,error('Event MAT requires rhsTime, HS_R.timestamps or all_events(type,time).');end
end
rhs=rhs(:);assert(all(isfinite(rhs)) && all(diff(rhs)>0),'RHS times must be finite and increasing; do not silently sort.');
rhs=rhs(rhs>=t(1) & rhs<=t(end));assert(numel(rhs)>=3,'Too few RHS in XDF range. Check time basis (not relative seconds).');
end
function [S,chosen,durations]=phaseWindows(rhs,t,fs,N,o,valid)
S=zeros(0,numel(o.phasePercent));chosen=[];durations=[];lastEnd=0;
for k=1:numel(rhs)-1
 d=rhs(k+1)-rhs(k);if d<o.rhsDurationRange(1)||d>o.rhsDurationRange(2),continue;end
 centers=rhs(k)+d*o.phasePercent/100;
 ss=round((centers-t(1))*fs)+1-floor(N/2);
 if min(ss)<=lastEnd || numel(keepWindows(ss,N,valid))~=numel(ss),continue;end
 S(end+1,:)=ss;chosen(end+1,1)=k;durations(end+1,1)=d;lastEnd=max(ss)+N-1;
end
end
function [locs,ready,note]=locations(file,labels)
locs=[];ready=false;note='not supplied';if isempty(file),return;end
assert(exist('topoplot','file')~=0 && exist('readlocs','file')~=0,'Start EEGLAB for topography.');
[~,~,ext]=fileparts(file);
if strcmpi(ext,'.mat')
 S=load(file);if isfield(S,'chanlocs'),raw=S.chanlocs;elseif isfield(S,'EEG'),raw=S.EEG.chanlocs;else,error('MAT needs chanlocs or EEG.');end
elseif strcmpi(ext,'.set')
 [p,n,e]=fileparts(file);E=pop_loadset('filename',[n e],'filepath',p,'loadmode','info');raw=E.chanlocs;
else,raw=readlocs(file);end
if ~isfield(raw,'theta') || ~isfield(raw,'radius') || any(arrayfun(@(r)isempty(r.theta)||isempty(r.radius),raw))
 raw=convertlocs(raw,'cart2all');
end
names=lower(string({raw.labels}));ix=zeros(size(labels));
for k=1:numel(labels)
 j=find(names==lower(labels(k)));assert(isscalar(j),'Missing/duplicate coordinate label: %s',labels(k));ix(k)=j;
end
locs=raw(ix);
assert(all(arrayfun(@(r)isscalar(r.theta)&&isscalar(r.radius)&&isfinite(r.theta)&&isfinite(r.radius),locs)),...
 'Invalid electrode coordinates.');
ready=true;note=char(string(file)+' (matched by labels; supplied coordinates, not inferred anatomy)');
end
function p=pick(pattern,titleText)
[f,d]=uigetfile(pattern,titleText);p='';if ~isequal(f,0),p=fullfile(d,f);end
end
function o=defaults(o,varargin)
for k=1:2:numel(varargin),if ~isfield(o,varargin{k}),o.(varargin{k})=varargin{k+1};end,end
end

function [A,B,cache]=prepareStep1(qcDir,o)
% Step-1 CSVs are the authority for source, sensor mapping and walking range.
assert(exist('load_xdf','file')~=0,'Start EEGLAB and add the XDF importer (load_xdf).');
assert(exist('resample','file')~=0 && exist('mscohere','file')~=0,'Signal Processing Toolbox required.');
qcFile=fullfile(qcDir,'walking_neck_channel_qc.tsv');
if ~isfile(qcFile), qcFile=fullfile(qcDir,'walking_neck_channel_qc.csv'); end
walkingFile=fullfile(qcDir,'walking_intervals.tsv');
if ~isfile(walkingFile), walkingFile=fullfile(qcDir,'walking_intervals.csv'); end
assert(isfile(qcFile),'Step-1 folder lacks walking_neck_channel_qc.tsv. Rerun Step 1 v1.5.1.');
w=readtable(walkingFile,'TextType','string');
q=readtable(qcFile,'TextType','string');
assert(all(ismember({'Session','Run','Status','File','StartTime_s','EndTime_s','SelectedSamples'},w.Properties.VariableNames)),...
 'Step-1 walking table has unsupported columns.');
sel=strcmpi(string(w.Session),string(o.session)) & str2double(string(w.Run))==str2double(string(o.run));
assert(nnz(sel)==1,'Expected one Step-1 row for session %s, run %s. Set opt.session/opt.run.',string(o.session),string(o.run));
w=w(sel,:);assert(w.Status=="SELECTED",'Step-1 walking selection is not SELECTED.');
q=sortrows(q(string(q.File)==string(w.File),:),'NeckSlot');
assert(height(q)==8 && numel(unique(q.NeckSlot))==8 && all(q.Status=="AUTO_PASS"),...
 'Need eight mapped AUTO_PASS neck channels from Step 1 for this pilot.');
xdfFile=char(w.File);if ~isempty(o.xdfFile),xdfFile=char(o.xdfFile);end
assert(isfile(xdfFile),'Original XDF missing: %s. Set opt.xdfFile if it moved.',xdfFile);
identity=directIdentity(xdfFile,struct);

cacheRoot=directDataset(o.derivativesContainer,'p3neckaligned');

cache=fullfile(cacheRoot,['sub-' identity.Subject],['ses-' identity.Session], ...
    'reports',['desc-run' identity.Run 'Aligned']);
if ~isfolder(cache), mkdir(cache); end
writeDerivativeTable(w,fullfile(cache,'task_a_walking_interval.tsv'));writeDerivativeTable(q,fullfile(cache,'neck_mapping.tsv'));
fprintf('Step 1 -> Step 2 | %s / run %s\nReading: %s\n',string(w.Session),string(w.Run),xdfFile);
st=load_xdf(xdfFile,'HandleClockSynchronization',true,'HandleJitterRemoval',true);
names=strings(numel(st),1);types=names;
for k=1:numel(st),names(k)=streamText(st{k},'name');types(k)=streamText(st{k},'type');end
writeDerivativeTable(table((1:numel(st))',names,types,'VariableNames',{'Index','Name','Type'}),fullfile(cache,'stream_inventory.tsv'));
mi=find(names==string(q.Stream(1)));assert(isscalar(mi)&&all(q.Stream==q.Stream(1)),'EMG stream missing/ambiguous.');
if isempty(o.eegStreamName),ei=find(strcmpi(types,'EEG'));else,ei=find(names==string(o.eegStreamName));end
assert(isscalar(ei),'EEG stream missing/ambiguous. Inspect stream_inventory.tsv and set opt.eegStreamName.');
E=st{ei};M=st{mi};ec=o.eegChannels(:);ci=double(q.Channel(:));
assert(all(isfinite(ec)&ec>=1&ec==fix(ec)&ec<=size(E.time_series,1)) && numel(unique(ec))==numel(ec),...
 'Invalid EEG channel indices.');
assert(all(isfinite(ci)&ci>=1&ci==fix(ci)&ci<=size(M.time_series,1)) && numel(unique(ci))==8,...
 'Invalid Step-1 neck indices.');
assert(all(q.StreamChannels==size(M.time_series,1)),'EMG count changed since Step 1.');
[el,eu]=rawChannelMeta(E,size(E.time_series,1));[ml,~,meta]=rawChannelMeta(M,size(M.time_series,1));
for k=1:8
 assert(ml(ci(k))==string(q.Label(k)),'Neck label mismatch. Rerun Step 1.');
 pattern=['(?<![0-9])' char(string(q.SensorID(k))) '(?![0-9])'];
 assert(~isempty(regexp(jsonencode(meta{ci(k)}),pattern,'once')),'Sensor ID mismatch. Rerun Step 1.');
end
writeDerivativeTable(table((1:numel(el))',el(:),eu(:),ismember((1:numel(el))',ec),...
 'VariableNames',{'Channel','Label','Unit','Selected'}),fullfile(cache,'eeg_channel_inventory.tsv'));
assert(all(strlength(el(ec))>0),'EEG labels missing; cannot select Cz/C3/C4.');
assert(~any(contains(lower(el(ec)),["acc","trigger","marker"])),'Non-EEG labels selected. Check opt.eegChannels.');
te=double(E.time_stamps(:));tm=double(M.time_stamps(:));
checkRawAxis(te,size(E.time_series,2),'EEG');checkRawAxis(tm,size(M.time_series,2),'EMG');
a=double(w.StartTime_s);b=double(w.EndTime_s);
assert(te(1)<=a&&te(end)>=b&&tm(1)<=a&&tm(end)>=b,'Both streams must cover the complete Step-1 walking interval.');
assert(nnz(tm>=a&tm<=b)==double(w.SelectedSamples),'Walking sample count changed since Step 1. Check XDF/importer.');
[xe,re,de]=resampleRaw(E,ec,te,a,b,o.fs);[xm,rm,dm]=resampleRaw(M,ci,tm,a,b,o.fs);
% Same 2-second import guard as v0.1, enabling comparison with existing task-c data.
start=a+2;stop=b-2;assert(stop>start,'Walking interval too short.');
grid=(start-a)+(0:floor((stop-start)*o.fs))'/o.fs;
assert(grid(1)>=max(re(1),rm(1))&&grid(end)<=min(re(end),rm(end)),'Resampled coverage insufficient.');
xe=interp1(re,xe,grid,'linear');xm=interp1(rm,xm,grid,'linear');
assert(all(isfinite(xe(:)))&&all(isfinite(xm(:))),'Nonfinite aligned signals.');
xe=xe-mean(xe,1);xm=xm-mean(xm,1);sharedTime=a+grid;
assert(all(std(xe)>0)&&all(std(xm)>0),'Constant analysis channel.');
% Cache retains old Task-C input contract. Final Step-2 statistics are recomputed
% from these aligned data with the new shared protocol and analysis filters.
opt=struct('fs',o.fs,'windowSeconds',o.windowSeconds,'overlap',0,'maxFrequency',100);
N=round(opt.windowSeconds*opt.fs);assert(N>=4,'Invalid window length.');
starts=(1:N:size(xe,1)-N+1)';assert(numel(starts)>2,'Not enough windows.');
win=hann(N,'periodic');C=[];
for k=1:8
 [v,f]=mscohere(xe,xm(:,k),win,0,N,opt.fs);
 if k==1,C=nan(numel(f),size(xe,2),8);end
 C(:,:,k)=v;
end
windowTable=table(starts,starts+N-1,sharedTime(starts),sharedTime(starts+N-1),...
 'VariableNames',{'StartSample','EndSample','StartXDF_s','LastSampleXDF_s'});
provenance=struct('xdfFile',xdfFile,'qcDir',qcDir,...
 'eegStream',names(ei),'emgStream',names(mi),'EEGNativeUnits',eu(ec),...
 'EMGUnit','mV, user confirmed, no numeric scaling','reference','original acquisition reference',...
 'manualReview','NOT_APPLIED','synchronization','COMMON_CLOCK_ONLY_NOT_VALIDATED',...
 'EEGTiming',de,'EMGTiming',dm,'cachePurpose','Unnotched Task-C input; final Step2 results are in p3neckcoherence');
eegLabels=el(ec);neckLabels="Neck"+compose('%02d',q.NeckSlot);
save(fullfile(cache,'aligned_pre.mat'),'xe','xm','sharedTime','ec','ci','opt','provenance','-v7.3');
save(fullfile(cache,'coherence_pre.mat'),'C','f','opt','provenance','windowTable','eegLabels','neckLabels','q','w','-v7.3');
writeDerivativeTable(windowTable,fullfile(cache,'welch_windows.tsv'));
directJSON(fullfile(cache,'desc-aligned_provenance.json'),provenance);
A=struct('xe',xe,'xm',xm,'sharedTime',sharedTime,'opt',opt,'provenance',provenance);
B=struct('eegLabels',eegLabels,'neckLabels',neckLabels,'q',q,'w',w,'provenance',provenance);
fprintf('Automatic Task-C compatible input saved: %s\n',cache);
end
function checkRawAxis(t,n,label)
assert(numel(t)==n&&numel(t)>2&&all(isfinite(t))&&all(diff(t)>0),'Invalid %s timestamps.',label);
end
function [y,tr,d]=resampleRaw(st,c,t,a,b,fsOut)
mask=t>=a-5&t<=b+5;t=t(mask);x=double(st.time_series(c,mask))';dt=diff(t);
assert(all(isfinite(x(:)))&&max(dt)<=5*median(dt),'Nonfinite signal or timestamp gap; do not interpolate across it.');
assert(fsOut>200&&1/median(dt)>=.99*fsOut,'Invalid target rate; must exceed 200 Hz and not exceed input rate.');
d=struct('medianFs',1/median(dt),'maxGap_s',max(dt),'firstXDF_s',t(1),'lastXDF_s',t(end));
[y,tr]=resample(x,t-a,fsOut);tr=tr(:);
end
function s=streamText(st,k)
s="";if isfield(st.info,k),s=rawScalar(st.info.(k));end
end
function s=rawScalar(x)
while iscell(x)&&isscalar(x),x=x{1};end
s=string(x);if isempty(s),s="";else,s=s(1);end
end
function [labels,units,metadata]=rawChannelMeta(st,n)
labels=repmat("",1,n);units=labels;metadata=repmat({struct},1,n);
d=st.info.desc;while iscell(d),d=d{1};end
ch=d.channels;while iscell(ch),ch=ch{1};end
ch=ch.channel;
for k=1:min(n,numel(ch))
 if iscell(ch),v=ch{k};else,v=ch(k);end
 metadata{k}=v;
 if isfield(v,'label'),labels(k)=rawScalar(v.label);end
 if isfield(v,'unit'),units(k)=rawScalar(v.unit);end
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
