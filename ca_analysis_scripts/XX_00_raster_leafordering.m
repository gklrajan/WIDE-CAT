%% 
%
% Changes from original:
%   1. RdBu_r colormap  (blue = suppressed, red = activated)
%   2. Tighter z-score clip (±2.0) for better contrast
%   3. Taller figure (18 cm) so voxels are not squished
%   4. Cluster boundary lines drawn over heatmap
%   5. Random voxel subsampling (avoids spatial bias)
%   6. Y-axis label clarified to "Voxel (clustered order)"
%
% Output: heatmap_leaf_ordered.pdf + .png
%         saved to dfF/paper_figures_pretty/

clear; clc;

%% ===================== USER PARAMETERS ====================
INPUT_ROOT  = 'D:\Gokul\2026_data\test';
RESULT_ROOT = fullfile(INPUT_ROOT, 'rl_deconvolved');

% High-pass filter
DO_HIGHPASS = true;
HP_METHOD   = 'movmedian';
HP_WIN_VOL  = 30;

% Voxel / time limits
MAX_VOXELS  = 2000;
MAX_TIME    = 120;

% Z-score clip — tightened from 2.5 → 2.0 for better contrast
ZSCORE_CLIP = 2.0;

% Colormap — RdBu_r: blue=suppressed, red=activated
CMAP_NAME   = 'rdbu_r';

% Cluster boundaries drawn on top of heatmap
N_CLUSTERS      = 6;       % number of clusters to delineate
BOUNDARY_COLOR  = [1 1 1]; % white lines between clusters
BOUNDARY_WIDTH  = 1.2;
BOUNDARY_ALPHA  = 0.85;

% Output DPI
DPI = 300;

%% ===================== FIND DATASETS =====================
D    = dir(RESULT_ROOT);
isub = [D.isdir] & ~ismember({D.name},{'.','..'});
subdirs = {D(isub).name};
fprintf('Found %d datasets\n', numel(subdirs));

%% ===================== MAIN LOOP =====================
for dataset_idx = 1:numel(subdirs)

    subn    = subdirs{dataset_idx};
    outDir  = fullfile(RESULT_ROOT, subn);
    dfF_dir = fullfile(outDir, 'dfF');

    dff_path = fullfile(dfF_dir, 'dff_signals.mat');
    if ~exist(dff_path,'file')
        fprintf('SKIP %s — no dff_signals.mat\n', subn); continue;
    end
    fprintf('\n[%d/%d] %s\n', dataset_idx, numel(subdirs), subn);

    %% ── Load dF/F ────────────────────────────────────────────────────────
    fprintf('  Loading dff...\n');
    A   = load(dff_path);
    dff = A.dff;

    % Reshape to [nT x nVox]
    if ndims(dff) == 3
        dff = permute(dff, [2,1,3]);
        dff = reshape(dff, size(dff,1), []);
    end
    dff = single(dff);
    [nT, nVox] = size(dff);
    fprintf('  dff: %d timepoints x %d voxels\n', nT, nVox);

    % Truncate time
    nT_show = min(nT, MAX_TIME);
    dff     = dff(1:nT_show, :);

    %% ── High-pass filter ─────────────────────────────────────────────────
    if DO_HIGHPASS
        fprintf('  High-pass (%s, win=%d)...\n', HP_METHOD, HP_WIN_VOL);
        if strcmpi(HP_METHOD, 'movmedian')
            slow = movmedian(dff, HP_WIN_VOL, 1, 'omitnan');
        else
            slow = movmean(dff, HP_WIN_VOL, 1, 'omitnan');
        end
        dff = dff - slow; clear slow;
    end

    %% ── Subsample voxels — RANDOM (avoids spatial bias) ─────────────────
    if nVox > MAX_VOXELS
        fprintf('  Subsampling: %d → %d voxels (random)\n', nVox, MAX_VOXELS);
        rng(42, 'twister');                        % reproducible
        sel_idx = sort(randperm(nVox, MAX_VOXELS));
        dff     = dff(:, sel_idx);
        nVox    = MAX_VOXELS;
    end

    %% ── Z-score each voxel ───────────────────────────────────────────────
    fprintf('  Z-scoring...\n');
    mu  = mean(dff, 1, 'omitnan');
    sg  = std(dff,  0, 1, 'omitnan');
    sg(sg < eps) = 1;
    dff_z = (dff - mu) ./ sg;
    dff_z = max(-ZSCORE_CLIP, min(ZSCORE_CLIP, dff_z));

    %% ── Hierarchical clustering + optimal leaf order ─────────────────────
    fprintf('  Clustering + optimal leaf order...\n');
    D_corr     = pdist(dff_z', 'correlation');
    Z_link     = linkage(D_corr, 'ward');
    leaf_order = optimalleaforder(Z_link, D_corr);

    % Reorder matrix: [nVox x nT] for imagesc
    dff_ordered = dff_z(:, leaf_order)';

    % Cluster assignments in leaf order (for boundary lines)
    cluster_ids         = cluster(Z_link, 'maxclust', N_CLUSTERS);
    cluster_ids_ordered = cluster_ids(leaf_order);
    boundaries          = find(diff(cluster_ids_ordered) ~= 0) + 0.5;

    fprintf('  Done. %d cluster boundaries found.\n', numel(boundaries));

    %% ── Figure ───────────────────────────────────────────────────────────
    fprintf('  Plotting...\n');

    % Taller figure: 18 cm height (was 14)
    fig = figure('Color','w', ...
        'Units','centimeters','Position',[2 2 24 18], ...
        'PaperUnits','centimeters','PaperSize',[24 18]);

    ax = axes('Parent', fig, ...
        'Position',[0.09 0.11 0.78 0.82], ...
        'Color','w','FontSize',10,'FontName','Helvetica Neue', ...
        'TickDir','out','Box','off', ...
        'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15]);

    imagesc(ax, (1:nT_show), (1:nVox), dff_ordered);
    caxis(ax, [-ZSCORE_CLIP ZSCORE_CLIP]);

    % Colormap
    switch lower(CMAP_NAME)
        case 'rdbu_r'
            colormap(ax, rdbu_r(256));
        case 'gray'
            colormap(ax, gray(256));
        case 'inferno'
            if exist('inferno','file'), colormap(ax, inferno(256));
            else, colormap(ax, hot(256)); end
        otherwise
            colormap(ax, rdbu_r(256));
    end

    % ── Cluster boundary lines ────────────────────────────────────────────
    hold(ax, 'on');
    for b = boundaries'
        yline(ax, b, ...
            'Color',  BOUNDARY_COLOR, ...
            'LineWidth', BOUNDARY_WIDTH, ...
            'Alpha',  BOUNDARY_ALPHA);
    end
    hold(ax, 'off');

    % ── Colorbar ──────────────────────────────────────────────────────────
    cb = colorbar(ax, 'Location','eastoutside');
    cb.FontSize        = 9;
    cb.FontName        = 'Helvetica Neue';
    cb.TickLength      = 0.02;
    cb.Label.String    = 'GCaMP (z)';
    cb.Label.FontSize  = 10;
    cb.Label.FontName  = 'Helvetica Neue';
    cb.Color           = [0.15 0.15 0.15];

    % ── Axis labels ───────────────────────────────────────────────────────
    xlabel(ax, 'Time (volumes)',          'FontSize',11,'FontName','Helvetica Neue');
    ylabel(ax, 'Voxel (clustered order)', 'FontSize',11,'FontName','Helvetica Neue');

    % ── Y ticks ───────────────────────────────────────────────────────────
    ytick_pos = round(linspace(1, nVox, 5));
    set(ax, 'YTick', ytick_pos, ...
        'YTickLabel', arrayfun(@num2str, ytick_pos, 'UniformOutput', false));

    % ── X ticks ───────────────────────────────────────────────────────────
    xtick_pos = 0:20:nT_show;
    set(ax, 'XTick', xtick_pos);

    % ── Panel label ───────────────────────────────────────────────────────
    text(ax, -0.065, 1.02, 'E', ...
        'Units','normalized', ...
        'FontSize',15,'FontWeight','bold','FontName','Helvetica Neue', ...
        'Color',[0.1 0.1 0.1],'VerticalAlignment','bottom');

    % ── Methods footnote ──────────────────────────────────────────────────
    text(ax, 0.99, -0.09, ...
        sprintf('Optimal leaf ordering  |  Ward linkage, correlation distance  |  N=%d voxels  |  %d clusters', ...
        nVox, N_CLUSTERS), ...
        'Units','normalized','FontSize',7.5,'FontName','Helvetica Neue', ...
        'Color',[0.55 0.55 0.55], ...
        'HorizontalAlignment','right','VerticalAlignment','top');

    %% ── Save ─────────────────────────────────────────────────────────────
    out_dir = fullfile(dfF_dir, 'paper_figures_pretty');
    if ~exist(out_dir,'dir'), mkdir(out_dir); end

    stem = fullfile(out_dir, sprintf('heatmap_leaf_ordered_fish%03d', dataset_idx));
    exportgraphics(fig, [stem '.png'], 'Resolution',DPI,      'BackgroundColor','w');
    exportgraphics(fig, [stem '.pdf'], 'ContentType','vector', 'BackgroundColor','w');
    fprintf('  Saved: %s.pdf + .png\n', stem);
    close(fig);

end

fprintf('\nDONE.\n');

%% ===================== HELPERS =====================
function cmap = rdbu_r(n)
    % Diverging Blue–White–Red
    % Blue = negative (suppressed), Red = positive (activated)
    % Reversed from standard RdBu so that convention matches GCaMP sign
    lo = [0.017 0.314 0.673];   % deep blue
    mid = [1.000 1.000 1.000];  % white
    hi = [0.698 0.094 0.168];   % deep red
    h  = floor(n/2);
    c1 = interp1([0 1], [lo;  mid], linspace(0,1,h),   'linear');
    c2 = interp1([0 1], [mid; hi],  linspace(0,1,n-h), 'linear');
    cmap = [c1; c2];
end