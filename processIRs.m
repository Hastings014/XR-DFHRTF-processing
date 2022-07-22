close all
clear

addpath('tools/')
addpath('tools/invFIR/')
addpath('tools/VoronoiSphere/')
addpath('tools/TriangleRayIntersection/')

addpath('../API_MO/API_MO/')

dirlist = dir('data/*');
% key = '20201217-122pt-2.5m-dayton_vt';
% key = '20201217-122pt-2.5m-canford_vt';
% key = '20211012-q2_tr';
% key = '20211105-A-Jan';
% key = '20211126-XR-TR';
key = '20211126-XR-Gavin';
% key = '20220223-XR-TR_median';

% filter directories
idx = [];
for i = 1:length(dirlist)
    if contains(dirlist(i).name,key)
        idx = [idx i];
    end
end
dirlist = dirlist(idx);

for i = 1:length(dirlist)
    subjectdir = [dirlist(i).folder '/' dirlist(i).name '/'];
    load([subjectdir 'irBank.mat'])
    mkdir([subjectdir 'figures/'])
    plotMagnitudes(irBank, '1-measured', [subjectdir 'figures/'])
    
    % headphone EQ
%     hpEQ(hpirBank, subjectdir)
    
    % HMD influence correction(ITD and magnitude)
%     irBank = hmdCorrection(irBank);

    % time domain windowing
    plotting = 'false';
    irBank = winIRs(irBank, plotting, [subjectdir 'figures/windowing/']); % set 'true' to save plots
    plotMagnitudes(irBank, '2-win', [subjectdir 'figures/'])

    % calculate FF measurement inv filter and normalize all hrirs
    % do the low-frequency extension
    plotting = 'true';
    irBank = normalizeIRs(irBank, plotting, [subjectdir 'figures/']);
    plotMagnitudes(irBank, '3-raw', [subjectdir 'figures/'])

    % diffuse-field equalization
    dfe_enabled = true;
    plotting = 'true';
    irBank = dfeHRIRs(irBank, dfe_enabled, plotting, [subjectdir 'figures/']);
    plotMagnitudes(irBank, '4-dfe', [subjectdir 'figures/'])

    % save sofa file
    saveAsSofa(irBank, subjectdir,'raw')
    saveAsSofa(irBank, subjectdir,'dfe')
    
    % save ambix config file
    addpath('../adt/')
    adt_initialize
    saveAsAmbix(irBank, subjectdir)

    save([subjectdir 'irBankProcessed.mat'], 'irBank')
    load([subjectdir 'irBankProcessed.mat'])
    
    % do barycentric interpolation of hrirs using time alignment
    interpHrirBank = interpHRIRs(irBank,'raw','align');
    saveAsSofa(interpHrirBank,subjectdir,'interp-raw')
    
    interpHrirBank = interpHRIRs(irBank,'dfe','align');
    saveAsSofa(interpHrirBank,subjectdir,'interp-dfe')
end

%% Functions
function hpEQ(hpirBank, subjectdir)
    % calculate average magnitude for left & right   
    for i = 1:length(hpirBank)
        if i == 1
            Nfft = size(hpirBank(i).fullIR,1);
            mag_ir_avgL = zeros(Nfft,1);
            mag_ir_avgR = zeros(Nfft,1);
            sn = 1 / length(hpirBank);
        end
        mag_ir_avgL = mag_ir_avgL + (abs(fft(hpirBank(i).fullIR(:,1), Nfft)).^2) * sn;
        mag_ir_avgR = mag_ir_avgR + (abs(fft(hpirBank(i).fullIR(:,2), Nfft)).^2) * sn;
    end
    
    mag_ir_avgL = sqrt(mag_ir_avgL);
    mag_ir_avgR = sqrt(mag_ir_avgR);

    % back to time domain
    ir_avgL = ifft(mag_ir_avgL,'symmetric');
    ir_avgR = ifft(mag_ir_avgR,'symmetric');
    ir_avgL = circshift(ir_avgL,Nfft/2,1);
    ir_avgR = circshift(ir_avgR,Nfft/2,1);
    hpir = [ir_avgL ir_avgR];
    Fs = hpirBank(1).Fs;

    % adjust levels
    [f,mag] = getMagnitude(hpir,Fs,'log');
    idmin = find(f >= 200, 1 );           % f min
    idmax = find(f <= 800, 1, 'last');    % f max
    gain1 = mean(mag(idmin:idmax,1));
    gain2 = mean(mag(idmin:idmax,2));
    hpir(:,1) = hpir(:,1) * 10^(-gain1/20);
    hpir(:,2) = hpir(:,2) * 10^(-gain2/20);
    
    % create EQ filters
    invh(:,1) = createInverseFilter(hpir(:,1), Fs, 12, [400 600]);
    invh(:,2) = createInverseFilter(hpir(:,2), Fs, 12, [400 600]);

    %% plotting
    figure('Name','HPTF + inv resp','NumberTitle','off','WindowStyle','docked');
    hold on
    box on

    [f,mag] = getMagnitude(hpir(:,1),Fs,'log');
    plot(f,mag,'-g','LineWidth',1);

    [f,mag] = getMagnitude(hpir(:,2),Fs,'log');
    plot(f,mag,'-r','LineWidth',1);

    [f,mag] = getMagnitude(invh(:,1),Fs,'log');
    plot(f,mag,'--g','LineWidth',2);

    [f,mag] = getMagnitude(invh(:,2),Fs,'log');
    plot(f,mag,'--r','LineWidth',2);

    set(gca,'xscale','log')
    grid on
    xlim([20 Fs/2]);
    ylim([-20 20]);
    %             legend('Left channel', 'Right channel','','', 'Left inverse filter', 'Right inverse filter','location','northwest')
    xlabel('Frequency (Hz)');
    ylabel('Magnitude (dB)');
    
    figure('Name','HPIR HPEQIR','NumberTitle','off','WindowStyle','docked');
    hold on
    plot(hpir(:,1))
    plot(hpir(:,2))
    plot(invh(:,1))
    plot(invh(:,2))
    
    mkdir([subjectdir '/hpeq/'])
    audiowrite([subjectdir '/hpeq/' 'hpeq.wav'], invh * 0.25, Fs)
end

function irBank = hmdCorrection(irBank)
    load('data/hmdpert_output/model_interp.mat')
    
    for i = 1:length(irBank)
        if irBank(i).ref == 0
            dist = distance(irBank(i).elevation,irBank(i).azimuth,[model_interp.el],[model_interp.az]);
            [~,idxl] = min(dist);
            dist = distance(irBank(i).elevation,irBank(i).azimuth,[model_interp.el],-[model_interp.az]);
            [~,idxr] = min(dist);
            
            % correct magnitude
            left = irBank(i).fullIR(:,1);
            right = irBank(i).fullIR(:,2);
            left = conv(model_interp(idxl).invh,left);
            right = conv(model_interp(idxr).invh,right); 

            % correct time of arrival
            dly = model_interp(idxl).dtoa_diff;
            shift = -1 * dly * 10^-6 * irBank(i).Fs;
            left = fraccircshift(left,shift);
            
            dly = model_interp(idxr).dtoa_diff;
            shift = -1 * dly * 10^-6 * irBank(i).Fs;
            right = fraccircshift(right,shift);
                  
            irBank(i).fullIR = [left right];    
        end
    end
end

function IRbank = winIRs(IRbank, plotting, save_fig_folder)
    % define window    
    win1 = hann(80).^4;
    win1 = win1(1:end/2);
    win2 = hann(200).^4;
    win2 = win2(end/2+1:end);
    win = [win1; ones(40,1); win2;];
    winshift = length(win1); % how many samples the window should be shifted forward from the peak

    Nwin = length(win);
    if mod(Nwin,2) ~= 0
        disp('wrong window length, must be even')
    end
    
    for i = 1:length(IRbank)
        irLeft = [zeros(Nwin,1); IRbank(i).fullIR(:,1);];
        irRight = [zeros(Nwin,1); IRbank(i).fullIR(:,2);];
        Fs = IRbank(i).Fs;
        
        % get ITD, direct sound sample indices, and direct sound delay
        [IRbank(i).ITD,maxL,maxR,IRbank(i).dlyL,IRbank(i).dlyR] = getITD(irLeft,irRight,Fs);

        % apply window
        winstart = fix(maxL - winshift);
        winend = winstart + Nwin - 1;
        irLeft(1:winstart-1) = 0;
        irLeft(winstart:winend) = irLeft(winstart:winend) .* win;
        irLeft(winend+1:end) = 0;
        
        winstart = fix(maxR - winshift);
        winend = winstart + Nwin - 1;
        irRight(1:winstart-1) = 0;
        irRight(winstart:winend) = irRight(winstart:winend) .* win;
        irRight(winend+1:end) = 0;
        
        % mean time of arrival for both ear signals expressed in samples
        toasmp = round(mean([maxL, maxR]));
        
        % cut irs
        preSamples = fix(0.00075 * Fs);
        afterSamples = 512 - preSamples;
        IRbank(i).winIR(:,1) = irLeft(toasmp-preSamples+1:toasmp+afterSamples);
        IRbank(i).winIR(:,2) = irRight(toasmp-preSamples+1:toasmp+afterSamples);
        
        IRbank(i).toasmp = toasmp - Nwin; % because Nwin of zeroes was added at the beginning
        IRbank(i).maxL = maxL - Nwin;
        IRbank(i).maxR = maxR - Nwin;
    end
    
    % plot ITD
    for i = 1:length(IRbank)
        IRbank(i).ITDwin = (IRbank(i).maxR - IRbank(i).maxL)  * 10^6 / IRbank(i).Fs;
    end
    figure('Name','ITD','NumberTitle','off','WindowStyle','docked');
    tiledlayout(1,2)
    lim = [-1000 1000];
    nexttile
    hold on
    plotAzEl([IRbank.azimuth],[IRbank.elevation],[IRbank.ITD], lim)
    nexttile
    hold on
    plotAzEl([IRbank.azimuth],[IRbank.elevation],[IRbank.ITDwin], lim)
    
    % plot distance
    figure('Name','distance','NumberTitle','off','WindowStyle','docked');
    scatter([IRbank.distance],[IRbank.toasmp] * 343/Fs)
    xlabel('measured distance by HMD (m)')
    ylabel('measured distance acoustically (m)')
    
    % correct gains
    ref_dist = 1.5;
    for i = 1:length(IRbank)
        if ~isnan(IRbank(i).distance)
            gain_lin = IRbank(i).distance/ref_dist;
            IRbank(i).gain = 20*log10(gain_lin);
            IRbank(i).winIR = IRbank(i).winIR * gain_lin;
        end
    end
    
    if strcmp(plotting,'true')
        figure('Name','ETC + win','NumberTitle','off','WindowStyle','docked');
        range = [-1 1];
        mkdir(save_fig_folder)
        for i = 1:length(IRbank) % this will produce lots of graphs
%         for i = randperm(length(IRbank),20) % 20 random directions
            subplot(2,2,1)
            hold on
            yyaxis left
            cla
            plot(IRbank(i).fullIR(:,1),'-b')
            xline(IRbank(i).maxL, '--k','linewidth',2)
%             xline(IRbank(i).toasmp, '--g')
            xlabel('Samples')
            ylabel('Amplitude')
            ylim(range)
            yyaxis right
            cla
            plot(IRbank(i).maxL-winshift:IRbank(i).maxL-winshift+Nwin-1,win,'--')
            ylabel('Linear gain')
            xlim([IRbank(i).maxL-Nwin IRbank(i).maxL+Nwin])
%             title(['Full BRIR (left)' ' azi ' num2str(IRbank(i).azimuth) ' ele ' num2str(IRbank(i).elevation)])
            box on
            
            legend('IR','Peak','Windowing function','Location','NorthWest')

            subplot(2,2,3)
            cla
            hold on
            plot(IRbank(i).winIR(:,1),'-b')
            xlabel('Samples')
            ylabel('Amplitude')
            ylim(range);
            xlim([0 size(IRbank(i).winIR,1)])
%             title(['Windowed BRIR (left)' ' azi ' num2str(IRbank(i).azimuth) ' ele ' num2str(IRbank(i).elevation)])
            box on

            subplot(2,2,2)
            hold on
            yyaxis left
            cla
            plot(IRbank(i).fullIR(:,2),'-b')
            xline(IRbank(i).maxR, '--k','linewidth',2)
            xline(IRbank(i).toasmp, '--g')
            xlabel('Samples')
            ylabel('Amplitude')
            ylim(range)
            yyaxis right
            cla
            plot(IRbank(i).maxR-winshift:IRbank(i).maxR-winshift+Nwin-1,win,'--')
            ylabel('Linear gain')
            xlim([IRbank(i).maxR-Nwin IRbank(i).maxR+Nwin])
%             title('Right Raw HRIR')
            box on


            subplot(2,2,4)
            cla
            hold on
            plot(IRbank(i).winIR(:,2),'-b')
            xlabel('Samples')
            ylabel('Amplitude')
            ylim(range);
            xlim([0 size(IRbank(i).winIR,1)])
%             title('Right Windowed HRIR')
            box on

            
            % save figure
            figlen = 8;
            width = 4*figlen;
            height = 2*figlen;
            set(gcf,'Units','centimeters','PaperPosition',[0 0 width height],'PaperSize',[width height]);
%             saveas(gcf,[save_fig_folder 'windowing_fig' num2str(i)  '.jpg'])
            saveas(gcf,[save_fig_folder 'windowing_fig' num2str(i)  '.pdf'])
            close
        end
    end
end

function irBank = normalizeIRs(irBank, plotting, save_fig_folder)
    % find the free-field measurements and calculate inverse filters
    for i = find([irBank.ref])
        Fs = irBank(i).Fs;
        irBank(i).invh(:,1) = createInverseFilter(irBank(i).winIR(:,1), Fs, 12, [0 0]);
        irBank(i).invh(:,2) = createInverseFilter(irBank(i).winIR(:,2), Fs, 12, [0 0]);
    end
    
    if strcmp(plotting,'true')
        % plot freefield and inverse filter
        plots_num = length(find([irBank.ref]));
        figure('Name','P0 + inv resp','NumberTitle','off','WindowStyle','docked');
        tiledlayout(ceil(sqrt(plots_num)),floor(sqrt(plots_num)))
        for i = find([irBank.ref])
            nexttile
            hold on
            box on

            [f,mag] = getMagnitude(irBank(i).winIR(:,1),irBank(i).Fs,'log');
            plot(f,mag,'-g','LineWidth',1);

            [f,mag] = getMagnitude(irBank(i).winIR(:,2),irBank(i).Fs,'log');
            plot(f,mag,'-r','LineWidth',1);

            [f,mag] = getMagnitude(irBank(i).invh(:,1),irBank(i).Fs,'log');
            plot(f,mag,'--g','LineWidth',2);

            [f,mag] = getMagnitude(irBank(i).invh(:,2),irBank(i).Fs,'log');
            plot(f,mag,'--r','LineWidth',2);

            set(gca,'xscale','log')
%             grid on
            xlim([20 Fs/2]);
            ylim([-35 35]);
            legend('Left channel', 'Right channel', 'Left inverse filter', 'Right inverse filter','location','NorthEast')
            xlabel('Frequency (Hz)');
            ylabel('Magnitude (dB)');
            
            % save figure
            figlen = 4;
            width = 4*figlen;
            height = 2.5*figlen;
            set(gcf,'Units','centimeters','PaperPosition',[0 0 width height],'PaperSize',[width height]);
            mkdir(save_fig_folder)
%             saveas(gcf,[save_fig_folder 'normalization-' num2str(i) '.png'])
            saveas(gcf,[save_fig_folder 'normalization-' num2str(i) '.pdf']) 
        end

%         % plot freefield impulse response
%         figure('Name','FF IR','NumberTitle','off','WindowStyle','docked');
%         subplot(2,1,1)
%         hold on
%         box on
%         plot(FFIR(:,1),'g')
%         plot(FFIR(:,2),'r')
%         
%         % plot inverese filter for freefield impulse response
% %         figure('Name','FF inv filter IR','NumberTitle','off','WindowStyle','docked');
%         subplot(2,1,2)
%         hold on
%         box on
%         plot(invh(:,1),'g')
%         plot(invh(:,2),'r')
    end
    
    %% filter all windowed hrirs
    for i = 1:length(irBank)
        % find the reference measurement
        ref_idx = [irBank.ref] == 1 & [irBank.lspk] == irBank(i).lspk;
        irBank(i).rawHRIR(:,1) = conv(irBank(ref_idx).invh(:,1),irBank(i).winIR(:,1));
        irBank(i).rawHRIR(:,2) = conv(irBank(ref_idx).invh(:,2),irBank(i).winIR(:,2));  
    end
    
    %% add LF extension
    for i = 1:length(irBank)
        plotting = 'false';
%         if irBank(i).azimuth == 90 && irBank(i).elevation == 0
%             plotting = 'true';
%         end
        dist = 1.5; % reference distance
        hd = 0.16; % head diameter / ear to ear distance
        dd = dist + (hd/2) * sin(deg2rad(-irBank(i).azimuth)) * cos(deg2rad(irBank(i).elevation));
        lfe_amp = 20*log10(dd/dist);
        irBank(i).rawHRIR(:,1) = LFextension(irBank(i).rawHRIR(:,1), Fs, lfe_amp, plotting);
        irBank(i).rawHRIR(:,2) = LFextension(irBank(i).rawHRIR(:,2), Fs, -lfe_amp, plotting);
    end
    
    %% cut equalized IRs
    figure('Name','raw IR truncation','NumberTitle','off','WindowStyle','docked');
    hold on
    cut_start = 1;
    cut_end = 300;
    for i = 1:length(irBank)
        plot(irBank(i).rawHRIR(:,1),'b')
        plot(irBank(i).rawHRIR(:,2),'r')
    end
    xline(cut_start,'--k')
    xline(cut_end,'--k')
    
    for i = 1:length(irBank)
        irBank(i).rawHRIR = irBank(i).rawHRIR(cut_start:cut_end,:);
    end


function lfe_h = LFextension(h, Fs, lfe_amp, plotting)    
    [acor, lag] = xcorr(h,minph(h));
    [~,index] = max(acor);
    shift = lag(index);

    lfe_kronecker = zeros(length(h),1);
    lfe_kronecker(shift) = 1 * 10^(lfe_amp/20);
    
    xfreq = 250; % crossover frequency
    filter_order = 2;    
    [B_highpass, A_highpass] = butter( filter_order, xfreq/Fs*2, 'high' );            
    [B_lowpass,  A_lowpass ] = butter( filter_order, xfreq/Fs*2, 'low'  );
    output_low = filter(B_lowpass, A_lowpass, lfe_kronecker);
    output_low = filter(B_lowpass, A_lowpass, output_low);
    output_high = filter(B_highpass, A_highpass, h);
    output_high = filter(B_highpass, A_highpass, output_high);
        
    lfe_h = output_low + output_high;
    
    if strcmp(plotting,'true')
        %% simple plot
        figure('Name','lf extension','NumberTitle','off','WindowStyle','docked');
        hold on
        [f,mag] = getMagnitude(h,Fs,'log');
        plot(f,mag,'-b','LineWidth',1);
        [f,mag] = getMagnitude(output_low,Fs,'log');
        plot(f,mag,'--g','LineWidth',2);
        [f,mag] = getMagnitude(output_high,Fs,'log');
        plot(f,mag,'--r','LineWidth',2);
        [f,mag] = getMagnitude(lfe_h,Fs,'log');
        plot(f,mag,'-m','LineWidth',1);
        legend('Original','Low-passed','High-passed','Extended','location','northwest')
        xlim([20 Fs/2]);
        ylim([-30 20]);
        set(gca,'xscale','log')
        xlabel('Frequency (Hz)');
        ylabel('Magnitude (dB)');
        box on
        
        % save figure
        figlen = 4;
        width = 4*figlen;
        height = 2.5*figlen;
        set(gcf,'Units','centimeters','PaperPosition',[0 0 width height],'PaperSize',[width height]);
        saveas(gcf,'lfe.pdf')  
        
        
%         %% advanced plot
%         figure('Name','lf extension','NumberTitle','off','WindowStyle','docked');
%         subplot(2,2,1)
%         hold on
%         plot(h)
%         plot(lfe_kronecker)
%         plot(output_low,'--','LineWidth',1)
%         plot(output_high,'--','LineWidth',1)
%         plot(lfe_h,'-','LineWidth',2)
%         xline(shift,'--k')
% 
%         legend('original','kronecker','low','high','extended','location','northeast')
%         xlim([0 256]);
%         ylim([-1 1]);
% 
%         subplot(2,2,2)
%         hold on
%         [gd,f] = grpdelay(h,1,2^10,'whole',Fs);
%         plot(f,gd,'-b','LineWidth',1);
%         [gd,f] = grpdelay(lfe_h,1,2^10,'whole',Fs);
%         plot(f,gd,'-r','LineWidth',1);
%         xlim([20 Fs/2]), ylim([-200 500])
%         xlabel('Frequency (Hz)'), ylabel('group delay in samples')
%         set(gca,'xscale','log')
%         legend('original','extended','location','southwest')
% 
%         subplot(2,2,3)
%         hold on
%         [f,mag] = getMagnitude(h,Fs,'log');
%         plot(f,mag,'-b','LineWidth',1);
%         [f,mag] = getMagnitude(output_low,Fs,'log');
%         plot(f,mag,'--g','LineWidth',2);
%         [f,mag] = getMagnitude(output_high,Fs,'log');
%         plot(f,mag,'--r','LineWidth',2);
%         [f,mag] = getMagnitude(lfe_h,Fs,'log');
%         plot(f,mag,'-m','LineWidth',1);
%         legend('original','low','high','extended','location','northwest')
%         xlim([20 Fs/2]);
%         ylim([-30 20]);
%         set(gca,'xscale','log')
%         xlabel('Frequency (Hz)');
%         ylabel('Magnitude (dB)');
% 
%         subplot(2,2,4)
%         hold on
%         [f,mag] = getPhase(h,Fs);
%         plot(f,mag,'-b','LineWidth',1);
%         [f,mag] = getPhase(output_low,Fs);
%         plot(f,mag,'--g','LineWidth',2);
%         [f,mag] = getPhase(output_high,Fs);
%         plot(f,mag,'--r','LineWidth',2);
%         [f,mag] = getPhase(lfe_h,Fs);
%         plot(f,mag,'-m','LineWidth',1);
%         legend('original','low','high','extended','location','southwest')
%         xlim([20 Fs/2]);
%     %     ylim([-40 40]);
%         set(gca,'xscale','log')
%         xlabel('Frequency (Hz)');
%         ylabel('Phase');
    end
end
end

function irBank = dfeHRIRs(irBank, dfe_enabled, plotting, save_fig_folder)
    Fs = unique([irBank.Fs]);
    
    % remove the ff measurement
%     IRbank(isnan([IRbank.azimuth])) = [];
    irBank([irBank.ref]) = [];

    % calculate weights based on solid angle of each cell
    azel = [[irBank.azimuth]',[irBank.elevation]'];
    azel = azel + randn(size(azel))*0.001; % add some noise to smooth out plotting
    [xyz(1,:), xyz(2,:), xyz(3,:)] = sph2cart(deg2rad(azel(:,1)),deg2rad(azel(:,2)),1);
    xyz = xyz ./ sqrt(sum(xyz.^2,1));
    [~, ~, voronoiboundary, s] = voronoisphere(xyz);
    
    sn = s./sum(s);
    
    % calculate average magnitude for left & right
    for i = 1:length(irBank)
        if i == 1
            Nfft = size(irBank(i).rawHRIR,1);
            mag_ir_avgL = zeros(Nfft,1);
            mag_ir_avgR = zeros(Nfft,1);
        end
        mag_ir_avgL = mag_ir_avgL + (abs(fft(irBank(i).rawHRIR(:,1), Nfft)).^2) * sn(i);
        mag_ir_avgR = mag_ir_avgR + (abs(fft(irBank(i).rawHRIR(:,2), Nfft)).^2) * sn(i);
    end

    mag_ir_avgLR = sqrt(mag_ir_avgL/2 + mag_ir_avgR/2);
    mag_ir_avgL = sqrt(mag_ir_avgL);
    mag_ir_avgR = sqrt(mag_ir_avgR);

    % back to time domain
    ir_avgLR = ifft(mag_ir_avgLR,'symmetric');
    ir_avgLR = circshift(ir_avgLR,Nfft/2,1);

    ir_avgL = ifft(mag_ir_avgL,'symmetric');
    ir_avgR = ifft(mag_ir_avgR,'symmetric');
    ir_avgL = circshift(ir_avgL,Nfft/2,1);
    ir_avgR = circshift(ir_avgR,Nfft/2,1);
    
    % inv fir Nfft and filter length
    Nfft = length(ir_avgL);
    if dfe_enabled   
        % create dfe filters
        dfeLR = createInverseFilter(ir_avgLR, Fs, 12, [0 0]);
    else
        % use "flat" filters
        dfeLR = [1; zeros(Nfft-1,1)];
    end

    %% filter hrirs with dfe filters
    for i = 1:length(irBank)
        irBank(i).dfeHRIR(:,1) = conv(dfeLR,irBank(i).rawHRIR(:,1));
        irBank(i).dfeHRIR(:,2) = conv(dfeLR,irBank(i).rawHRIR(:,2));  
    end
    
    %% cut equalized IRs
    figure('Name','dfe IR truncation','NumberTitle','off','WindowStyle','docked');
    hold on
    cut_start = 1;
    cut_end = cut_start + 255;
    for i = 1:length(irBank)
        plot(irBank(i).dfeHRIR(:,1),'b')
        plot(irBank(i).dfeHRIR(:,2),'r')
    end
    xline(cut_start,'--k')
    xline(cut_end,'--k')
    
    for i = 1:length(irBank)
        irBank(i).dfeHRIR = irBank(i).dfeHRIR(cut_start:cut_end,:);
    end
    
    if plotting == "true"        
        
        figure('Name','voronoi diagram','NumberTitle','off','WindowStyle','docked');
        hold on
        n = size(xyz,2);
        w = s - min(s);
        w = w ./ max(w);
        w = round(w*255)+1;
            plot3(xyz(1,:),xyz(2,:),xyz(3,:),'ko');
%         text(xyz(1,:),xyz(2,:),xyz(3,:),num2str(w))
        clmap = cool();
        ncl = size(clmap,1);
        for k = 1:n
            X = voronoiboundary{k};
            cl = clmap(w(k),:);
            fill3(X(1,:),X(2,:),X(3,:),cl,'EdgeColor','w');
        end
        axis('equal');
        view(40,10)
        axis([-1 1 -1 1 -1 1]);
        
        % plot avereged hrirs and dfe filter response 
        figure('Name','avg resp + dfe filter','NumberTitle','off','WindowStyle','docked');
        hold on
        box on
%         grid on
        [f,mag] = getMagnitude(ir_avgLR,Fs,'log');
        plot(f,mag,'-b','LineWidth',1);
        [f,mag] = getMagnitude(ir_avgL,Fs,'log');
        plot(f,mag,'-g','LineWidth',1);
        [f,mag] = getMagnitude(ir_avgR,Fs,'log');
        plot(f,mag,'-r','LineWidth',1);
        [f,mag] = getMagnitude(dfeLR,Fs,'log');
        plot(f,mag,'--b','LineWidth',1.5);
                
        set(gca,'xscale','log')
        xlim([100 Fs/2]);
        ylim([-20 20]);
        ylabel('Magnitude (dB)')
        xlabel('Frequency (Hz)')
        legend('Left and Right Ear Average', 'Left Ear Average', 'Right Ear Average', 'DFE Filter','Location','southwest')
%         title('DFE filter')
        
        % save figure
        figlen = 4;
        width = 4*figlen;
        height = 2.5*figlen;
        set(gcf,'Units','centimeters','PaperPosition',[0 0 width height],'PaperSize',[width height]);
        mkdir(save_fig_folder)
        saveas(gcf,[save_fig_folder 'dfe.pdf'])        
%         close
    end
end