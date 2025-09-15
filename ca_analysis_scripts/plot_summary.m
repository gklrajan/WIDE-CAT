function plot_summary(suffix, dataset, pre_vols, post_vols, stim_duration, ...
    mean_vol, brain_mask, hex_rois, ...
    corr_sust, corr_onset, ...
    dff_data, sustained_regressor, onset_regressor, ...
    top_sust, top_onset, ...
    stim_onsets, expected_len, gauss_sigma, dfF_path)

figname = string(dataset) + " " + string(suffix);
f = figure('Name', figname, 'Position', [100 100 2000 1000]);

% Subplot 1: Mean aligned traces of top sustained ROIs
subplot(2,3,1); hold on;
if ~isempty(top_sust)
    for idx = top_sust(:)'
        aligned_traces = {};
        for s = stim_onsets(:)'
            idxs = s-pre_vols : s+stim_duration+post_vols-1;
            if min(idxs)<1 || max(idxs)>size(dff_data,1), continue; end
            trace = dff_data(idxs,idx)';
            if length(trace)==expected_len
                aligned_traces{end+1} = trace;
            end
        end
        if ~isempty(aligned_traces)
            A_mat = cell2mat(aligned_traces');
            plot(nanmean(A_mat,1));
        end
    end
else
    text(0.5,0.5,'No ROIs above threshold','HorizontalAlignment','center');
end
xline(pre_vols+1,'--k');
xline(pre_vols+stim_duration,'--k');
xlabel('Aligned Volumes');
ylabel('dF/F');
title(['Aligned dF/F (Top Sustained - ' suffix ')']);

% Subplot 2: Mean aligned traces of top onset ROIs
subplot(2,3,2); hold on;
if ~isempty(top_onset)
    for idx = top_onset(:)'
        aligned_traces = {};
        for s = stim_onsets(:)'
            idxs = s-pre_vols : s+stim_duration+post_vols-1;
            if min(idxs)<1 || max(idxs)>size(dff_data,1), continue; end
            trace = dff_data(idxs,idx)';
            if length(trace)==expected_len
                aligned_traces{end+1} = trace;
            end
        end
        if ~isempty(aligned_traces)
            A_mat = cell2mat(aligned_traces');
            plot(nanmean(A_mat,1));
        end
    end
else
    text(0.5,0.5,'No ROIs above threshold','HorizontalAlignment','center');
end
xline(pre_vols+1,'--k');
xline(pre_vols+stim_duration,'--k');
xlabel('Aligned Volumes');
ylabel('dF/F');
title(['Aligned dF/F (Top Onset - ' suffix ')']);

% Subplot 3: Sustained correlation histogram
subplot(2,3,3);
histogram(corr_sust,30);
xlabel('Correlation Sustained');
ylabel('Count');
title(['Sustained Correlation (' suffix ')']);

% Subplot 4: Onset correlation histogram
subplot(2,3,4);
histogram(corr_onset,30);
xlabel('Correlation Onset');
ylabel('Count');
title(['Onset Correlation (' suffix ')']);

% Subplot 5: Sustained correlation map (only top ROIs)
subplot(2,3,5); hold on;
proj = max(mean_vol,[],3);
imagesc(mat2gray(proj)); colormap(gray); axis image off;
corr_map_sust = zeros(size(proj));
if ~isempty(top_sust)
    roi_idx = 0;
    for z=1:size(brain_mask,3)
        rois = hex_rois{z};
        for r=1:numel(rois)
            roi_idx = roi_idx + 1;
            if ~ismember(roi_idx, top_sust)
                continue;
            end
            roi_mask = rois{r};
            [yy,xx]=find(roi_mask);
            if isempty(xx), continue; end
            cx=mean(xx); cy=mean(yy);
            [X,Y]=meshgrid(1:size(proj,2),1:size(proj,1));
            gauss_blob = exp(-((X-cx).^2 + (Y-cy).^2)/(2*gauss_sigma^2));
            corr_map_sust = corr_map_sust + gauss_blob * corr_sust(roi_idx);
        end
    end
    if max(corr_map_sust(:))>0
        corr_map_sust = corr_map_sust / max(corr_map_sust(:));
        h=imagesc(corr_map_sust); colormap(gca,jet); set(h,'AlphaData',corr_map_sust*0.8);
        colorbar;
    else
        text(0.5,0.5,'No ROI map','HorizontalAlignment','center');
    end
else
    text(0.5,0.5,'No ROIs above threshold','HorizontalAlignment','center');
end
title(['Sustained Corr Map (' suffix ')']);

% Subplot 6: Onset correlation map (only top ROIs)
subplot(2,3,6); hold on;
imagesc(mat2gray(proj)); colormap(gray); axis image off;
corr_map_onset = zeros(size(proj));
if ~isempty(top_onset)
    roi_idx = 0;
    for z=1:size(brain_mask,3)
        rois = hex_rois{z};
        for r=1:numel(rois)
            roi_idx = roi_idx + 1;
            if ~ismember(roi_idx, top_onset)
                continue;
            end
            roi_mask = rois{r};
            [yy,xx]=find(roi_mask);
            if isempty(xx), continue; end
            cx=mean(xx); cy=mean(yy);
            [X,Y]=meshgrid(1:size(proj,2),1:size(proj,1));
            gauss_blob = exp(-((X-cx).^2 + (Y-cy).^2)/(2*gauss_sigma^2));
            corr_map_onset = corr_map_onset + gauss_blob * corr_onset(roi_idx);
        end
    end
    if max(corr_map_onset(:))>0
        corr_map_onset = corr_map_onset / max(corr_map_onset(:));
        h=imagesc(corr_map_onset); colormap(gca,hot); set(h,'AlphaData',corr_map_onset*0.8);
        colorbar;
    else
        text(0.5,0.5,'No ROI map','HorizontalAlignment','center');
    end
else
    text(0.5,0.5,'No ROIs above threshold','HorizontalAlignment','center');
end
title(['Onset Corr Map (' suffix ')']);

% Save figure
saveas(f, fullfile(dfF_path, ['qc_summary_' suffix '.png']));
close(f);

end