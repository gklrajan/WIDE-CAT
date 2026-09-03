%
% Single script, processes ctrl / non_learners / test in one run.
%
% ── PER FISH: 4 FIGURES ──────────────────────────────────────────────────
%
%   FIG_XY    Dorsal view — depth-coded max projection.
%             For each XY pixel: find the sig voxel with the highest score
%             across all Z. Colour that pixel by the DEPTH of that voxel.
%             Colormap: purple=0 um (dorsal) -> teal -> amber=Z_max (ventral).
%
%   FIG_XZ    Side view    — mean score heatmap [nZ x nX_tiles]
%   FIG_YZ    Coronal view — mean score heatmap [nZ x nY_tiles]
%   FIG_TRACE Discrete points +/- SEM across sig voxels, one per volume.
%
% ── PROJECTION LOGIC ─────────────────────────────────────────────────────
%
%   XY  : max projection — pixel colour = depth of highest-score voxel.
%   XZ  : bin centroids into (Z x X) cells at tile resolution (18 um).
%         Cell value = mean(scoreObs) of all sig voxels in that cell.
%   YZ  : same as XZ but averaging across X -> [nZ x nY_tiles].
%
%   XY colormap : purple->teal->amber (depth, perceptually uniform, CB-safe)
%   XZ/YZ cmap  : white->red (score, one-sided — all sig scores > 0)
%
% ── OUTPUT ───────────────────────────────────────────────────────────────
%
%   <ROOT_BASE>/WITH_TRACES_SCORES_<timestamp>/
%       ctrl/        <fish>/  FIG_XY FIG_XZ FIG_YZ FIG_TRACE (.png + .pdf)
%       non_learners/<fish>/
%       test/        <fish>/
%
% ── DEPENDENCIES ─────────────────────────────────────────────────────────
%   MATLAB Image Processing Toolbox (imgaussfilt)
%   Payload files from XX_cluster_and_phase_shifted.m

clear; clc;

%% ===================== USER PARAMETERS =====================

ROOT_BASE  = 'D:\Gokul\2026_data';

GROUP_DEFS = {
%   folder_name     display_label    RGB colour
    'ctrl',         'Control',       [0.20 0.35 0.80];
    'non_learners', 'Non-learners',  [0.55 0.35 0.75];
    'test',         'Learners',      [0.85 0.25 0.20];
};

RLD_SUBDIR = 'rl_deconvolved';

% ── Analysis parameters — MUST match XX_cluster_and_phase_shifted.m ──────
N_SHUF        = 5000;
SCORE_AGG     = 'mean';
DO_HIGHPASS   = true;
HP_METHOD     = 'movmedian';
HP_WIN_VOL    = 30;
P_PRIM        = 0.01;
CLUSTER_ALPHA = 0.05;

% ── Peri-stimulus window for traces ──────────────────────────────────────
TRACE_LAGS   = -2:7;
STIM_DUR_VOL = 6;

% ── Physical parameters ───────────────────────────────────────────────────
Z_STEP_UM     = 5.0;
PX_SIZE_UM    = 1.3;
TILE_WIDTH_UM = 18.0;

% ── XZ / YZ bin size ─────────────────────────────────────────────────────
XZ_BIN_UM = TILE_WIDTH_UM;
YZ_BIN_UM = TILE_WIDTH_UM;

% ── Score colormap clip (XZ/YZ only) ─────────────────────────────────────
SCORE_CLIP_PRCT = 90;

% ── Current Biology figure dimensions ────────────────────────────────────
FIG_W_IN = 85 / 25.4;   % 85 mm single column

% ── Typography ───────────────────────────────────────────────────────────
FONT      = 'Helvetica';
FS_PANEL  = 7;
FS_LABEL  = 6;
FS_TICK   = 5;
FS_CB     = 5;
FS_CB_LBL = 6;
LW_AX     = 0.5;
LW_SCALE  = 0.8;

% ── Visual parameters ────────────────────────────────────────────────────
BG_GAMMA    = 2.0;
ALPHA_OVL   = 0.92;
% DISP_BLUR set per-fish below: 0.8 x tile_width_px
STIM_C      = [0.92 0.92 0.92];
EMPTY_BIN_C = 0.93;

% ── Output ───────────────────────────────────────────────────────────────
DPI      = 600;
MAKE_PDF = true;
RUN_TAG  = sprintf('WITH_TRACES_SCORES_%s', datestr(now,'yyyymmdd_HHMMSS'));

%% ===================== DERIVED =====================
hpTag    = ternary(DO_HIGHPASS, ...
               sprintf('HP_%s_win%d', HP_METHOD, HP_WIN_VOL), 'HP_OFF');
scoreTag = sprintf('SCORE_MEDIAN_%s', upper(SCORE_AGG));
PAYLOAD_SUBDIR = sprintf( ...
    'CLUSTER_PHASERAND_N%d_%s_%s_PPRIM%.2f_CALPHA%.2f', ...
    N_SHUF, scoreTag, hpTag, P_PRIM, CLUSTER_ALPHA);

nGroups   = size(GROUP_DEFS, 1);
nTrL      = numel(TRACE_LAGS);
CMAP_SCORE = white_to_red(256);    % XZ/YZ score heatmaps
CMAP_DEPTH = depth_colormap(256);  % XY depth-coded projection

fprintf('Run tag        : %s\n',   RUN_TAG);
fprintf('Payload subdir : %s\n\n', PAYLOAD_SUBDIR);

%% ===================== GROUP LOOP =====================
for g = 1:nGroups

    grp_folder = GROUP_DEFS{g,1};
    grp_label  = GROUP_DEFS{g,2};
    grp_color  = GROUP_DEFS{g,3};

    rld_root = fullfile(ROOT_BASE, grp_folder, RLD_SUBDIR);
    if ~exist(rld_root,'dir')
        fprintf('SKIP group "%s" — directory not found:\n  %s\n', ...
            grp_folder, rld_root);
        continue;
    end

    grp_out = fullfile(ROOT_BASE, RUN_TAG, grp_folder);
    ensure_dir(grp_out);

    D    = dir(rld_root);
    isub = [D.isdir] & ~ismember({D.name},{'.','..'});
    fish_dirs = {D(isub).name};

    fprintf('\n==== %s  (%d fish) ====\n', grp_label, numel(fish_dirs));

    %% ── FISH LOOP ────────────────────────────────────────────────────────
    for fi = 1:numel(fish_dirs)

        fish_name = fish_dirs{fi};
        dfF_dir   = fullfile(rld_root, fish_name, 'dfF');
        pay_dir   = fullfile(dfF_dir, 'paper_figures_pretty', PAYLOAD_SUBDIR);

        pf = dir(fullfile(pay_dir, 'PAYLOAD_CLUSTER_*.mat'));
        if isempty(pf)
            fprintf('  SKIP %s — no payload in:\n    %s\n', fish_name, pay_dir);
            continue;
        end

        [~, pstem] = fileparts(pf(1).name);
        fish_stem  = strrep(pstem, 'PAYLOAD_CLUSTER_', '');
        fprintf('\n  [%d/%d] %s\n', fi, numel(fish_dirs), fish_name);

        %% ── Load + validate payload ──────────────────────────────────────
        P    = load(fullfile(pay_dir, pf(1).name));
        req  = {'sig_idx','scoreObs','onsets','cluster_labels', ...
                'cluster_sig','cx_um','cy_um','cz_um', ...
                'DO_HIGHPASS','HP_METHOD','HP_WIN_VOL', ...
                'PRE_BASE_LAGS','N_Z','N_ROIS'};
        miss = req(~isfield(P, req));
        if ~isempty(miss)
            fprintf('    SKIP — missing fields: %s\n', strjoin(miss,', '));
            continue;
        end
        if isempty(P.sig_idx)
            fprintf('    SKIP — no significant clusters\n'); continue;
        end

        %% ── Unpack ───────────────────────────────────────────────────────
        sig_idx       = P.sig_idx(:);
        onsets        = P.onsets(:);
        N_Z           = P.N_Z;
        N_ROIS        = P.N_ROIS;
        sig_clust_ids = find(P.cluster_sig);

        %% ── Load dff ─────────────────────────────────────────────────────
        D2  = load(fullfile(dfF_dir,'dff_signals.mat'));
        dff = D2.dff;
        if ndims(dff) == 3
            dff = permute(dff,[2 1 3]);
            dff = reshape(dff, size(dff,1), []);
        end
        dff  = single(dff);
        nT   = size(dff,1);
        nVox = size(dff,2);

        sig_idx = sig_idx(sig_idx >= 1 & sig_idx <= nVox);
        nSig    = numel(sig_idx);
        if nSig == 0
            fprintf('    SKIP — all sig_idx out of bounds\n'); continue;
        end

        %% ── High-pass filter ─────────────────────────────────────────────
        if P.DO_HIGHPASS
            if strcmpi(P.HP_METHOD,'movmedian')
                slow = movmedian(dff, P.HP_WIN_VOL, 1, 'omitnan');
            else
                slow = movmean(dff,   P.HP_WIN_VOL, 1, 'omitnan');
            end
            dff = dff - slow; clear slow;
        end

        %% ── Load spatial data ────────────────────────────────────────────
        R        = load(fullfile(dfF_dir,'hex_rois.mat'));
        hex_rois = R.hex_rois;

        Mv = load(fullfile(dfF_dir,'mean_volume.mat'));
        if isfield(Mv,'mean_vol')
            bg_raw = single(Mv.mean_vol);
        else
            bg_raw = single(Mv.mean_volume);
        end
        [H, W] = size(bg_raw);

        % Brain silhouette background
        brain_mask_path = fullfile(dfF_dir, 'brain_mask.mat');
        bm = [];
        if exist(brain_mask_path, 'file')
            Bm = load(brain_mask_path);
            fn = fieldnames(Bm);
            bm = Bm.(fn{1});
            if ndims(bm) == 3, bm = max(bm, [], 3); end
            bm = logical(bm);
            if ~isequal(size(bm), [H W])
                bm = imresize(bm, [H W], 'nearest') > 0;
            end
            bg = ones(H, W, 'single');
            bg(bm) = 0.78;
        else
            bg = bg_raw - min(bg_raw(:));
            bg = (bg ./ (max(bg(:)) + eps)) .^ BG_GAMMA;
        end

        % Display blur in pixels: 0.8 x tile width
        DISP_BLUR = TILE_WIDTH_UM / PX_SIZE_UM * 0.8;

        %% ── Spatial decode ───────────────────────────────────────────────
        sig_z    = max(1, min(N_Z,    ceil(double(sig_idx) / N_ROIS)));
        sig_tile = max(1, min(N_ROIS, mod(double(sig_idx)-1, N_ROIS) + 1));

        cx = double(P.cx_um(sig_idx));
        cy = double(P.cy_um(sig_idx));
        cz = double(P.cz_um(sig_idx));
        vt = isfinite(cx) & isfinite(cy) & isfinite(cz);

        % ROI pixel masks
        mc = cell(nSig, 1);
        for k = 1:nSig
            mc{k} = get_roi_mask(hex_rois, sig_z(k), sig_tile(k), H, W);
        end

        %% ── Scores ───────────────────────────────────────────────────────
        sc = double(P.scoreObs(sig_idx));
        sc(~isfinite(sc)) = 0;

        % Global clim for XZ/YZ
        s_hi = prctile(sc(isfinite(sc)), SCORE_CLIP_PRCT);
        if s_hi <= 0, s_hi = max(abs(sc(:))); end
        if s_hi == 0, s_hi = 1; end
        s_lo = 0;
        fprintf('    n_sig=%d  score_clim=[0  %.4f]\n', nSig, s_hi);

        % Per-fish output folder
        fish_out = fullfile(grp_out, fish_stem);
        ensure_dir(fish_out);

        %% ════════════════════════════════════════════════════════════════
        %  FIG A — XY  depth-coded max projection
        %
        %  For each XY pixel: find the sig voxel with the highest score
        %  across all Z planes. Paint that pixel with the DEPTH (um) of
        %  that winning voxel. Colour = depth, not score.
        %  purple = 0 um (dorsal) | teal = mid | amber = Z_max (ventral)
        %════════════════════════════════════════════════════════════════

        xy_maxsc = nan(H, W, 'double');   % best score at each pixel
        xy_depth = nan(H, W, 'double');   % depth (um) of that best voxel

        for k = 1:nSig
            msk = mc{k};
            if isempty(msk), continue; end
            z_um_k = (sig_z(k) - 1) * Z_STEP_UM;
            update = msk & (isnan(xy_maxsc) | sc(k) > xy_maxsc);
            xy_maxsc(update) = sc(k);
            xy_depth(update) = z_um_k;
        end

        % Depth range fixed to full stack — comparable across all fish
        z_max_um  = (N_Z - 1) * Z_STEP_UM;
        d_lo      = 0;
        d_hi      = z_max_um;

        % Layout
        left_in  = 0.08;
        cb_gap   = 0.04;
        cb_w_in  = 0.06;
        cb_pad   = 0.20;
        ax_w_in  = FIG_W_IN - left_in - cb_gap - cb_w_in - cb_pad;
        ax_h_in  = ax_w_in * (H / W);
        fig_h_in = 0.22 + ax_h_in + 0.18;

        fXY  = mkfig(FIG_W_IN, fig_h_in);
        axXY = axes('Parent',fXY, 'Units','normalized', ...
            'Position',[left_in/FIG_W_IN, 0.22/fig_h_in, ...
                        ax_w_in/FIG_W_IN, ax_h_in/fig_h_in]);

        imagesc(axXY, bg);
        colormap(axXY, gray(256));
        caxis(axXY, [0 1]);
        axis(axXY,'image');
        axis(axXY,'off');
        hold(axXY,'on');

        % Depth overlay
        vpx = ~isnan(xy_depth);
        if any(vpx(:))
            % Normalise depth to 0-1 for colormap indexing
            nm = min(max((xy_depth - d_lo) / (d_hi - d_lo), 0), 1);
            nm(~vpx) = 0;

            if exist('imgaussfilt','file') && DISP_BLUR > 0
                nm = imgaussfilt(nm, DISP_BLUR);
                nm = min(max(nm, 0), 1);
            end

            al = single(vpx);
            if exist('imgaussfilt','file')
                al = imgaussfilt(al, DISP_BLUR);
                al = min(max(al, 0), 1);
            end

            % Hard brain-mask clip — AFTER blur
            if ~isempty(bm) && isequal(size(bm), [H W])
                nm(~bm) = 0;
                al(~bm) = 0;
            end

            im_i = uint8(nm * 255) + 1;
            rgb  = zeros(H, W, 3, 'single');
            for ch = 1:3
                rgb(:,:,ch) = reshape(single(CMAP_DEPTH(im_i(:), ch)), H, W);
            end
            ho = image(axXY, rgb);
            set(ho, 'AlphaData', al * ALPHA_OVL);
        end

        % Scale bar: 100 um
        sb_px = round(100 / PX_SIZE_UM);
        sx0   = round(W * 0.05);
        sy0   = round(H * 0.95);
        line(axXY, [sx0 sx0+sb_px], [sy0 sy0], ...
            'Color',[0 0 0], 'LineWidth',LW_SCALE);
        text(axXY, sx0+sb_px/2, sy0-H*0.025, '100 um', ...
            'Color',[0 0 0], 'FontSize',FS_TICK, 'FontName',FONT, ...
            'HorizontalAlignment','center', 'VerticalAlignment','bottom');

        % Panel letter + fish ID
        text(axXY, -0.04, 1.05, 'A', 'Units','normalized', ...
            'FontSize',FS_PANEL, 'FontWeight','bold', 'FontName',FONT, ...
            'Color',[0 0 0]);
        text(axXY, 0.02, 0.03, fish_stem, 'Units','normalized', ...
            'FontSize',FS_LABEL, 'FontName',FONT, 'Color',[0.4 0.4 0.4], ...
            'VerticalAlignment','bottom');
        hold(axXY,'off');

        % Depth colorbar: purple=0 (dorsal) -> amber=z_max (ventral)
        mkcb_depth(fXY, FIG_W_IN, fig_h_in, ...
            left_in+ax_w_in+cb_gap, 0.22+ax_h_in*0.10, ...
            cb_w_in, ax_h_in*0.80, ...
            CMAP_DEPTH, z_max_um, FONT, FS_CB, FS_CB_LBL, LW_AX);

        savefig2(fXY, fullfile(fish_out, ...
            sprintf('FIG_XY_%s_%s', grp_folder, fish_stem)), DPI, MAKE_PDF);
        fprintf('    Saved XY\n');

        %% ════════════════════════════════════════════════════════════════
        %  FIG B+C — XZ and YZ  (2D score heatmaps at tile resolution)
        %════════════════════════════════════════════════════════════════
        z_max_plot = (N_Z-1) * Z_STEP_UM;
        z_edges    = 0 : Z_STEP_UM : z_max_plot + Z_STEP_UM;
        nZb        = numel(z_edges) - 1;
        z_ctrs     = (z_edges(1:end-1) + z_edges(2:end)) / 2;

        side_cfgs = {
           cx, W*PX_SIZE_UM, XZ_BIN_UM, 'X (um)',  'B', sprintf('FIG_XZ_%s_%s',grp_folder,fish_stem);
           cy, H*PX_SIZE_UM, YZ_BIN_UM, 'Y (um)',  'C', sprintf('FIG_YZ_%s_%s',grp_folder,fish_stem);
        };

        % Brain footprint per (Z bin x lateral bin) for outline
        nRoisPerPlane = size(hex_rois{1,1}, 2);
        xz_xedge = 0 : XZ_BIN_UM : W*PX_SIZE_UM + XZ_BIN_UM;
        yz_yedge = 0 : YZ_BIN_UM : H*PX_SIZE_UM + YZ_BIN_UM;
        nXbrn = numel(xz_xedge)-1;
        nYbrn = numel(yz_yedge)-1;
        xz_brain = false(nZb, nXbrn);
        yz_brain = false(nZb, nYbrn);

        for zp = 1:N_Z
            z_um_plane = (zp-1) * Z_STEP_UM;
            zi_brn = find(z_um_plane >= z_edges(1:end-1) & ...
                          z_um_plane <  z_edges(2:end), 1);
            if isempty(zi_brn), continue; end
            for t = 1:nRoisPerPlane
                msk_b = get_roi_mask(hex_rois, zp, t, H, W);
                if isempty(msk_b), continue; end
                [rr,cc] = find(msk_b);
                if isempty(rr), continue; end
                cx_b = mean(cc) * PX_SIZE_UM;
                cy_b = mean(rr) * PX_SIZE_UM;
                xi_b = find(cx_b >= xz_xedge(1:end-1) & cx_b < xz_xedge(2:end), 1);
                yi_b = find(cy_b >= yz_yedge(1:end-1) & cy_b < yz_yedge(2:end), 1);
                if ~isempty(xi_b), xz_brain(zi_brn, xi_b) = true; end
                if ~isempty(yi_b), yz_brain(zi_brn, yi_b) = true; end
            end
        end

        xz_x_ctrs    = (xz_xedge(1:end-1)+xz_xedge(2:end))/2;
        yz_y_ctrs    = (yz_yedge(1:end-1)+yz_yedge(2:end))/2;
        brain_outlines = {xz_brain, xz_x_ctrs; yz_brain, yz_y_ctrs};

        for sv = 1:2
            pos_um   = side_cfgs{sv,1};
            pos_max  = side_cfgs{sv,2};
            bin_um   = side_cfgs{sv,3};
            xlbl_sv  = side_cfgs{sv,4};
            pl_ltr   = side_cfgs{sv,5};
            fname_sv = side_cfgs{sv,6};

            x_edges = 0 : bin_um : pos_max + bin_um;
            nXb     = numel(x_edges) - 1;
            x_ctrs  = (x_edges(1:end-1) + x_edges(2:end)) / 2;

            sv_sum = zeros(nZb, nXb, 'double');
            sv_cnt = zeros(nZb, nXb, 'double');
            for k = 1:nSig
                if ~vt(k), continue; end
                xi = find(pos_um(k) >= x_edges(1:end-1) & ...
                          pos_um(k) <  x_edges(2:end), 1);
                zi = find(cz(k) >= z_edges(1:end-1) & ...
                          cz(k) <  z_edges(2:end), 1);
                if isempty(xi) || isempty(zi), continue; end
                sv_sum(zi,xi) = sv_sum(zi,xi) + sc(k);
                sv_cnt(zi,xi) = sv_cnt(zi,xi) + 1;
            end
            sv_mn            = sv_sum ./ max(sv_cnt, 1);
            sv_mn(sv_cnt==0) = NaN;

            % Build RGB image
            nm2   = min(max((sv_mn - s_lo) / (s_hi - s_lo), 0), 1);
            im_i2 = round(nm2 * 255) + 1;
            rgb2  = ones(nZb, nXb, 3, 'single');
            brn_mat  = brain_outlines{sv,1};
            brn_ctrs = brain_outlines{sv,2};
            for xi2 = 1:nXb
                bi = find(abs(brn_ctrs - x_ctrs(xi2)) < bin_um/2, 1);
                if isempty(bi), continue; end
                for zi2 = 1:nZb
                    if brn_mat(zi2,bi) && sv_cnt(zi2,xi2)==0
                        rgb2(zi2,xi2,:) = EMPTY_BIN_C;
                    end
                end
            end
            for ch = 1:3
                layer = rgb2(:,:,ch);
                layer(sv_cnt>0) = single(CMAP_SCORE(im_i2(sv_cnt>0), ch));
                rgb2(:,:,ch) = layer;
            end

            % Figure sizing
            z_span  = z_ctrs(end) - z_ctrs(1);
            x_span  = x_ctrs(end) - x_ctrs(1);
            asp     = z_span / max(x_span, 1);
            pad_l   = 0.44; pad_b = 0.40; pad_t = 0.16;
            cb_gap2 = 0.04; cb_w2 = 0.055; cb_pad2 = 0.20;
            ax_w_sv = FIG_W_IN - pad_l - cb_gap2 - cb_w2 - cb_pad2;
            ax_h_sv = max(ax_w_sv * asp, 0.55);
            fig_h_sv = pad_b + ax_h_sv + pad_t;

            fSV  = mkfig(FIG_W_IN, fig_h_sv);
            axSV = axes('Parent',fSV, 'Units','normalized', ...
                'Position',[pad_l/FIG_W_IN, pad_b/fig_h_sv, ...
                            ax_w_sv/FIG_W_IN, ax_h_sv/fig_h_sv]);

            image(axSV, x_ctrs, z_ctrs, rgb2);
            hold(axSV,'on');

            % Brain outline: top and bottom boundary per lateral bin
            brn_x_ctrs = brn_ctrs;
            top_z = nan(1, numel(brn_x_ctrs));
            bot_z = nan(1, numel(brn_x_ctrs));
            for bi = 1:numel(brn_x_ctrs)
                rows = find(brn_mat(:,bi));
                if isempty(rows), continue; end
                top_z(bi) = z_ctrs(rows(1));
                bot_z(bi) = z_ctrs(rows(end));
            end
            has_brn = ~isnan(top_z);
            if any(has_brn)
                plot(axSV, brn_x_ctrs(has_brn), top_z(has_brn), ...
                    '-', 'Color',[0.40 0.40 0.40], 'LineWidth',0.7);
                plot(axSV, brn_x_ctrs(has_brn), bot_z(has_brn), ...
                    '-', 'Color',[0.40 0.40 0.40], 'LineWidth',0.7);
            end
            hold(axSV,'off');

            set(axSV, ...
                'YDir',       'reverse', ...
                'TickDir',    'out', ...
                'Box',        'off', ...
                'LineWidth',  LW_AX, ...
                'FontSize',   FS_TICK, ...
                'FontName',   FONT, ...
                'XColor',     [0 0 0], ...
                'YColor',     [0 0 0], ...
                'TickLength', [0.015 0.015], ...
                'XTick',      nice_ticks(x_ctrs(1), x_ctrs(end), 4), ...
                'YTick',      nice_ticks(z_ctrs(1), z_ctrs(end), 5));
            axis(axSV,'tight');

            xlabel(axSV, xlbl_sv, ...
                'FontSize',FS_LABEL, 'FontName',FONT, 'Color',[0 0 0]);
            ylabel(axSV, 'Depth (um)', ...
                'FontSize',FS_LABEL, 'FontName',FONT, 'Color',[0 0 0]);
            text(axSV, 0.03, 0.97, fish_stem, 'Units','normalized', ...
                'VerticalAlignment','top', 'FontSize',FS_LABEL, ...
                'FontName',FONT, 'Color',[0.3 0.3 0.3]);
            text(axSV, -0.18, 1.06, pl_ltr, 'Units','normalized', ...
                'FontSize',FS_PANEL, 'FontWeight','bold', ...
                'FontName',FONT, 'Color',[0 0 0]);

            mkcb(fSV, FIG_W_IN, fig_h_sv, ...
                pad_l+ax_w_sv+cb_gap2, pad_b+ax_h_sv*0.10, ...
                cb_w2, ax_h_sv*0.80, ...
                CMAP_SCORE, s_lo, s_hi, 'Score', ...
                FONT, FS_CB, FS_CB_LBL, LW_AX);

            savefig2(fSV, fullfile(fish_out, fname_sv), DPI, MAKE_PDF);
            fprintf('    Saved %s\n', pl_ltr);
        end

        %% ════════════════════════════════════════════════════════════════
        %  FIG D — TRACE  (discrete points +/- SEM across sig voxels)
        %════════════════════════════════════════════════════════════════
        pre_l = P.PRE_BASE_LAGS(:)';
        ib    = max(1, min(nT, onsets(:) + pre_l));
        base  = mean(dff(ib(:), sig_idx), 1, 'omitnan');

        lag_mat = nan(nTrL, nSig, 'single');
        for li = 1:nTrL
            il = max(1, min(nT, onsets(:) + TRACE_LAGS(li)));
            v  = mean(dff(il(:), sig_idx), 1, 'omitnan');
            lag_mat(li,:) = v - base;
        end

        tr_mn  = mean(lag_mat, 2, 'omitnan');
        tr_sem = std(lag_mat,  0, 2, 'omitnan') / sqrt(nSig);
        t_ax   = TRACE_LAGS(:);

        yr = max(abs([tr_mn + tr_sem; tr_mn - tr_sem])) * 1.40;
        if ~isfinite(yr) || yr == 0, yr = 0.05; end

        pad_l_tr = 0.54; pad_b_tr = 0.44;
        pad_t_tr = 0.22; pad_r_tr = 0.12;
        ax_w_tr  = FIG_W_IN - pad_l_tr - pad_r_tr;
        ax_h_tr  = 1.15;
        fig_h_tr = pad_b_tr + ax_h_tr + pad_t_tr;

        fTR  = mkfig(FIG_W_IN, fig_h_tr);
        axT  = axes('Parent',fTR, 'Units','normalized', ...
            'Position',[pad_l_tr/FIG_W_IN, pad_b_tr/fig_h_tr, ...
                        ax_w_tr/FIG_W_IN,  ax_h_tr/fig_h_tr]);
        hold(axT,'on');

        % Stimulus window behind data
        patch(axT, ...
            [0, STIM_DUR_VOL-1, STIM_DUR_VOL-1, 0], ...
            [-yr, -yr, yr, yr], ...
            STIM_C, 'EdgeAlpha',0, 'FaceAlpha',1, 'HandleVisibility','off');
        uistack(findobj(axT,'Type','patch'), 'bottom');

        yline(axT, 0, 'Color',[0.80 0.80 0.80], 'LineWidth',0.3, ...
            'HandleVisibility','off');
        xline(axT, 0, 'Color',[0.45 0.45 0.45], 'LineWidth',0.5, ...
            'HandleVisibility','off');

        cap_w = 0.10;
        for li = 1:nTrL
            x0  = t_ax(li);
            ylo = tr_mn(li) - tr_sem(li);
            yhi = tr_mn(li) + tr_sem(li);
            line(axT,[x0 x0],[ylo yhi], ...
                'Color',grp_color,'LineWidth',0.7,'HandleVisibility','off');
            line(axT,[x0-cap_w x0+cap_w],[ylo ylo], ...
                'Color',grp_color,'LineWidth',0.7,'HandleVisibility','off');
            line(axT,[x0-cap_w x0+cap_w],[yhi yhi], ...
                'Color',grp_color,'LineWidth',0.7,'HandleVisibility','off');
        end
        plot(axT, t_ax, tr_mn, 'o', ...
            'Color',           grp_color, ...
            'MarkerFaceColor', grp_color, ...
            'MarkerEdgeColor', grp_color, ...
            'MarkerSize',      3.5, ...
            'LineStyle',       'none');

        xlim(axT, [min(TRACE_LAGS)-0.3, max(TRACE_LAGS)+0.3]);
        ylim(axT, [-yr yr]);

        y_tick_step = round(yr * 0.7, 2, 'significant');
        set(axT, ...
            'TickDir',   'out', ...
            'Box',       'off', ...
            'LineWidth', LW_AX, ...
            'FontSize',  FS_TICK, ...
            'FontName',  FONT, ...
            'XColor',    [0 0 0], ...
            'YColor',    [0 0 0], ...
            'XTick',     min(TRACE_LAGS):max(TRACE_LAGS), ...
            'YTick',     [-y_tick_step 0 y_tick_step], ...
            'TickLength',[0.012 0.012]);

        xlabel(axT, 'Lag from stim onset (volumes)', ...
            'FontSize',FS_LABEL, 'FontName',FONT, 'Color',[0 0 0]);
        ylabel(axT, '\Delta(\DeltaF/F)  (sig. voxels)', ...
            'FontSize',FS_LABEL, 'FontName',FONT, 'Color',[0 0 0]);

        text(axT, -0.14, 1.07, 'D', 'Units','normalized', ...
            'FontSize',FS_PANEL, 'FontWeight','bold', ...
            'FontName',FONT, 'Color',[0 0 0]);
        text(axT, 0.02, 0.97, fish_stem, 'Units','normalized', ...
            'VerticalAlignment','top', 'FontSize',FS_LABEL, ...
            'FontName',FONT, 'Color',[0.3 0.3 0.3]);
        text(axT, 0.99, 0.97, sprintf('n_{vox} = %d', nSig), ...
            'Units','normalized', ...
            'HorizontalAlignment','right', 'VerticalAlignment','top', ...
            'FontSize',FS_TICK, 'FontName',FONT, 'Color',[0.45 0.45 0.45]);

        hold(axT,'off');

        savefig2(fTR, fullfile(fish_out, ...
            sprintf('FIG_TRACE_%s_%s', grp_folder, fish_stem)), DPI, MAKE_PDF);
        fprintf('    Saved trace\n');
        fprintf('    -> %s\n', fish_out);

        clear dff;

    end % fish loop
end % group loop

fprintf('\n\nDONE.\nAll outputs saved under:\n  %s\n', ...
    fullfile(ROOT_BASE, RUN_TAG));

%% =========================================================================
%  LOCAL FUNCTIONS — all function definitions must appear after all
%  script statements. Do not insert any non-function code below this line.
%% =========================================================================

function f = mkfig(w, h)
    f = figure( ...
        'Color',          [1 1 1], ...
        'Units',          'inches', ...
        'Position',       [1 1 w h], ...
        'PaperUnits',     'inches', ...
        'PaperSize',      [w h], ...
        'PaperPosition',  [0 0 w h], ...
        'InvertHardcopy', 'off', ...
        'Renderer',       'painters');
end

function savefig2(f, stem, dpi, pdf)
    print(f, stem, '-dpng', sprintf('-r%d', dpi));
    if pdf
        print(f, stem, '-dpdf', '-painters', sprintf('-r%d', dpi));
    end
    close(f);
end

function mkcb(f, fw, fh, cx, cy, cw, ch, cmap, vlo, vhi, lbl, ...
              font, fs_tick, fs_lbl, lw)
    ax = axes('Parent',f, 'Units','normalized', ...
        'Position',[cx/fw, cy/fh, cw/fw, ch/fh]);
    imagesc(ax, linspace(vlo, vhi, 256)');
    colormap(ax, cmap);
    set(ax, ...
        'XTick',         [], ...
        'YDir',          'normal', ...
        'YAxisLocation', 'right', ...
        'FontSize',      fs_tick, ...
        'FontName',      font, ...
        'TickDir',       'out', ...
        'TickLength',    [0.06 0.06], ...
        'LineWidth',     lw, ...
        'YTick',         linspace(1, 256, 5), ...
        'Box',           'off', ...
        'XColor',        'none', ...
        'YColor',        [0 0 0]);
    yticklabels(ax, arrayfun(@(v) sprintf('%.2g', v), ...
        linspace(vlo, vhi, 5), 'UniformOutput', false));
    yl = ylabel(ax, lbl, 'FontSize',fs_lbl, 'FontName',font, 'Color',[0 0 0]);
    yl.Units = 'normalized';
    yl.Position(1) = max(yl.Position(1), 2.5);
end

function mkcb_depth(f, fw, fh, cx, cy, cw, ch, cmap, z_max_um, ...
                    font, fs_tick, fs_lbl, lw)
%MKCB_DEPTH  Colorbar for depth-coded XY projection.
%  Row 1 of colormap (purple) displayed at top = dorsal (Z=0).
%  Row end (amber) at bottom = ventral (Z=z_max_um).
    n  = size(cmap, 1);
    ax = axes('Parent',f, 'Units','normalized', ...
        'Position',[cx/fw, cy/fh, cw/fw, ch/fh]);
    % imagesc with YDir=reverse: row 1 at top, row n at bottom
    imagesc(ax, (1:n)');
    colormap(ax, cmap);
    set(ax, ...
        'XTick',         [], ...
        'YDir',          'reverse', ...
        'YAxisLocation', 'right', ...
        'FontSize',      fs_tick, ...
        'FontName',      font, ...
        'TickDir',       'out', ...
        'TickLength',    [0.06 0.06], ...
        'LineWidth',     lw, ...
        'Box',           'off', ...
        'XColor',        'none', ...
        'YColor',        [0 0 0], ...
        'YTick',         [1, n/2, n], ...
        'YLim',          [1 n]);
    yticklabels(ax, {'0', sprintf('%d', round(z_max_um/2)), ...
                     sprintf('%d um', round(z_max_um))});
    ylabel(ax, 'Depth', 'FontSize',fs_lbl, 'FontName',font, 'Color',[0 0 0]);
    % Dorsal / ventral annotations
    text(ax, 2.0, 0.02, 'dorsal', 'Units','normalized', ...
        'FontSize',fs_tick-0.5, 'FontName',font, 'Color',[0.45 0.45 0.45], ...
        'HorizontalAlignment','left', 'VerticalAlignment','top');
    text(ax, 2.0, 0.98, 'ventral', 'Units','normalized', ...
        'FontSize',fs_tick-0.5, 'FontName',font, 'Color',[0.45 0.45 0.45], ...
        'HorizontalAlignment','left', 'VerticalAlignment','bottom');
end

function ticks = nice_ticks(lo, hi, n)
    raw = (hi - lo) / max(n-1, 1);
    mag = 10^floor(log10(max(raw, eps)));
    stp = ceil(raw / mag) * mag;
    ticks = ceil(lo/stp)*stp : stp : floor(hi/stp)*stp;
    if isempty(ticks)
        ticks = linspace(lo, hi, n);
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function ensure_dir(p)
    if ~exist(p,'dir'), mkdir(p); end
end

function mask = get_roi_mask(hex_rois, z, t, H, W)
    mask = [];
    try
        r = hex_rois{z,1}{1,t};
        if islogical(r) && isequal(size(r), [H W])
            mask = r;
        elseif islogical(r)
            mask = imresize(r, [H W], 'nearest') > 0;
        end
    catch
    end
end

function cmap = depth_colormap(n)
%DEPTH_COLORMAP  purple->teal->amber, perceptually uniform, CB-safe.
%  purple [0.48 0.18 0.55] = Z=0      = dorsal
%  teal   [0.13 0.63 0.66] = Z=mid
%  amber  [0.96 0.65 0.14] = Z=max    = ventral
    nodes = [0.48 0.18 0.55;
             0.13 0.63 0.66;
             0.96 0.65 0.14];
    t_in  = linspace(0, 1, size(nodes,1));
    t_out = linspace(0, 1, n)';
    cmap  = interp1(t_in, nodes, t_out, 'linear');
end

function cmap = white_to_red(n)
%WHITE_TO_RED  white->deep red, one-sided (all sig scores > 0).
    lo   = [1.000 1.000 1.000];
    hi   = [0.698 0.094 0.168];
    cmap = interp1([0 1], [lo; hi], linspace(0,1,n)', 'linear');
end