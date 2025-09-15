function plot_shifts(shift_x, shift_y, savePath)
    figure;
    subplot(2,1,1);
      plot(shift_x, 'r');
      title('Median X Shift per Volume');
      ylabel('Pixels');
    subplot(2,1,2);
      plot(shift_y, 'b');
      title('Median Y Shift per Volume');
      xlabel('Volume');
      ylabel('Pixels');
    saveas(gcf, savePath);
    close(gcf);
end