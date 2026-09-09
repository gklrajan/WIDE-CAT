%% XX_01c_cluster_and_phase_shifted_spatialnull_mean.m
% Voxelwise analysis with 3D CLUSTER-BASED PERMUTATION CORRECTION.
%
% MEAN SCORING:
%   score = mean across trials of (mean_post_trial - mean_pre_trial)

%% 
%
% METHOD SUMMARY:
%   Non-parametric cluster-based permutation test (Maris & Oostenveld 2007,
%   J Neurosci Methods). Adapted for widefield calcium imaging with 3D hex
%   tile voxel structure and a spatial-covariance-preserving common-phase
%   randomisation null.
%
% PIPELINE:
%   Step 0 — Pilot run (N_PILOT surrogates):
%             Estimate marginal null score distribution.
%             Derive score_thresh = P_PRIM-th upper percentile.
%             This fixed threshold is applied IDENTICALLY to real data
%             and every surrogate — guaranteeing symmetry.
%
%   Step 1 — Observed score per voxel:
%             For each trial: score_t = mean(post lags) - mean(pre lags)
%             Final score = mean(score_t across trials)
%
%   Step 2 — Primary threshold on real data:
%             prim_pass = (scoreObs > score_thresh) & (scoreObs > 0)
%
%   Step 3 — 3D connected clusters on prim_pass voxels.
%             Cluster mass = sum of scores within cluster.
%
%   Step 4 — Common-phase randomisation null (N_SHUF iterations, parfor):
%             At each temporal frequency, the same random phase rotation is
%             applied to every voxel. This randomises timing relative to the
%             stimulus while preserving the multivoxel cross-spectrum and
%             therefore the spatial covariance/traveling-wave structure.
%             Each surrogate: same score_thresh applied identically,
%             same cluster procedure, record max cluster mass.
%
%   Step 5 — Cluster-level inference:
%             cluster_p = (1 + number of null max-masses >= observed mass)
%                         / (N_SHUF + 1).
%             Significant if cluster_p <= CLUSTER_ALPHA.

clear; clc;

%% ===================== USER PARAMETERS ====================
INPUT_ROOT = 'F:\lnm_brain_data_GR_2026_clean\L';
envInputRoot = getenv('WIDECAT_CLUSTER_INPUT_ROOT');
if ~isempty(envInputRoot), INPUT_ROOT = envInputRoot; end
RESULT_ROOT = fullfile(INPUT_ROOT, 'rl_deconvolved');


% --- Scoring ---
SCORE_AGG   = 'mean';       % within-trial post window: 'mean' or 'peak'
TRIAL_AGG   = 'mean';       % across trial-wise post-minus-pre scores; locked for this script
DO_HIGHPASS = true;
HP_METHOD   = 'movmedian';
HP_WIN_VOL  = 41;

% --- Trials ---
N_TRIALS_USE    = inf;       % Inf = all valid non-wrap trials
STIM_DUR_VOL    = 5;

% Symmetric 3-volume windows
PRE_BASE_LAGS   = -5:-1;   % 5 volumes before onset
POST_LAGS_SCORE = 0:4;     % 5 volumes from onset

% --- Pilot run ---
N_PILOT = 200;

% --- Primary threshold ---
P_PRIM      = 0.01;         % score_thresh = (1-P_PRIM)*100 th pctile of pilot null
REQUIRE_POS = true;

% --- Main null ---
N_SHUF = 5000;

% --- Cluster inference ---
CLUSTER_ALPHA = 0.05;

% --- 3D neighbour definition ---
TILE_WIDTH_UM      = 18.0;
LATERAL_THRESH_UM  = 1.5 * TILE_WIDTH_UM;
AXIAL_XY_THRESH_UM = 1.0 * TILE_WIDTH_UM;
PX_SIZE_UM         = 1.3;
Z_STEP_UM          = 10.0;

% --- Reproducibility ---
RNG_SEED = 1;

%% ===================== DERIVED TAGS =====================
SCORE_AGG = lower(char(SCORE_AGG));
assert(ismember(SCORE_AGG, {'peak','mean'}), ...
    'SCORE_AGG must be ''peak'' or ''mean''.');
TRIAL_AGG = lower(char(TRIAL_AGG));
assert(strcmp(TRIAL_AGG, 'mean'), ...
    'This is the mean variant; TRIAL_AGG must remain ''mean''.');

hpTag    = ternary(DO_HIGHPASS, sprintf('HP_%s_win%d',char(HP_METHOD),HP_WIN_VOL), 'HP_OFF');
scoreTag = sprintf('TRIAL%s_WINDOW%s', upper(char(TRIAL_AGG)), ...
    upper(char(SCORE_AGG)));

OUT_SUBFOLDER = sprintf('CLUSTER_COMMONPHASE_N%d_%s_%s_PPRIM%.2f_CALPHA%.2f', ...
    N_SHUF, scoreTag, hpTag, P_PRIM, CLUSTER_ALPHA);

%% ===================== FIND DATASETS =====================
D    = dir(RESULT_ROOT);
isub = [D.isdir] & ~ismember({D.name},{'.','..'});
subdirs = {D(isub).name};
fprintf('\nDatasets found: %d\n', numel(subdirs));
for ii = 1:numel(subdirs)
    fprintf('  %d) %s\n', ii, subdirs{ii});
end
fprintf('\nRunning BATCH...\n');

%% ===================== MAIN LOOP =====================
for dataset_idx = 1:numel(subdirs)
    rng(RNG_SEED + dataset_idx, 'twister');

    subn    = subdirs{dataset_idx};
    outDir  = fullfile(RESULT_ROOT, subn);
    dfF_dir = fullfile(outDir, 'dfF');

    req = {'dff_signals.mat','stim_slices.mat','hex_rois.mat'};
    ok  = all(cellfun(@(f) exist(fullfile(dfF_dir,f),'file')>0, req));
    if ~ok
        fprintf('SKIP %s (missing inputs)\n', subn); continue;
    end
    fprintf('\n[%d/%d] %s\n', dataset_idx, numel(subdirs), subn);

    %% ── Load ─────────────────────────────────────────────────────────────
    A   = load(fullfile(dfF_dir,'dff_signals.mat'));
    dff = A.dff;
    S   = load(fullfile(dfF_dir,'stim_slices.mat'));
    stim_periods_per_slice = S.stim_periods_per_slice;
    R        = load(fullfile(dfF_dir,'hex_rois.mat'));
    hex_rois = R.hex_rois;

    if ndims(dff)==3
        dff = permute(dff,[2,1,3]);
        dff = reshape(dff, size(dff,1), []);
    end
    dff = single(dff);
    [nT, nVox] = size(dff);
    if nVox==0||nT==0, fprintf('  Empty. SKIP.\n'); continue; end

    %% ── Stimulus onsets ──────────────────────────────────────────────────
    
    % One stimulus status value per volume
    nStimVolumes = max(stim_periods_per_slice(:,2));
    stim_status_vol = false(nStimVolumes,1);
    
    for v = 1:nStimVolumes
        stim_status_vol(v) = any( ...
            stim_periods_per_slice(stim_periods_per_slice(:,2)==v,4) > 0);
    end
    
    % Find OFF -> ON transitions = stimulus onsets
    stim_onsets_all = find( ...
        stim_status_vol & ...
        [true; ~stim_status_vol(1:end-1)]);
    
    if isempty(stim_onsets_all)
        fprintf('  No stim onsets. SKIP.\n');
        continue;
    end
    
    fprintf('  Stimulus onsets: ');
    fprintf('%d ', stim_onsets_all);
    fprintf('\n');

    %% ── ROIs and image dims ──────────────────────────────────────────────
    rois = flatten_rois(hex_rois);
    if isempty(rois), fprintf('  No ROIs. SKIP.\n'); continue; end
    [H, W] = infer_hw(dfF_dir, rois);
    if isempty(H), fprintf('  Cannot infer H,W. SKIP.\n'); continue; end

    n    = min(nVox, numel(rois));
    rois = rois(1:n); dff = dff(:,1:n); nVox = n;

    %% ── High-pass ────────────────────────────────────────────────────────
    if DO_HIGHPASS
        fprintf('  High-pass (%s, win=%d)...\n', HP_METHOD, HP_WIN_VOL);
        dff = highpass_dff(dff, HP_WIN_VOL, HP_METHOD);
    end

    %% ── Valid trials ─────────────────────────────────────────────────────
    minL = min(PRE_BASE_LAGS); maxL = max(POST_LAGS_SCORE);
    valid_on = stim_onsets_all((stim_onsets_all+minL)>=1 & ...
                               (stim_onsets_all+maxL)<=nT);
    if isempty(valid_on), fprintf('  No valid onsets. SKIP.\n'); continue; end

    if ~isinf(N_TRIALS_USE) && N_TRIALS_USE < numel(valid_on)
        onsets = valid_on(1:N_TRIALS_USE);
    else
        onsets = valid_on;
    end
    nTrials = numel(onsets);
    fprintf('  Trials: %d\n', nTrials);

    %% ── Tile layout ──────────────────────────────────────────────────────
    N_Z    = size(hex_rois, 1);
    N_ROIS = size(hex_rois{1,1}, 2);
    fprintf('  Z=%d  tiles/plane=%d  total voxels=%d\n', N_Z, N_ROIS, nVox);

    %% ── Voxel centroids ──────────────────────────────────────────────────
    fprintf('  Computing centroids...\n');
    cx_um = nan(nVox,1,'single');
    cy_um = nan(nVox,1,'single');
    cz_um = nan(nVox,1,'single');
    for v = 1:nVox
        z_plane = ceil(v/N_ROIS);
        t_idx   = mod(v-1,N_ROIS)+1;
        mask    = get_roi_mask(hex_rois, z_plane, t_idx, H, W);
        if isempty(mask), continue; end
        [rr,cc] = find(mask);
        if isempty(rr), continue; end
        cx_um(v) = mean(cc)*PX_SIZE_UM;
        cy_um(v) = mean(rr)*PX_SIZE_UM;
        cz_um(v) = (z_plane-1)*Z_STEP_UM;
    end
    valid_coords = isfinite(cx_um) & isfinite(cy_um) & isfinite(cz_um);
    fprintf('  Valid centroids: %d/%d\n', sum(valid_coords), nVox);
    if ~any(valid_coords)
        fprintf('  No voxels have valid spatial coordinates. SKIP.\n');
        continue;
    end

    %% ── 3D neighbour graph ───────────────────────────────────────────────
    fprintf('  Building 3D neighbour graph...\n');
    adj = build_neighbour_graph(cx_um, cy_um, cz_um, nVox, ...
                                LATERAL_THRESH_UM, AXIAL_XY_THRESH_UM);
    [adj_i, adj_j] = find(triu(adj,1));
    adj_i = uint32(adj_i(:));
    adj_j = uint32(adj_j(:));
    fprintf('  Edges: %d\n', numel(adj_i));

    %% ── Observed score ───────────────────────────────────────────────────
    fprintf('  Observed score (%s across trial-wise responses)...\n', ...
        char(TRIAL_AGG));
    preL       = PRE_BASE_LAGS(:)';
    postL      = POST_LAGS_SCORE(:)';
    scoreAgg_c = char(SCORE_AGG);
    trialAgg_c = char(TRIAL_AGG);

    % Build index matrices once — reused for all surrogates
    idx_base_mat = onsets(:) + preL;    % [nTrials x nPre]
    idx_post_mat = onsets(:) + postL;   % [nTrials x nPost]

    scoreObs = score_voxels_by_trials(double(dff), idx_base_mat, ...
        idx_post_mat, nTrials, nVox, scoreAgg_c, trialAgg_c);
    scoreObs(~isfinite(scoreObs)) = -inf;

    %% ── Precompute FFT once ──────────────────────────────────────────────
    dff_fft = fft(double(dff), [], 1);

    if mod(nT,2)==0
        freeBins = uint32(2 : nT/2);
    else
        freeBins = uint32(2 : (nT+1)/2);
    end
    mirrorBins = uint32(nT + 2 - freeBins);
    nFree      = numel(freeBins);

    %% ── STEP 0: Pilot run ────────────────────────────────────────────────
    fprintf('  Pilot run (%d surrogates) for score threshold...\n', N_PILOT);

    pilot_scores = zeros(N_PILOT, nVox, 'single');

    parfor iter = 1:N_PILOT
        % One phase rotation per temporal frequency, shared by every voxel.
        % This preserves the multivoxel cross-spectrum/spatial covariance.
        phase_rotation  = exp(1i * 2*pi * rand(nFree, 1));
        Fs              = dff_fft;
        Fs(freeBins,:)  = Fs(freeBins,:)  .* phase_rotation;
        Fs(mirrorBins,:)= conj(Fs(freeBins,:));
        surr = real(ifft(Fs, [], 1));
        pilot_scores(iter,:) = single(score_voxels_by_trials(surr, ...
            idx_base_mat, idx_post_mat, nTrials, nVox, scoreAgg_c, trialAgg_c));
    end

    % Match the observed analysis by deriving the threshold only from voxels
    % that have valid spatial coordinates.
    all_pilot    = pilot_scores(:, valid_coords);
    all_pilot    = all_pilot(:);
    all_pilot    = all_pilot(isfinite(all_pilot));
    score_thresh = prctile(all_pilot, (1-P_PRIM)*100);
    clear pilot_scores all_pilot;

    fprintf('  score_thresh = %.4f  (%.0fth pctile, equiv p<%.2f)\n', ...
        score_thresh, (1-P_PRIM)*100, P_PRIM);

    %% ── STEP 4: Main null loop ───────────────────────────────────────────
    fprintf('  Main null loop (%d surrogates, parfor)...\n', N_SHUF);

    scoreObs_bc  = scoreObs;
    score_thr_bc = score_thresh;
    req_pos_bc   = REQUIRE_POS;
    valid_coords_bc = valid_coords(:)';

    null_max_mass       = zeros(1, N_SHUF, 'double');
    null_cluster_counts = zeros(1, N_SHUF, 'double');
    null_GE             = zeros(1, nVox,   'uint32');

    parfor iter = 1:N_SHUF
        phase_rotation  = exp(1i * 2*pi * rand(nFree, 1));
        Fs              = dff_fft;
        Fs(freeBins,:)  = Fs(freeBins,:)  .* phase_rotation;
        Fs(mirrorBins,:)= conj(Fs(freeBins,:));
        surr = real(ifft(Fs, [], 1));

        sNull = score_voxels_by_trials(surr, idx_base_mat, idx_post_mat, ...
            nTrials, nVox, scoreAgg_c, trialAgg_c);
        sNull(~isfinite(sNull)) = -inf;

        null_GE = null_GE + uint32(sNull >= scoreObs_bc);

        prim_mask = (sNull > score_thr_bc);
        if req_pos_bc
            prim_mask = prim_mask & (sNull > 0);
        end
        prim_mask = prim_mask & valid_coords_bc;

        [mm, nc] = find_max_cluster_mass(prim_mask, sNull, ...
                                         adj_i, adj_j, uint32(nVox));
        null_max_mass(iter)       = mm;
        null_cluster_counts(iter) = nc;
    end

    p_uncorr = (1 + double(null_GE)) ./ (1 + N_SHUF);
    p_uncorr(~isfinite(scoreObs)) = 1;
    p_uncorr(~valid_coords_bc) = 1;
    p_uncorr = p_uncorr(:)';

    fprintf('  Null complete.  p-resolution=%.4g\n', 1/(1+N_SHUF));
    fprintf('  Null cluster counts: median=%.1f  95th=%.1f\n', ...
        median(null_cluster_counts), prctile(null_cluster_counts,95));

    %% ── Primary threshold on real data ───────────────────────────────────
    prim_pass = (scoreObs > score_thresh);
    if REQUIRE_POS
        prim_pass = prim_pass & (scoreObs > 0);
    end
    prim_pass = prim_pass & valid_coords';

    fprintf('  Voxels passing threshold: %d / %d\n', sum(prim_pass), nVox);

    %% ── Find clusters ────────────────────────────────────────────────────
    [cluster_labels, cluster_masses, n_clusters_obs] = ...
        find_clusters_full(prim_pass, scoreObs, adj_i, adj_j, nVox);
    fprintf('  Clusters found: %d\n', n_clusters_obs);

    %% ── Cluster-level inference ──────────────────────────────────────────
    cluster_thresh_mass = prctile(null_max_mass, (1-CLUSTER_ALPHA)*100);

    cluster_p   = nan(1, n_clusters_obs);
    cluster_sig = false(1, n_clusters_obs);
    for c = 1:n_clusters_obs
        cluster_p(c) = (1 + sum(null_max_mass >= cluster_masses(c))) / ...
            (N_SHUF + 1);
        cluster_sig(c) = cluster_p(c) <= CLUSTER_ALPHA;
    end

    n_sig = sum(cluster_sig);
    fprintf('  Significant clusters: %d / %d\n', n_sig, n_clusters_obs);

    fprintf('  %-8s  %-10s  %-8s  %-5s  %s\n', ...
        'Cluster','Mass','p','Sig?','Voxels');
    for c = 1:n_clusters_obs
        nv = sum(cluster_labels==c);
        fprintf('  %-8d  %-10.4f  %-8.4f  %-5s  %d\n', ...
            c, cluster_masses(c), cluster_p(c), ...
            ternary(cluster_sig(c),'YES','no'), nv);
    end

    sig_idx = find(ismember(cluster_labels, find(cluster_sig)));
    fprintf('  Total sig voxels: %d\n', numel(sig_idx));

    %% ── Save payload ─────────────────────────────────────────────────────
    out_dir  = fullfile(dfF_dir, 'paper_figures_pretty', OUT_SUBFOLDER);
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    safeStem = sprintf('TRIAL%s_fish%03d', upper(char(TRIAL_AGG)), dataset_idx);

    payload = struct();
    payload.scoreObs          = scoreObs;
    payload.p_uncorr          = p_uncorr;
    payload.score_thresh      = score_thresh;
    payload.cluster_labels    = cluster_labels;
    payload.cluster_masses    = cluster_masses;
    payload.cluster_p         = cluster_p;
    payload.cluster_sig       = cluster_sig;
    payload.n_clusters_obs    = n_clusters_obs;
    payload.cluster_thresh    = cluster_thresh_mass;
    payload.sig_idx           = sig_idx(:)';
    payload.null_max_mass     = null_max_mass;
    payload.null_cluster_counts = null_cluster_counts;
    payload.cx_um             = cx_um(:)';
    payload.cy_um             = cy_um(:)';
    payload.cz_um             = cz_um(:)';
    payload.onsets            = onsets;
    payload.nTrials           = nTrials;
    payload.N_SHUF            = N_SHUF;
    payload.N_PILOT           = N_PILOT;
    payload.P_PRIM            = P_PRIM;
    payload.CLUSTER_ALPHA     = CLUSTER_ALPHA;
    payload.REQUIRE_POS       = REQUIRE_POS;
    payload.SCORE_AGG         = char(SCORE_AGG);
    payload.TRIAL_SCORE_AGG   = char(TRIAL_AGG);
    payload.SCORE_METHOD      = sprintf('per_trial_%s', char(TRIAL_AGG));
    payload.DO_HIGHPASS       = DO_HIGHPASS;
    payload.HP_METHOD         = char(HP_METHOD);
    payload.HP_WIN_VOL        = HP_WIN_VOL;
    payload.PRE_BASE_LAGS     = PRE_BASE_LAGS;
    payload.POST_LAGS_SCORE   = POST_LAGS_SCORE;
    payload.STIM_DUR_VOL      = STIM_DUR_VOL;
    payload.nullType          = ...
        'common_phase_randomisation_spatial_covariance_preserved';
    payload.LATERAL_THRESH_UM = LATERAL_THRESH_UM;
    payload.AXIAL_XY_THRESH_UM= AXIAL_XY_THRESH_UM;
    payload.Z_STEP_UM         = Z_STEP_UM;
    payload.PX_SIZE_UM        = PX_SIZE_UM;
    payload.N_Z               = N_Z;
    payload.N_ROIS            = N_ROIS;

    save(fullfile(out_dir, sprintf('PAYLOAD_CLUSTER_%s.mat', safeStem)), ...
        '-struct', 'payload', '-v7.3');
    fprintf('  Saved: PAYLOAD_CLUSTER_%s.mat\n', safeStem);

end

fprintf('\n\nDONE.\n');

%% =========================================================================
%  HELPERS
%% =========================================================================

function out = ternary(cond, a, b)
    if cond, out=a; else, out=b; end
end

% ── Trial-wise scoring followed by explicit across-trial aggregation ──────
function score = score_voxels_by_trials(data, idx_base_mat, idx_post_mat, ...
                                         nTrials, nVox, windowAgg, trialAgg)
% Compute one post-minus-pre score per trial and voxel, then aggregate the
% trial-wise scores using TRIAL_AGG.
%
% For each trial t:
%   pre_t  = mean of data at pre-lag timepoints for trial t   [1 x nVox]
%   post_t = mean (or peak) of data at post-lag timepoints    [1 x nVox]
%   score_t = post_t - pre_t
%
% Final score = median or mean(score_t across trials)         [1 x nVox]

    trial_scores = zeros(nTrials, nVox);   % [nTrials x nVox]

    for t = 1:nTrials
        % Pre-baseline for this trial
        pre_idx = idx_base_mat(t,:);   % [1 x nPre]
        pre_t   = mean(data(pre_idx,:), 1);   % [1 x nVox]

        % Post response for this trial
        post_idx = idx_post_mat(t,:);   % [1 x nPost]
        if strcmp(windowAgg,'peak')
            post_t = max(data(post_idx,:), [], 1);   % [1 x nVox]
        else
            post_t = mean(data(post_idx,:), 1);       % [1 x nVox]
        end

        trial_scores(t,:) = post_t - pre_t;
    end

    if strcmp(trialAgg, 'mean')
        score = mean(trial_scores, 1, 'omitnan');
    else
        score = median(trial_scores, 1, 'omitnan');
    end
end

% ── High-pass filter ──────────────────────────────────────────────────────
function dff = highpass_dff(dff, win, method)
    if win<=1, return; end
    if strcmpi(method,'movmedian')
        slow = movmedian(dff, win, 1, 'omitnan');
    else
        slow = movmean(dff, win, 1, 'omitnan');
    end
    nanMask = isnan(dff);
    dff = dff - slow;
    dff(nanMask) = NaN;
end

% ── 3D neighbour graph ────────────────────────────────────────────────────
function adj = build_neighbour_graph(cx, cy, cz, nVox, lat_thresh, ax_xy_thresh)
    adj_i_all = [];
    adj_j_all = [];
    z_vals    = unique(cz(isfinite(cz)));
    n_planes  = numel(z_vals);

    for p1 = 1:n_planes
        mask1 = abs(cz - z_vals(p1)) < 0.1;
        idx1  = find(mask1);
        if isempty(idx1), continue; end
        xy1 = [cx(idx1), cy(idx1)];

        D = pdist2(xy1, xy1);
        D(logical(eye(size(D,1)))) = inf;
        [ia,ib] = find(D < lat_thresh);
        keep = ia < ib;
        adj_i_all = [adj_i_all; idx1(ia(keep))]; %#ok<AGROW>
        adj_j_all = [adj_j_all; idx1(ib(keep))]; %#ok<AGROW>

        if p1 < n_planes
            mask2 = abs(cz - z_vals(p1+1)) < 0.1;
            idx2  = find(mask2);
            if isempty(idx2), continue; end
            D2 = pdist2(xy1, [cx(idx2), cy(idx2)]);
            [ia2,ib2] = find(D2 < ax_xy_thresh);
            adj_i_all = [adj_i_all; idx1(ia2)]; %#ok<AGROW>
            adj_j_all = [adj_j_all; idx2(ib2)]; %#ok<AGROW>
        end
    end

    if isempty(adj_i_all)
        adj = sparse(nVox, nVox); return;
    end
    all_i = [adj_i_all; adj_j_all];
    all_j = [adj_j_all; adj_i_all];
    adj   = sparse(all_i, all_j, true(numel(all_i),1), nVox, nVox);
end

% ── Max cluster mass (parfor safe) ────────────────────────────────────────
function [max_mass, n_clust] = find_max_cluster_mass(prim_mask, scores, ...
                                                      adj_i, adj_j, nVox)
    max_mass = 0; n_clust = 0;
    sub_idx = uint32(find(prim_mask));
    if isempty(sub_idx), return; end
    nSub = numel(sub_idx);

    is_sub  = false(1, nVox); is_sub(sub_idx) = true;
    parent  = 1:nSub;
    sub_map = zeros(1, nVox, 'uint32'); sub_map(sub_idx) = 1:nSub;

    function r = uf_find(x)
        while parent(x)~=x
            parent(x)=parent(parent(x)); x=parent(x);
        end
        r=x;
    end

    for e = 1:numel(adj_i)
        vi=adj_i(e); vj=adj_j(e);
        if ~is_sub(vi)||~is_sub(vj), continue; end
        ri=uf_find(sub_map(vi)); rj=uf_find(sub_map(vj));
        if ri~=rj, parent(rj)=ri; end
    end
    for s=1:nSub, uf_find(s); end

    roots   = arrayfun(@(s)uf_find(s), 1:nSub);
    u_roots = unique(roots);
    n_clust = numel(u_roots);
    masses  = zeros(1,n_clust);
    for c=1:n_clust
        members   = sub_idx(roots==u_roots(c));
        masses(c) = sum(scores(members));
    end
    max_mass = max(masses);
    if isempty(max_mass), max_mass=0; end
end

% ── Full cluster extraction (real data only) ──────────────────────────────
function [labels, masses, n_clust] = find_clusters_full(prim_mask, scores, ...
                                                          adj_i, adj_j, nVox)
    labels  = zeros(1, nVox, 'uint32');
    masses  = []; n_clust = 0;
    sub_idx = uint32(find(prim_mask));
    if isempty(sub_idx), return; end
    nSub    = numel(sub_idx);

    is_sub  = false(1,nVox); is_sub(sub_idx)=true;
    parent  = 1:nSub;
    sub_map = zeros(1,nVox,'uint32'); sub_map(sub_idx)=1:nSub;

    function r = uf_find(x)
        while parent(x)~=x
            parent(x)=parent(parent(x)); x=parent(x);
        end
        r=x;
    end

    for e=1:numel(adj_i)
        vi=adj_i(e); vj=adj_j(e);
        if ~is_sub(vi)||~is_sub(vj), continue; end
        ri=uf_find(sub_map(vi)); rj=uf_find(sub_map(vj));
        if ri~=rj, parent(rj)=ri; end
    end
    for s=1:nSub, uf_find(s); end

    roots   = arrayfun(@(s)uf_find(s), 1:nSub);
    u_roots = unique(roots);
    n_clust = numel(u_roots);
    masses  = zeros(1,n_clust);
    for c=1:n_clust
        members   = sub_idx(roots==u_roots(c));
        masses(c) = sum(scores(members));
        labels(members) = c;
    end
end

% ── ROI mask ──────────────────────────────────────────────────────────────
function mask = get_roi_mask(hex_rois, z, t, H, W)
    mask = [];
    try
        r = hex_rois{z,1}{1,t};
        if islogical(r)
            if isequal(size(r),[H W])
                mask = r;
            else
                mask = imresize(r,[H W],'nearest')>0;
            end
        end
    catch
        mask = [];
    end
end

% ── Flatten hex_rois ──────────────────────────────────────────────────────
function rois = flatten_rois(hex_rois)
    rois={};
    if isempty(hex_rois), return; end
    if iscell(hex_rois)
        tmp={};
        for i=1:numel(hex_rois)
            x=hex_rois{i};
            if iscell(x), tmp=[tmp;x(:)]; %#ok<AGROW>
            elseif isstruct(x)||islogical(x), tmp=[tmp;{x}]; %#ok<AGROW>
            end
        end
        rois=tmp;
    elseif isstruct(hex_rois)
        rois=arrayfun(@(s){s},hex_rois(:));
    elseif islogical(hex_rois)
        rois={hex_rois};
    end
end

% ── Infer H, W ────────────────────────────────────────────────────────────
function [H,W] = infer_hw(dfF_dir, rois)
    H=[]; W=[];
    mvPath = fullfile(dfF_dir,'mean_volume.mat');
    if exist(mvPath,'file')>0
        M=load(mvPath);
        if     isfield(M,'mean_vol'),    V=M.mean_vol;
        elseif isfield(M,'mean_volume'), V=M.mean_volume;
        else,                            V=[];
        end
        if ~isempty(V), H=size(V,1); W=size(V,2); return; end
    end
    for i=1:numel(rois)
        R=rois{i};
        if islogical(R)&&~isempty(R), H=size(R,1); W=size(R,2); return; end
    end
end

