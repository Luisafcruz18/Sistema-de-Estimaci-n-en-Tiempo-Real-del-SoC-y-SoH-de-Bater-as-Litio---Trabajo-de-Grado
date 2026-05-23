clear; clc; close all;

%% ========================================================================
%                Voc vs SoC USING MULTIPLE FILES
%% ========================================================================

% FILE LIST
files = {

'DESCARGA_MANUAL_SAVE_204925_2026-05-08_0915_recorte_23014s_38965s.mat'
'DESCARGA_MANUAL_SAVE_124123_2026-05-05_0919_recorte_1400s_11400s.mat'

};

%% ========================================================================
% BATTERY PARAMETERS
%% ========================================================================

Cn  = 5.2;
eta = 1;

INITIAL_SOC = [0.90 0.82];

%% ========================================================================
% GLOBAL VARIABLES
%% ========================================================================

Voc_total = [];
SoC_total = [];

markers = {'o','^','s','*','d','x','+','v'};

%% ========================================================================
% GLOBAL FIGURE
%% ========================================================================

figure
hold on

%% ========================================================================
% LOOP THROUGH FILES
%% ========================================================================

for f = 1:length(files)

    fprintf('\n=================================================\n');
    fprintf('Processing file %d of %d\n', f, length(files));
    fprintf('%s\n', files{f});
    fprintf('=================================================\n');

    %% ================== LOAD FILE ==================

    load(files{f})

    data = logSesion;

    %% ================== VARIABLES ==================

    t_raw = data(:,1);

    % Convert datenum -> seconds
    t = (t_raw - t_raw(1))*24*3600;

    V = data(:,2);
    I = data(:,3);

    %% ================== TIME ==================

    Ts = mean(diff(t));

    fprintf('Ts = %.6f s\n', Ts);

    Ts_h = Ts/3600;

    %% ================== OFFSET ==================

    I = I + 0.3;

    %% ================== CALCULATE SOC ==================

    SoC = zeros(length(I),1);

    SoC(1) = INITIAL_SOC(f);

    for k = 2:length(I)

        SoC(k) = SoC(k-1) ...
               - (eta*Ts_h/Cn)*I(k-1);

    end

    SoC = max(0,min(1,SoC));

    fprintf('Minimum SoC = %.4f\n', min(SoC));
    fprintf('Maximum SoC = %.4f\n', max(SoC));

    %% ================== EXTRACT VOC ==================

    threshold = 0.05;

    Voc_real = [];
    SoC_real = [];

    for k = 2:length(I)-1

        if abs(I(k)) < threshold && abs(I(k-1)) > threshold

            Voc_real = [Voc_real; V(k)];
            SoC_real = [SoC_real; SoC(k)];

        end
    end

    fprintf('Voc points found: %d\n', length(Voc_real));

    %% ================== SAVE GLOBAL DATA ==================

    Voc_total = [Voc_total; Voc_real];
    SoC_total = [SoC_total; SoC_real];

    %% ================== PLOT ==================

    scatter(SoC_real,...
            Voc_real,...
            70,...
            markers{f},...
            'filled')

end

%% ========================================================================
% VALIDATE DATA
%% ========================================================================

fprintf('\n=================================================\n');
fprintf('TOTAL Voc POINTS: %d\n', length(Voc_total));
fprintf('=================================================\n');

if length(SoC_total) < 5
    error('Too few points for fitting');
end

%% ========================================================================
% CONFIGURE FIGURE
%% ========================================================================

xlabel('SoC')
ylabel('Voc [V]')

title('Global Voc vs SoC Curve')

ylim([8 14])

grid on

%% ========================================================================
% TEST DIFFERENT POLYNOMIAL DEGREES
%% ========================================================================

degrees = [1 2 3 4 5];

RMSE_all = zeros(length(degrees),1);

colors = lines(length(degrees));

fprintf('\n================ GLOBAL RESULTS ================\n')

for n = 1:length(degrees)

    degree = degrees(n);

    if degree >= length(SoC_total)
        continue
    end

    %% ================== FIT ==================

    p_global = polyfit(SoC_total,...
                       Voc_total,...
                       degree);

    SoC_fit = linspace(min(SoC_total),...
                       max(SoC_total),500);

    Voc_fit = polyval(p_global,SoC_fit);

    %% ================== PREDICTION ==================

    Voc_pred = polyval(p_global,SoC_total);

    %% ================== ERROR ==================

    RMSE = sqrt(mean((Voc_total - Voc_pred).^2));

    RMSE_all(n) = RMSE;

    %% ================== PLOT ==================

    plot(SoC_fit,...
         Voc_fit,...
         'LineWidth',3,...
         'Color',colors(n,:))

    %% ================== DISPLAY ==================

    fprintf('\nDegree %d\n', degree);

    fprintf('RMSE = %.6f V (%.2f mV)\n',...
            RMSE,...
            RMSE*1000);

    fprintf('Coefficients:\n')

    disp(p_global)

end

%% ========================================================================
% LEGEND
%% ========================================================================

legend_entries = { ...
    'Dataset 1', ...
    'Dataset 2', ...
    'Degree 1', ...
    'Degree 2', ...
    'Degree 3', ...
    'Degree 4', ...
    'Degree 5'};

legend(legend_entries,'Location','best')

%% ========================================================================
% BEST FIT
%% ========================================================================

[RMSE_min,idx_best] = min(RMSE_all);

best_degree = degrees(idx_best);

fprintf('\n=================================================\n');
fprintf('BEST GLOBAL FIT\n');
fprintf('=================================================\n');

fprintf('Optimal degree = %d\n', best_degree);

fprintf('Minimum RMSE = %.6f V (%.2f mV)\n',...
        RMSE_min,...
        RMSE_min*1000);

%% ========================================================================
% FINAL EQUATION
%% ========================================================================

p_best = polyfit(SoC_total,...
                 Voc_total,...
                 best_degree);

fprintf('\n=================================================\n');
fprintf('FINAL EQUATION\n');
fprintf('=================================================\n\n');

fprintf('Voc(SoC) = ')

for k = 1:length(p_best)

    power = best_degree-(k-1);

    coef = p_best(k);

    if power > 1

        fprintf('%.8f*SoC^%d + ',coef,power);

    elseif power == 1

        fprintf('%.8f*SoC + ',coef);

    else

        fprintf('%.8f',coef);

    end
end

fprintf('\n')

%% ========================================================================
% RMSE COMPARISON
%% ========================================================================

figure

bar(degrees,RMSE_all*1000)

xlabel('Polynomial Degree')
ylabel('RMSE [mV]')

title('Global RMSE Comparison')

grid on

%% ========================================================================
% SAVE RESULTS
%% ========================================================================
%
% save('Voc_SoC_Global.mat', ...
%      'p_best', ...
%      'Voc_total', ...
%      'SoC_total', ...
%      'RMSE_all', ...
%      'best_degree');
%
% fprintf('\n✔ Voc_SoC_Global.mat file saved successfully\n');