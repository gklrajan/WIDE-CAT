function plot_motion_metrics(pre_corr, post_corr, savePath)
    figure;
    plot(pre_corr(:), 'r'); hold on;
    plot(post_corr(:), 'g');
    legend('Pre-Correction', 'Post-Correction');
    title('Motion Correction Quality');
    xlabel('Frame');
    ylabel('Correlation with Mean Frame');
    saveas(gcf, savePath);
    close(gcf);
end