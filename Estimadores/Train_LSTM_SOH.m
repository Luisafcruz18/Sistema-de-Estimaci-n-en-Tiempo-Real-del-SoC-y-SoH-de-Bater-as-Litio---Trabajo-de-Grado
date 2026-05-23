% =========================================================================
%     ENTRENAMIENTO LSTM SoH - V7 FINAL
% =========================================================================
clear; clc; close all;

if ~license('test','Neural_Network_Toolbox') && ...
   ~license('test','Deep_Learning_Toolbox')
    error('Se requiere Deep Learning Toolbox.');
end

fprintf('Cargando features...\n');
load('LSTM_Features_Dataset.mat');

%% ELIMINAR CICLOS TRANSITORIOS
n_skip        = 50;
features_norm = features_norm(n_skip+1 : end, :);
labels_SoH    = labels_SoH(n_skip+1 : end);
cycle_idx     = cycle_idx(n_skip+1 : end);
n_cycles      = size(features_norm, 1);

fprintf('Ciclos disponibles : %d\n', n_cycles);
fprintf('Rango SoH          : [%.4f, %.4f]\n', min(labels_SoH), max(labels_SoH));

%% DETECTAR KNEE-POINT
SoH_knee_umbral = 0.94;
idx_knee = find(labels_SoH <= SoH_knee_umbral, 1, 'first');
if isempty(idx_knee)
    idx_knee = floor(n_cycles * 0.55);
    fprintf('Knee-point no detectado, usando estimado: %d\n', idx_knee);
else
    fprintf('Knee-point en ciclo local %d (real: %d)\n', ...
            idx_knee, cycle_idx(idx_knee));
end

idx_EOL       = n_cycles;
n_LAM         = idx_EOL - idx_knee;
idx_train_min = idx_knee + floor(n_LAM * 0.60);
train_pct_ef  = idx_train_min / n_cycles;

%% PARÁMETROS
W         = 10;
train_pct = max(train_pct_ef, 0.82);
val_pct   = 0.10;

%% CREAR SECUENCIAS
fprintf('\nCreando secuencias (W=%d)...\n', W);
n_seq = n_cycles - W;
X_all = cell(n_seq, 1);
Y_all = zeros(n_seq, 1);

for i = 1:n_seq
    X_all{i} = features_norm(i : i+W-1, :)';
    Y_all(i)  = labels_SoH(i + W);
end

%% NORMALIZACIÓN DE ETIQUETA
Y_mean     = mean(Y_all);
Y_std      = std(Y_all);
Y_all_norm = (Y_all - Y_mean) / Y_std;
fprintf('Normalización SoH: media=%.4f  std=%.4f\n', Y_mean, Y_std);

%% DIVISIÓN
n_train = floor(n_seq * train_pct);
n_val   = floor(n_seq * val_pct);
n_test  = n_seq - n_train - n_val;

if n_val < 50 || n_test < 50
    error('Val o Test < 50 muestras. Reducir train_pct.');
end

X_train = X_all(1 : n_train);
Y_train = Y_all_norm(1 : n_train);
X_val   = X_all(n_train+1 : n_train+n_val);
Y_val   = Y_all_norm(n_train+1 : n_train+n_val);
X_test  = X_all(n_train+n_val+1 : end);
Y_test  = Y_all_norm(n_train+n_val+1 : end);

Y_test_real = Y_test * Y_std + Y_mean;
Y_all_real  = Y_all;

% ← DEFINIR cycles_pred_all AQUÍ (era el bug principal)
cycles_pred_all = cycle_idx(W+1 : end);

fprintf('\nDivisión:\n');
fprintf('  Train : %d | Val : %d | Test : %d\n', n_train, n_val, n_test);
fprintf('  Iteraciones/época : %d\n', ceil(n_train/32));

%% FIGURA TIEMPO REAL
fig_rt = figure('Color','w','Name','Entrenamiento LSTM V7', ...
                'Position',[50 50 1000 420]);
ax1 = subplot(1,2,1);
h_tr  = plot(ax1, NaN, NaN, 'b-',  'LineWidth',1.5,'DisplayName','Train RMSE');
hold(ax1,'on');
h_val = plot(ax1, NaN, NaN, 'r--', 'LineWidth',1.5,'DisplayName','Val RMSE');
xlabel(ax1,'Época'); ylabel(ax1,'RMSE (norm.)');
title(ax1,'Convergencia'); legend(ax1,'show','Location','northeast');
grid(ax1,'on'); ax1.YScale = 'log';
xlim(ax1,[0 10]); ylim(ax1,[1e-5 1]);

ax2 = subplot(1,2,2);
h_lr = plot(ax2, NaN, NaN, 'Color',[0.1 0.6 0.2],'LineWidth',1.5);
xlabel(ax2,'Época'); ylabel(ax2,'Learning Rate');
title(ax2,'Tasa de aprendizaje');
grid(ax2,'on'); ax2.YScale = 'log';
xlim(ax2,[0 10]);
drawnow;

outputFcn = @(info) liveTrainPlot(info, ax1, ax2, h_tr, h_val, h_lr);

%% ARQUITECTURA
layers = [
    sequenceInputLayer(n_features,  'Name','input')
    lstmLayer(128, 'OutputMode','sequence', 'Name','lstm1')
    dropoutLayer(0.1, 'Name','drop1')
    lstmLayer(64,  'OutputMode','last',     'Name','lstm2')
    dropoutLayer(0.1, 'Name','drop2')
    fullyConnectedLayer(32, 'Name','fc1')
    reluLayer('Name','relu1')
    fullyConnectedLayer(16, 'Name','fc2')
    reluLayer('Name','relu2')
    fullyConnectedLayer(1,  'Name','fc_out')
    regressionLayer('Name','output')
];

%% OPCIONES
opts = trainingOptions('adam', ...
    'MaxEpochs',              500, ...
    'MiniBatchSize',          32, ...
    'InitialLearnRate',       3e-4, ...
    'LearnRateSchedule',      'piecewise', ...
    'LearnRateDropFactor',    0.5, ...
    'LearnRateDropPeriod',    80, ...
    'GradientThreshold',      1, ...
    'ValidationData',         {X_val, Y_val}, ...
    'ValidationFrequency',    10, ...
    'ValidationPatience',     60, ...
    'Shuffle',                'never', ...
    'Plots',                  'none', ...
    'Verbose',                true, ...
    'VerboseFrequency',       10, ...
    'OutputFcn',              outputFcn);

%% ENTRENAMIENTO
fprintf('\n>>> Iniciando entrenamiento V7 FINAL...\n\n');
tic;
net = trainNetwork(X_train, Y_train, layers, opts);
t_train = toc;
fprintf('\n>>> Completado en %.1f s (%.1f min)\n', t_train, t_train/60);

%% EVALUACIÓN
Y_pred_test_norm = predict(net, X_test, 'MiniBatchSize', 32);
Y_pred_all_norm  = predict(net, X_all,  'MiniBatchSize', 32);

Y_pred_test = Y_pred_test_norm * Y_std + Y_mean;
Y_pred_all  = Y_pred_all_norm  * Y_std + Y_mean;

RMSE_test = sqrt(mean((Y_pred_test - Y_test_real).^2));
MAE_test  = mean(abs(Y_pred_test   - Y_test_real));
MaxE_test = max(abs(Y_pred_test    - Y_test_real));
RMSE_all  = sqrt(mean((Y_pred_all  - Y_all_real).^2));

fprintf('\n=================================================\n');
fprintf('RESULTADOS FINALES — V7\n');
fprintf('=================================================\n');
fprintf('Train/Val/Test : %d / %d / %d\n', n_train, n_val, n_test);
fprintf('RMSE  test     : %.6f  (%.4f%%)\n', RMSE_test, RMSE_test*100);
fprintf('MAE   test     : %.6f  (%.4f%%)\n', MAE_test,  MAE_test*100);
fprintf('MaxE  test     : %.6f  (%.4f%%)\n', MaxE_test, MaxE_test*100);
fprintf('RMSE  global   : %.6f  (%.4f%%)\n', RMSE_all,  RMSE_all*100);

%% FIGURA 1 — SoH Real vs Predicho
figure('Color','w','Name','SoH Real vs Predicho');
plot(cycles_pred_all, Y_all_real*100,  'b-',  'LineWidth',1.5,'DisplayName','SoH Real');
hold on
plot(cycles_pred_all, Y_pred_all*100,  'r--', 'LineWidth',1.5,'DisplayName','SoH LSTM');
xline(cycle_idx(n_train+n_val+W+1), 'k--', 'Inicio Test', ...
      'LabelVerticalAlignment','bottom','LineWidth',1.2)
xline(cycle_idx(min(idx_knee+W, n_cycles)), 'm:', ...
      sprintf('Knee (ciclo %d)', cycle_idx(min(idx_knee,n_cycles))), ...
      'LineWidth',1,'LabelVerticalAlignment','bottom')
yline(80,'g--','EOL (80%)','LineWidth',1.2)
xlabel('Ciclo'); ylabel('SoH [%]')
title(sprintf('SoH Real vs LSTM  |  RMSE_{test} = %.4f%%', RMSE_test*100))
legend('Location','southwest'); grid on

%% FIGURA 2 — Error absoluto
figure('Color','w','Name','Error absoluto');
error_abs = abs(Y_pred_all - Y_all_real)*100;
plot(cycles_pred_all, error_abs, 'Color',[0.8 0.2 0.2],'LineWidth',1);
hold on
yline(mean(error_abs),'b--', ...
      sprintf('MAE = %.4f%%', mean(error_abs)),'LineWidth',1.2)
xline(cycle_idx(n_train+n_val+W+1),'k--','Inicio Test','LineWidth',1)
xlabel('Ciclo'); ylabel('Error absoluto SoH [%]')
title('Error absoluto de estimación por ciclo'); grid on

%% FIGURA 3 — Scatter
figure('Color','w','Name','Scatter Real vs Predicho');
scatter(Y_all_real*100, Y_pred_all*100, 15, cycles_pred_all,'filled');
hold on
ref = [min(Y_all_real)*100, max(Y_all_real)*100];
plot(ref, ref, 'k--','LineWidth',1.5)
colorbar; colormap('jet')
xlabel('SoH Real [%]'); ylabel('SoH Predicho [%]')
title(sprintf('Real vs Predicho  |  RMSE = %.4f%%', RMSE_test*100))
grid on; axis equal

%% =========================================================================
%  GUARDAR — todo lo necesario para la proyección
%  Guardamos también features_norm y cycle_idx (post n_skip)
%  para que la proyección no tenga que recalcular nada
%% =========================================================================
features_norm_saved = features_norm;   % post n_skip
cycle_idx_saved     = cycle_idx;       % post n_skip

save('LSTM_SoH_Model.mat', ...
    'net', ...
    'feat_min', 'feat_max', 'feat_range', ...
    'n_features', 'W', ...
    'Y_mean', 'Y_std', ...
    'RMSE_test', 'MAE_test', 'MaxE_test', ...
    'Y_pred_all', ...
    'Y_all_real', ...
    'cycles_pred_all', ...
    'features_norm_saved', ...
    'cycle_idx_saved', ...
    'n_skip');

fprintf('\n✔ Modelo guardado: LSTM_SoH_Model.mat\n');
fprintf('  Y_pred_all      : %d valores\n', length(Y_pred_all));
fprintf('  cycles_pred_all : %d valores\n', length(cycles_pred_all));
fprintf('  Último SoH LSTM : %.4f (%.2f%%)\n', Y_pred_all(end), Y_pred_all(end)*100);
fprintf('  Último ciclo    : %d\n', cycles_pred_all(end));

%% CALLBACK
function stop = liveTrainPlot(info, ax1, ax2, h_tr, h_val, h_lr)
    stop = false;
    if ~strcmp(info.State,'epoch'), return; end
    ep  = info.Epoch;
    xtr = get(h_tr,  'XData');  ytr  = get(h_tr,  'YData');
    xvl = get(h_val, 'XData');  yvl  = get(h_val, 'YData');
    xlr = get(h_lr,  'XData');  ylr  = get(h_lr,  'YData');
    if ~isnan(info.TrainingRMSE)
        xtr(end+1) = ep;  ytr(end+1) = info.TrainingRMSE;
        set(h_tr, 'XData',xtr, 'YData',ytr);
    end
    if ~isnan(info.ValidationRMSE)
        xvl(end+1) = ep;  yvl(end+1) = info.ValidationRMSE;
        set(h_val,'XData',xvl,'YData',yvl);
    end
    if ~isnan(info.LearnRate)
        xlr(end+1) = ep;  ylr(end+1) = info.LearnRate;
        set(h_lr, 'XData',xlr,'YData',ylr);
    end
    ax1.XLim = [1, max(ep+5, 20)];
    ax2.XLim = [1, max(ep+5, 20)];
    all_y = [ytr(~isnan(ytr)), yvl(~isnan(yvl))];
    if numel(all_y) > 1
        ax1.YLim = [max(1e-5, min(all_y)*0.5), max(all_y)*2];
    end
    drawnow limitrate;
end