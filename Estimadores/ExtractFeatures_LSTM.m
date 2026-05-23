% =========================================================================
%          EXTRACCIÓN DE FEATURES POR CICLO
%          Para entrenamiento de LSTM-SoH
%
%  Entrada:  DT_Degradation_Dataset.mat
%  Salida:   LSTM_Features_Dataset.mat
%            LSTM_Features_Dataset.csv
% =========================================================================

clear; clc; close all;

%% =========================================================================
% CARGAR DATASET DEL GEMELO
%% =========================================================================

fprintf('Cargando dataset...\n');
load('DT_Degradation_Dataset.mat');

total_cycles = max(cycle_number);
fprintf('Ciclos disponibles: %d\n', total_cycles);

%% =========================================================================
% CONFIGURACIÓN
%% =========================================================================

% Ciclos a usar (descartar el primero, suele ser incompleto)
cycles_to_use = 51:total_cycles;
n_cycles      = length(cycles_to_use);

%% =========================================================================
% PRE-ALLOCACIÓN DE FEATURES
%
%  Feature 1:  V_mean_dis      — Voltaje medio durante descarga
%  Feature 2:  V_min_dis       — Voltaje mínimo durante descarga
%  Feature 3:  V_range_dis     — Rango de voltaje (max-min) en descarga
%  Feature 4:  V_slope_dis     — Pendiente de caída de voltaje
%  Feature 5:  Q_dis           — Capacidad descargada [Ah]
%  Feature 6:  SOC_mean_dis    — SoC medio durante descarga
%  Feature 7:  SOC_range_dis   — Rango de SoC en descarga
%  Feature 8:  I_mean_dis      — Corriente media real de descarga
%  Feature 9:  V_mean_chg      — Voltaje medio durante carga
%  Feature 10: Q_chg           — Capacidad cargada [Ah]
%  Feature 11: cycle_norm      — Número de ciclo normalizado [0-1]
%
%  Etiqueta:   SoH             — Estado de salud en ese ciclo
%% =========================================================================

n_features = 11;
features   = zeros(n_cycles, n_features);
labels_SoH = zeros(n_cycles, 1);
labels_Cn  = zeros(n_cycles, 1);
cycle_idx  = zeros(n_cycles, 1);

fprintf('\nExtrayendo features por ciclo...\n');

for ci = 1:n_cycles

    c = cycles_to_use(ci);

    %% ----------------------------------------------------------------
    % ÍNDICES DEL CICLO COMPLETO
    %% ----------------------------------------------------------------

    idx_all = find(cycle_number == c);

    if length(idx_all) < 10
        % Ciclo incompleto, copiar features del anterior si existe
        if ci > 1
            features(ci,:)   = features(ci-1,:);
            labels_SoH(ci)   = labels_SoH(ci-1);
        end
        continue;
    end

    %% ----------------------------------------------------------------
    % SEPARAR FASES DEL CICLO
    %% ----------------------------------------------------------------

    % Descarga: corriente positiva
    idx_dis = idx_all(I(idx_all) > 0.01);

    % Carga: corriente negativa
    idx_chg = idx_all(I(idx_all) < -0.01);

    %% ----------------------------------------------------------------
    % FEATURES DE DESCARGA
    %% ----------------------------------------------------------------

    if length(idx_dis) > 5

        V_dis = Vt(idx_dis);
        S_dis = SoC(idx_dis);
        I_dis = I(idx_dis);
        t_dis = (idx_dis - idx_dis(1)) * 1;   % tiempo relativo [s]

        % Voltaje
        features(ci, 1) = mean(V_dis);
        features(ci, 2) = min(V_dis);
        features(ci, 3) = max(V_dis) - min(V_dis);

        % Pendiente de voltaje (regresión lineal simple)
        if length(t_dis) > 2
            p = polyfit(t_dis / t_dis(end), V_dis, 1);
            features(ci, 4) = p(1);   % pendiente normalizada
        else
            features(ci, 4) = 0;
        end

        % Capacidad descargada [Ah]
        Ts_h = 1 / 3600;
        features(ci, 5) = sum(I_dis) * Ts_h;

        % SoC
        features(ci, 6) = mean(S_dis);
        features(ci, 7) = max(S_dis) - min(S_dis);

        % Corriente media real
        features(ci, 8) = mean(I_dis);

    else
        % Sin datos de descarga suficientes: copiar del ciclo anterior
        if ci > 1
            features(ci, 1:8) = features(ci-1, 1:8);
        end
    end

    %% ----------------------------------------------------------------
    % FEATURES DE CARGA
    %% ----------------------------------------------------------------

    if length(idx_chg) > 5

        V_chg = Vt(idx_chg);
        I_chg = I(idx_chg);
        Ts_h  = 1 / 3600;

        features(ci, 9)  = mean(V_chg);
        features(ci, 10) = abs(sum(I_chg)) * Ts_h;   % Ah cargados

    else
        if ci > 1
            features(ci, 9:10) = features(ci-1, 9:10);
        end
    end

    %% ----------------------------------------------------------------
    % CICLO NORMALIZADO
    %% ----------------------------------------------------------------

    features(ci, 11) = c / total_cycles;

    %% ----------------------------------------------------------------
    % ETIQUETA SoH — valor al final del ciclo
    %% ----------------------------------------------------------------

    labels_SoH(ci) = SoH_vec(idx_all(end));
    labels_Cn(ci)  = Cn_vec(idx_all(end));
    cycle_idx(ci)  = c;

end

fprintf('Features extraídas para %d ciclos.\n', n_cycles);

%% =========================================================================
% NORMALIZACIÓN MIN-MAX DE FEATURES
%% =========================================================================

feat_min  = min(features, [], 1);
feat_max  = max(features, [], 1);
feat_range = feat_max - feat_min;
feat_range(feat_range == 0) = 1;   % evitar división por cero

features_norm = (features - feat_min) ./ feat_range;

fprintf('\nEstadísticas de features normalizadas:\n');
fprintf('  Min global: %.4f\n', min(features_norm(:)));
fprintf('  Max global: %.4f\n', max(features_norm(:)));
fprintf('  Media SoH labels: %.4f\n', mean(labels_SoH));
fprintf('  SoH range: [%.4f, %.4f]\n', min(labels_SoH), max(labels_SoH));

%% =========================================================================
% GUARDAR
%% =========================================================================

save('LSTM_Features_Dataset.mat', ...
    'features', 'features_norm', ...
    'labels_SoH', 'labels_Cn', ...
    'cycle_idx', 'feat_min', 'feat_max', 'feat_range', ...
    'n_features', 'n_cycles', 'total_cycles');

% CSV para inspección
T = array2table([cycle_idx, features, labels_SoH, labels_Cn], ...
    'VariableNames', { ...
        'Cycle', ...
        'V_mean_dis','V_min_dis','V_range_dis','V_slope_dis', ...
        'Q_dis_Ah','SOC_mean_dis','SOC_range_dis','I_mean_dis', ...
        'V_mean_chg','Q_chg_Ah','cycle_norm', ...
        'SoH','Cn_Ah'});

writetable(T, 'LSTM_Features_Dataset.csv');

fprintf('\n✔ Guardado: LSTM_Features_Dataset.mat / .csv\n');

%% =========================================================================
% VISUALIZACIÓN DE FEATURES VS SoH
%% =========================================================================

feature_names = {'V_{mean} desc','V_{min} desc','V_{range} desc', ...
                 'V_{slope}','Q_{dis} [Ah]','SOC_{mean}','SOC_{range}', ...
                 'I_{mean}','V_{mean} carga','Q_{chg} [Ah]','Ciclo norm.'};

figure('Color','w','Name','Features vs SoH','Position',[100 100 1200 700]);

for fi = 1:n_features
    subplot(3, 4, fi)
    scatter(features(:, fi), labels_SoH, 5, cycle_idx, 'filled')
    xlabel(feature_names{fi}, 'FontSize', 8)
    ylabel('SoH')
    grid on
    colorbar
end
sgtitle('Correlación Features vs SoH (color = número de ciclo)')

%% =========================================================================
% CORRELACIÓN DE PEARSON — AYUDA A SELECCIONAR MEJORES FEATURES
%% =========================================================================

fprintf('\nCorrelación de Pearson con SoH:\n');
fprintf('%-20s  %8s\n', 'Feature', 'Corr');
fprintf('%s\n', repmat('-', 1, 32));

for fi = 1:n_features
    r = corr(features(:, fi), labels_SoH);
    fprintf('%-20s  %8.4f\n', feature_names{fi}, r);
end
