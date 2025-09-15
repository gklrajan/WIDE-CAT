function analyze_frequency_responses_regression(...
    dff_signals, stim_periods_per_slice, tone_sequence,...
    hex_rois, brain_mask, frames_per_volume, stim_start_volume)
% analyze_frequency_responses_regression
%   Voxel-level (slice-by-slice ROI) regression of ΔF/F to stimulus regressor
%   Inputs:
%     dff_signals: [nSlices × nVols × nROIs_per_slice] ΔF/F time-series
%     hex_rois   : cell array of size nSlices, each a cell of ROI masks [H×W]
%     brain_mask : [H × W × nSlices] logical mask of imaged volume
%     tone_sequence, stim_start_volume: stimulus timing info
%   Steps:
%     1) Build GCaMP6s kernel and convolve with stimulus vector per frequency
%     2) Flatten per-slice ROI time-series into matrix [nVols × (nSlices*nROIs)]
%     3) For each flattened ROI trace, regress ΔF/F = β0 + β1*regressor
%     4) Rank β1 and select top top_pct percent per frequency
%     5) Plot aligned traces and overlay selected ROI masks

    %% PARAMETERS
    top_pct   = 1;    % top percent of slice-by-slice ROIs
    prePlot   = 1;    % volumes before stim
    postPlot  = 4;    % volumes after stim
    dt        = 1.9;  % sec per volume
    tau_rise  = 0.7;  % GCaMP rise time
    tau_decay = 2.0;  % GCaMP decay time

    %% DIMENSIONS
    [nSlices, nVols, nROIs] = size(dff_signals);
    H = size(brain_mask,1);
    W = size(brain_mask,2);
    totalROIs = nSlices * nROIs;

    %% FLATTEN ROI TRACES
    % Permute to [nVols × nSlices × nROIs], then reshape to [nVols × totalROIs]
    dff_perm = permute(dff_signals, [2 1 3]);    % [nVols × nSlices × nROIs]
    dffV = reshape(dff_perm, nVols, []);        % [nVols × totalROIs]

    %% BUILD GCaMP6s KERNEL
    t = 0:10;
    ts = t * dt;
    kernel = (1 - exp(-ts ./ tau_rise)) .* exp(-ts ./ tau_decay);
    kernel = kernel / sum(kernel);

    %% MAP FREQUENCIES → STIMULUS VOLUMES
    freqs = unique(tone_sequence);
    freqMap = containers.Map('KeyType','double','ValueType','any');
    for i = 1:numel(tone_sequence)
        vol = stim_start_volume + (i-1)*6;
        if vol <= nVols
            f = tone_sequence(i);
            if ~isKey(freqMap, f)
                freqMap(f) = [];
            end
            freqMap(f) = [freqMap(f); vol];
        end
    end

    %% PREP FIGURES
    brain2D = any(brain_mask,3);
    fTr = figure('Name','Stim-Aligned Traces','Position',[100 100 1200 800]);
    tiledlayout(fTr,3,5,'Padding','compact','TileSpacing','compact');
    fMk = figure('Name','Top ROI Masks','Position',[100 100 1200 800]);
    tiledlayout(fMk,3,5,'Padding','compact','TileSpacing','compact');

    %% LOOP OVER FREQUENCIES
    for idxF = 1:numel(freqs)
        f = freqs(idxF);
        vols = freqMap(f);
        if isempty(vols)
            continue;
        end

        % Stimulus regressor
        stim = zeros(nVols,1);
        stim(vols) = 1;
        reg = conv(stim, kernel, 'same');

        % Regression for each slice-by-slice ROI
        X = [ones(nVols,1), reg];       % [nVols × 2]
        B = X \ dffV;                   % [2 × totalROIs]
        beta1 = B(2,:)';                % [totalROIs × 1]

        % Select top percent
        nTop = ceil(totalROIs * top_pct/100);
        [~, topIdx] = maxk(beta1, nTop);

        % Convert linear indices to (slice, roi) pairs
        [sliceID, roiID] = ind2sub([nSlices, nROIs], topIdx);

        % Plot aligned traces
        aligned = nan(nTop, prePlot+1+postPlot, numel(vols));
        for vj = 1:numel(vols)
            vol = vols(vj);
            frames = (vol-prePlot):(vol+postPlot);
            valid = frames >= 1 & frames <= nVols;
            aligned(:, valid, vj) = dffV(frames(valid), topIdx)';
        end
        meanTrace = squeeze(nanmean(aligned,3));
        gm = nanmean(meanTrace,1);

        figure(fTr);
        nexttile;
        plot(-prePlot:postPlot, meanTrace','Color',[0.7 0.7 0.7 0.3]); hold on;
        plot(-prePlot:postPlot, gm,'k','LineWidth',2);
        xline(0,'--r'); title(sprintf('%d Hz', f));
        xlabel('Vol offset'); ylabel('ΔF/F'); hold off;

        % Overlay ROI masks
        activeMask = false(H, W, nSlices);
        for k = 1:nTop
            s = sliceID(k);
            r = roiID(k);
            activeMask(:,:,s) = activeMask(:,:,s) | hex_rois{s}{r};
        end
        mask2D = any(activeMask,3);

        figure(fMk);
        nexttile;
        imagesc(brain2D); colormap(gray); axis image off; axis ij; hold on;
        redLayer = cat(3, ones(H,W), zeros(H,W), zeros(H,W));
        hImg = imshow(redLayer); set(hImg,'AlphaData',mask2D*0.5);
        title(sprintf('%d Hz', f)); hold off;
    end
end
