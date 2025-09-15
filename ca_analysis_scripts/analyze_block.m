function [corr_sust, corr_onset, b_sust, b_onset, R2] = analyze_block(dff_block, sust_reg, onset_reg)
    n = size(dff_block,1);
    nR = size(dff_block,2);
    corr_sust = zeros(nR,1);
    corr_onset = zeros(nR,1);
    b_sust = zeros(nR,1);
    b_onset = zeros(nR,1);
    R2 = zeros(nR,1);

    for r = 1:nR
        y = dff_block(:,r);
        X = [sust_reg, onset_reg, ones(n,1)];
        b = X \ y;
        y_hat = X*b;

        b_sust(r) = b(1);
        b_onset(r) = b(2);
        corr_sust(r) = corr(y, sust_reg, 'rows','complete');
        corr_onset(r) = corr(y, onset_reg, 'rows','complete');

        SStot = sum( (y - mean(y)).^2 );
        SSres = sum( (y - y_hat).^2 );
        R2(r) = 1 - SSres/SStot;
    end
end