%
% Mean ± SD trace of significant voxels — full timeseries
%
% PIPELINE:
%   1. Load PAYLOAD_CLUSTER_*.mat → sig_idx
%   2. Load dff_signals.mat → extract sig voxels only
%   3. HP filter
%   4. Z-score each sig voxel across full timeseries
%   5. Plot mean ± SD across sig voxels, full session
%   6. Mark stimulus onsets as vertical lines
%
% Runs across all 3 groups. One figure per fish.
% Output: dfF/paper_figures_pretty/sig_voxel_traces/trace_sigvox_<fish>.png/.pdf

clear; clc;

%% ===================== USER PARAMETERS =====================
ROOT_BASE  = 'D:\Gokul\2026_data';

GROUP_DEFS = { ...
    'ctrl',         'Control',      [0.20 0.35 0.80]; ...
    'non_learners', 'Non-learners', [0.55 0.35 0.75]; ...
    'test',         'Learners',     [0.85 0.25 0.20];  ...

};

RLD_SUBDIR = 'rl_deconvolved';

% ── Must match XX_cluster_and_phase_shifted.m ────────────────────────────
N_SHUF        = 5000;
SCORE_AGG     = 'mean';
DO_HIGHPASS   = true;
HP_METHOD     = 'movmedian';
HP_WIN_VOL    = 30;
P_PRIM        = 0.01;
CLUSTER_ALPHA = 0.05;

% ── Display ───────────────────────────────────────────────────────────────
MAX_TIME    = Inf;     % Inf = full session

% ── Stimulus duration (for shading) ──────────────────────────────────────
STIM_DUR_VOL = 6;
STIM_COLOR   = [0.90 0.90 0.90];

% ── figure dimensions ────────────────────────────────────
FIG_W_IN = 85 / 25.4;   % 85 mm single column
FONT     = 'Helvetica';
FS_LABEL = 6;
FS_TICK  = 5;
FS_PANEL = 7;
LW_AX    = 0.5;
LW_MEAN  = 1.2;

% ── Output ────────────────────────────────────────────────────────────────
DPI      = 600;
MAKE_PDF = true;

%% ===================== DERIVED =====================
hpTag    = ternary(DO_HIGHPASS, sprintf('HP_%s_win%d',HP_METHOD,HP_WIN_VOL),'HP_OFF');
scoreTag = sprintf('SCORE_MEDIAN_%s', upper(SCORE_AGG));
PAYLOAD_SUBDIR = sprintf('CLUSTER_PHASERAND_N%d_%s_%s_PPRIM%.2f_CALPHA%.2f', ...
    N_SHUF, scoreTag, hpTag, P_PRIM, CLUSTER_ALPHA);

nGroups = size(GROUP_DEFS,1);

%% ===================== GROUP LOOP =====================
for g = 1:nGroups

    grp_folder = GROUP_DEFS{g,1};
    grp_label  = GROUP_DEFS{g,2};
    grp_color  = GROUP_DEFS{g,3};

    rld_root = fullfile(ROOT_BASE, grp_folder, RLD_SUBDIR);
    if ~exist(rld_root,'dir')
        fprintf('SKIP %s — not found\n', grp_folder); continue;
    end

    D    = dir(rld_root);
    isub = [D.isdir] & ~ismember({D.name},{'.','..'});
    fish_dirs = {D(isub).name};
    fprintf('\n════ %s (%d fish) ════\n', grp_label, numel(fish_dirs));

    for fi = 1:numel(fish_dirs)

        fish_name = fish_dirs{fi};
        dfF_dir   = fullfile(rld_root, fish_name, 'dfF');
        pay_dir   = fullfile(dfF_dir, 'paper_figures_pretty', PAYLOAD_SUBDIR);

        pf = dir(fullfile(pay_dir,'PAYLOAD_CLUSTER_*.mat'));
        if isempty(pf)
            fprintf('  SKIP %s — no payload\n', fish_name); continue;
        end
        [~,pstem] = fileparts(pf(1).name);
        fish_stem = strrep(pstem,'PAYLOAD_CLUSTER_','');
        fprintf('\n  [%d/%d] %s\n', fi, numel(fish_dirs), fish_name);

        %% ── Load payload ─────────────────────────────────────────────────
        P = load(fullfile(pay_dir, pf(1).name));
        if ~isfield(P,'sig_idx') || isempty(P.sig_idx)
            fprintf('    SKIP — no significant voxels\n'); continue;
        end
        sig_idx = P.sig_idx(:);
        onsets  = P.onsets(:);

        %% ── Load dff ─────────────────────────────────────────────────────
        D2  = load(fullfile(dfF_dir,'dff_signals.mat'));
        dff = D2.dff;
        if ndims(dff)==3
            dff = permute(dff,[2 1 3]);
            dff = reshape(dff, size(dff,1),[]);
        end
        dff  = single(dff);
        nT   = size(dff,1);
        nVox = size(dff,2);

        sig_idx = sig_idx(sig_idx>=1 & sig_idx<=nVox);
        nSig    = numel(sig_idx);
        if nSig==0, fprintf('    SKIP — OOB\n'); continue; end

        nT_show = min(nT, ternary(isinf(MAX_TIME), nT, MAX_TIME));
        dff     = dff(1:nT_show, :);

        dff_sig = dff(:, sig_idx);   % [nT_show x nSig]

        %% ── HP filter ────────────────────────────────────────────────────
        if DO_HIGHPASS
            if strcmpi(HP_METHOD,'movmedian')
                slow = movmedian(dff_sig, HP_WIN_VOL, 1,'omitnan');
            else
                slow = movmean(dff_sig,   HP_WIN_VOL, 1,'omitnan');
            end
            dff_sig = dff_sig - slow; clear slow;
        end

        %% ── Z-score each voxel ───────────────────────────────────────────
        mu  = mean(dff_sig, 1,'omitnan');
        sg  = std(dff_sig,  0, 1,'omitnan');
        sg(sg < eps) = 1;
        dff_z = (dff_sig - mu) ./ sg;   % [nT_show x nSig]

        %% ── Mean ± SD across sig voxels ──────────────────────────────────
        tr_mean = mean(dff_z, 2,'omitnan');   % [nT_show x 1]
        tr_sd   = std(dff_z,  0, 2,'omitnan');% [nT_show x 1]
        t_ax    = (1:nT_show)';

        %% ── Figure ───────────────────────────────────────────────────────
        pad_l = 0.54; pad_b = 0.44; pad_t = 0.22; pad_r = 0.12;
        ax_w  = FIG_W_IN - pad_l - pad_r;
        ax_h  = 1.20;
        fig_h = pad_b + ax_h + pad_t;

        fig = figure('Color',[1 1 1], ...
            'Units','inches','Position',[1 1 FIG_W_IN fig_h], ...
            'PaperUnits','inches','PaperSize',[FIG_W_IN fig_h], ...
            'PaperPosition',[0 0 FIG_W_IN fig_h], ...
            'InvertHardcopy','off','Renderer','painters');

        ax = axes('Parent',fig,'Units','normalized', ...
            'Position',[pad_l/FIG_W_IN, pad_b/fig_h, ax_w/FIG_W_IN, ax_h/fig_h]);
        hold(ax,'on');

        % Stimulus onset shading
        valid_on = onsets(onsets>=1 & onsets+STIM_DUR_VOL-1<=nT_show);
        yr_est   = max(abs([tr_mean+tr_sd; tr_mean-tr_sd])) * 1.35;
        if ~isfinite(yr_est)||yr_est==0, yr_est=1; end

        for oi = 1:numel(valid_on)
            x0 = valid_on(oi);
            x1 = min(x0 + STIM_DUR_VOL - 1, nT_show);
            patch(ax, [x0 x1 x1 x0], [-yr_est -yr_est yr_est yr_est], ...
                STIM_COLOR,'EdgeAlpha',0,'FaceAlpha',1,'HandleVisibility','off');
        end
        uistack(findobj(ax,'Type','patch'),'bottom');

        % Zero line
        yline(ax, 0,'Color',[0.80 0.80 0.80],'LineWidth',0.3, ...
            'HandleVisibility','off');

        % SD band
        fill(ax, [t_ax; flipud(t_ax)], ...
            [tr_mean+tr_sd; flipud(tr_mean-tr_sd)], ...
            grp_color,'FaceAlpha',0.15,'EdgeAlpha',0,'HandleVisibility','off');

        % Mean trace
        plot(ax, t_ax, tr_mean,'-','Color',grp_color,'LineWidth',LW_MEAN);

        ylim(ax, [-yr_est yr_est]);
        xlim(ax, [1 nT_show]);

        set(ax,'TickDir','out','Box','off','LineWidth',LW_AX, ...
            'FontSize',FS_TICK,'FontName',FONT, ...
            'XColor',[0 0 0],'YColor',[0 0 0], ...
            'XTick',0:20:nT_show,'TickLength',[0.012 0.012]);

        xlabel(ax,'Time (volumes)','FontSize',FS_LABEL,'FontName',FONT,'Color',[0 0 0]);
        ylabel(ax,'GCaMP (z)  —  sig. voxels','FontSize',FS_LABEL,'FontName',FONT,'Color',[0 0 0]);

        % Panel label + annotations
        text(ax,-0.14,1.07,'D','Units','normalized', ...
            'FontSize',FS_PANEL,'FontWeight','bold','FontName',FONT,'Color',[0 0 0]);
        text(ax,0.02,0.97,fish_stem,'Units','normalized', ...
            'VerticalAlignment','top','FontSize',FS_LABEL,'FontName',FONT,'Color',[0.4 0.4 0.4]);
        text(ax,0.99,0.97,sprintf('n_{vox}=%d  |  mean \\pm SD', nSig), ...
            'Units','normalized','HorizontalAlignment','right','VerticalAlignment','top', ...
            'FontSize',FS_TICK,'FontName',FONT,'Color',[0.45 0.45 0.45]);

        hold(ax,'off');

        %% ── Save ─────────────────────────────────────────────────────────
        out_dir = fullfile(dfF_dir,'paper_figures_pretty','sig_voxel_traces');
        if ~exist(out_dir,'dir'), mkdir(out_dir); end

        stem = fullfile(out_dir, sprintf('trace_sigvox_%s_%s', grp_folder, fish_stem));
        print(fig, stem, '-dpng', sprintf('-r%d',DPI));
        if MAKE_PDF
            print(fig, stem, '-dpdf', '-painters', sprintf('-r%d',DPI));
        end
        fprintf('    Saved → %s\n', out_dir);
        close(fig);
        clear dff;

    end % fish
end % group

fprintf('\nDONE.\n');

%% ===================== HELPERS =====================
function out = ternary(c,a,b)
    if c, out=a; else, out=b; end
end