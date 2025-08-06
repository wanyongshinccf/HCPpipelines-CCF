function readHCPPhysioLog(pfile,tfile,odir,tr,tdim,zdim,smsfactor)
% read X_log.txt file from linked physio data and store it to AFNI format
pp=load(pfile);
trig=pp(:,1);
card=pp(:,2);
resp=pp(:,3);

% read
tshift=load(tfile);

% calculate
zmbdim = zdim/smsfactor;
SR_sli=tr/zmbdim;
TA_epi=tr*tdim;

% fixed 
SR_physio=1000/2.5; % 2.5msms
RSR_physio=40; % since SR_sli = 80

% sanity check
tdim_physio = round(length(trig)/SR_physio/tr);
TA_physio = tr*tdim_physio;
if (tdim ~= tdim_physio); 
  disp('Warning Physio file size is different from the corresponding EPI'); 
  disp([ 'tdim of EPI = ' num2str(tdim)]);
  disp([ 'tdim of physiofile = ' num2str(tdim_physio)])
  disp('Truncate physio file based on EPI size')
end

temp = diff(trig);
extrig=find(temp==1); extrig = [1; extrig];
temp2 = diff(extrig); temp2(1)=temp2(1)+1;
tp_exp = tr*SR_physio;
if length(find(temp2~=tp_exp))
    disp(['WARNING: physio recording or TR is dithered at '])
    disp(num2str(find(temp2~=tp_exp)))
end

% resample card and resp with SRS_physio
t1 = 0:1/SR_physio:TA_physio+1; t1(length(trig)+1:end)=[];
t2 = 0:1/RSR_physio:TA_epi; t2(end)=[];
card_res = pchip(t1,card,t2);
resp_res = pchip(t1,resp,t2);

% save 
fp=fopen([odir '/card_pmu.dat'],'w'); 
fprintf(fp,'%g\n',card_res); fclose(fp); 
fp=fopen([odir '/resp_pmu.dat'],'w'); 
fprintf(fp,'%g\n',resp_res); fclose(fp);

% snipped from run_RetroTS
Opts.ShowGraphs   = 0; 
Opts.VolTR        = tr; 
Opts.Nslices      = zdim; 
Opts.SliceOffset  = tshift;
Opts.SliceOrder   = 'Custom';
Opts.PhysFS       = RSR_physio; 
Opts.Quiet        = 1; 
Opts.RVT_out      = 0; % note no RVT here, feel free to modify it

RespOpts=Opts;
CardOpts=Opts;
% save Respiratory signals
if sum(std(resp_res)) ~= 0
  % save RetroTS.Resp.slicebase.1D here
  RespOpts.Prefix   = [odir '/RetroTS.PMU.resp'];
  RespOpts.Respfile = [odir '/resp_pmu.dat'];
  [SN, RESP, CARD]  = RetroTS_CCF(RespOpts);
  % register resp file for full RETROICOR 
  Opts.Respfile     = [odir '/resp_pmu.dat'];
end

if sum(std(card_res)) ~= 0
  CardOpts.Prefix   = [odir '/RetroTS.PMU.card'];
  CardOpts.Cardfile = [odir '/card_pmu.dat'];
  [SN, RESP, CARD]  = RetroTS_CCF(CardOpts);
  % register card file for full RETROICOR
  Opts.Cardfile     = [odir '/card_pmu.dat'];
end

% save RetroTS.PMU.slicebase.1D
Opts.Prefix       = [odir '/RetroTS.PMU'];
[SN, RESP, CARD] = RetroTS_CCF(Opts);

% The below is to generate resp/card phase function
% See Shin, Koening and Lowe, Neuroimage 2022
if sum(std(card_res)) ~= 0
  cardRF = zeros(length(CARD.tntrace)-1,100);
  nstd = std(CARD.v);
  for n = 1:length(CARD.tntrace)-1
    sigincycle = CARD.v(find(CARD.t == CARD.tntrace(n)): find(CARD.t == CARD.tntrace(n+1)))./nstd;
    t = 0:1000/length(sigincycle):1000;
    cardRF(n,:) = pchip(t(2:end),sigincycle',10:10:1000);
  end
  CARD.phasefunc=mean(cardRF);
end

if sum(std(resp_res)) ~= 0
  respRF = zeros(length(RESP.tntrace)-1,100);
  nstd = std(RESP.v);
  for n = 1:length(RESP.tntrace)-1
    sigincycle = RESP.v(find(RESP.t == RESP.tntrace(n)): find(RESP.t == RESP.tntrace(n+1)))./nstd;
    t = 0:1000/length(sigincycle):1000;
    respRF(n,:) = pchip(t(2:end),sigincycle',10:10:1000);
  end
  RESP.phasefunc=mean(respRF);
end

h = figure('visible','off');

if sum(std(card_res)) ~= 0
  subplot(2,3,1); plot(CARD.t,CARD.v); xlim([0 30]); 
  title('Card signal (< 30s)')
  text(5,-1000,sprintf('null pt = %6d',length(find(card_res==0))))
  text(5,-1500,sprintf('sat pt = %6d',length(find(card_res==4095))))
  
  subplot(2,3,2); errorbar(1:100,mean(cardRF,1),std(cardRF,1));xlim([0 100]);title('Card cycle');
  text(30,-1, sprintf('SD = %3.2f', mean(std(cardRF))));
  
  subplot(2,3,3);hist((CARD.prd),30)
  title(sprintf('Card period: %3.1f +/- %3.1f', mean(CARD.prd), std(CARD.prd)))
  ylabel('Count'); xlabel('seconds'); 
  
end

if sum(std(resp_res)) ~= 0
  subplot(2,3,4); plot(RESP.t,RESP.v); xlim([0 60]); 
  title('Resp signal (<1min)')
  text(5,-1000,sprintf('null pt = %6d',length(find(resp_res==0))))
  text(5,-1500,sprintf('sat pt = %6d',length(find(resp_res==4095))))

  subplot(2,3,5); errorbar(1:100,mean(respRF,1),std(respRF,1));xlim([0 100]);title('Resp cycle')
  text(30,-1, sprintf('SD = %3.2f', mean(std(respRF))));ylim([-2 2])

  subplot(2,3,6);hist((RESP.prd),30)
  title(sprintf('Resp period: %3.1f +/- %3.1f', mean(RESP.prd), std(RESP.prd)))
  ylabel('Count'); xlabel('seconds'); 
end
saveas(gcf,[odir '/PMU_qualtiycheck.png']);

% save
save([odir '/RetroTS.PMU.mat'],'SN','RESP','CARD');


