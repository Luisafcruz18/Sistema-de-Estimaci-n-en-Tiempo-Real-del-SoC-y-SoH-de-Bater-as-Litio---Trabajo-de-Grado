% =========================================================================
%     PROYECCIÓN FUTURA DE SoH — V7 FINAL
%     Modo: sigue la curva real ciclo a ciclo, luego proyecta
% =========================================================================
clear; clc; close all;

%% CONFIGURACIÓN
SoH_objetivo    = 0.80;
horas_por_ciclo = 11.0;
max_ciclos_proj = 90000;

%% CARGAR
fprintf('Cargando modelo...\n');
load('LSTM_SoH_Model.mat');
W = double(W);

fprintf('Cargando features...\n');
load('LSTM_Features_Dataset.mat');

% Aplicar n_skip igual que en entrenamiento
features_norm = features_norm(n_skip+1 : end, :);
labels_SoH    = labels_SoH(n_skip+1 : end);
cycle_idx     = cycle_idx(n_skip+1 : end);
n_cycles      = size(features_norm, 1);

fprintf('Ciclos disponibles: %d\n', n_cycles);
fprintf('Último SoH real   : %.4f (%.2f%%)\n', labels_SoH(end), labels_SoH(end)*100);

%% =========================================================================
% FASE 1 — ESTIMACIÓN LSTM SIGUIENDO LOS DATOS REALES CICLO A CICLO
% La LSTM avanza con la ventana deslizante sobre features reales.
% Esto garantiza que al llegar al último ciclo, la red tiene el
% contexto correcto de la trayectoria completa de degradación.
%% =========================================================================
fprintf('\nFase 1: estimación LSTM sobre datos reales...\n');

n_est        = n_cycles - W;
SoH_est      = zeros(n_est, 1);
ciclos_est   = zeros(n_est, 1);

for i = 1:n_est
    ventana      = features_norm(i : i+W-1, :)';   % [n_features x W]
    pred_norm    = predict(net, {ventana}, 'MiniBatchSize', 1);
    SoH_est(i)   = double(pred_norm) * Y_std + Y_mean;
    ciclos_est(i) = cycle_idx(i + W);
end

fprintf('Estimación completa. Último punto:\n');
fprintf('  Ciclo : %d\n',            ciclos_est(end));
fprintf('  SoH   : %.4f (%.2f%%)\n', SoH_est(end), SoH_est(end)*100);

%% =========================================================================
% FASE 2 — PROYECCIÓN DESDE EL ÚLTIMO PUNTO REAL
% La ventana de arranque son los últimos W ciclos REALES del dataset.
% La LSTM acaba de procesar esta secuencia en el último paso de la
% fase 1, por lo que tiene el contexto correcto.
% El SoH de arranque es el último valor estimado en la fase 1.
%% =========================================================================
%% =========================================================================
% FASE 2 — PROYECCIÓN (reemplazar el bloque completo)
%% =========================================================================
fprintf('\nFase 2: proyección desde último punto real...\n');

SoH_arranque = SoH_est(end);
ciclo_base   = ciclos_est(end);

fprintf('  SoH arranque: %.4f (%.2f%%)\n', SoH_arranque, SoH_arranque*100);
fprintf('  Ciclo base  : %d\n', ciclo_base);

if SoH_arranque <= SoH_objetivo
    fprintf('⚠ SoH ya en/bajo el objetivo.\n');
else
    % -----------------------------------------------------------------
    % CALCULAR TASA DE DEGRADACIÓN REAL de los últimos 200 ciclos
    % para usarla como guía y evitar que la proyección suba
    % -----------------------------------------------------------------
    n_ref = min(200, length(SoH_est)-1);
    tasa_real = (SoH_est(end-n_ref) - SoH_est(end)) / n_ref;
    % tasa_real es positiva: cuánto baja el SoH por ciclo
    fprintf('  Tasa degradación últimos %d ciclos: %.6f/ciclo (%.4f%%/ciclo)\n', ...
            n_ref, tasa_real, tasa_real*100);

    ventana_actual     = features_norm(end-W+1 : end, :);
    SoH_proy           = zeros(max_ciclos_proj, 1);
    ciclo_proy         = zeros(max_ciclos_proj, 1);
    SoH_proy(1)        = SoH_arranque;
    ciclo_proy(1)      = ciclo_base;
    ciclo_objetivo_val = NaN;
    SoH_anterior       = SoH_arranque;
    n_proj             = 1;
    ciclo_max_norm     = cycle_idx(end) + max_ciclos_proj;

    for paso = 1:max_ciclos_proj-1

        entrada   = ventana_actual';
        pred_norm = predict(net, {entrada}, 'MiniBatchSize', 1);
        SoH_lstm  = double(pred_norm) * Y_std + Y_mean;

        % -----------------------------------------------------------------
        % COMBINAR predicción LSTM con tendencia real
        % Si la LSTM predice subida, ignorarla y aplicar la tasa real.
        % Si predice bajada coherente, mezclar 50/50.
        % Esto evita el bucle de retroalimentación positiva.
        % -----------------------------------------------------------------
        SoH_tendencia = SoH_anterior - tasa_real;   % degradación lineal garantizada

        if SoH_lstm >= SoH_anterior
            % La LSTM quiere subir — ignorarla completamente
            SoH_pred = SoH_tendencia;
        else
            % La LSTM predice bajada — mezclar con la tendencia
            SoH_pred = 0.5 * SoH_lstm + 0.5 * SoH_tendencia;
        end

        % Clamp: nunca puede subir respecto al punto anterior
        SoH_pred = min(SoH_pred, SoH_anterior);

        n_proj = n_proj + 1;
        ciclo_proy(n_proj) = ciclo_base + paso;
        SoH_proy(n_proj)   = SoH_pred;

        if SoH_pred <= SoH_objetivo && isnan(ciclo_objetivo_val)
            ciclo_objetivo_val = ciclo_base + paso;
            fprintf('>>> Objetivo %.0f%% en ciclo %d\n', ...
                    SoH_objetivo*100, ciclo_objetivo_val);
        end

        % Actualizar ventana — features solo pueden decrecer
        nueva_fila     = ventana_actual(end, :);
        nueva_fila(11) = (ciclo_base + paso) / ciclo_max_norm;

        if SoH_anterior > 0
            fd = SoH_pred / SoH_anterior;
            fd = min(fd, 1.0);   % ← nunca permitir subida de features
            nueva_fila(1) = nueva_fila(1) * fd;
            nueva_fila(2) = nueva_fila(2) * fd;
            nueva_fila(5) = nueva_fila(5) * fd;
        end

        ventana_actual = [ventana_actual(2:end,:); nueva_fila];
        SoH_anterior   = SoH_pred;

        if SoH_pred <= (SoH_objetivo - 0.02), break; end

        if mod(paso, 10000) == 0
            fprintf('  Ciclo %d | SoH %.2f%%\n', ciclo_base+paso, SoH_pred*100);
        end
    end

    SoH_proy   = SoH_proy(1:n_proj);
    ciclo_proy = ciclo_proy(1:n_proj);
end

%% RESULTADOS
fprintf('\n=================================================\n');
fprintf('RESULTADOS — V7\n');
fprintf('=================================================\n');

if ~isnan(ciclo_objetivo_val)
    ciclos_rest  = ciclo_objetivo_val - ciclo_base;
    horas_rest   = ciclos_rest * horas_por_ciclo;
    dias_rest    = horas_rest / 24;
    fprintf('Ciclos hasta objetivo : %d\n',    ciclos_rest);
    fprintf('Tiempo estimado       : %.1f h\n', horas_rest);
    fprintf('Días equivalentes     : %.1f\n',   dias_rest);
    fprintf('Semanas equivalentes  : %.1f\n',   dias_rest/7);
else
    fprintf('⚠ Objetivo no alcanzado en %d ciclos.\n', max_ciclos_proj);
    ciclos_rest = NaN; horas_rest = NaN; dias_rest = NaN;
end

%% =========================================================================
% FIGURA 1 — Todo junto: real + estimación LSTM + proyección
%% =========================================================================
figure('Color','w','Name','Proyección SoH — LSTM V7', ...
       'Position',[100 100 1050 520]);

% SoH real del gemelo
plot(cycle_idx(W+1:end), labels_SoH(W+1:end)*100, 'b-', ...
     'LineWidth', 1.5, 'DisplayName', 'SoH real (gemelo)');
hold on

% Estimación LSTM sobre datos reales (fase 1)
plot(ciclos_est, SoH_est*100, 'r-', ...
     'LineWidth', 1.8, 'DisplayName', 'SoH LSTM (estimado)');

% Proyección (fase 2) — continúa desde el último punto rojo
if ~isnan(ciclo_objetivo_val)
    plot(ciclo_proy, SoH_proy*100, 'm--', ...
         'LineWidth', 2, 'DisplayName', 'SoH proyectado (LSTM)');

    % Punto de unión
    plot(ciclo_base, SoH_arranque*100, 'ko', ...
         'MarkerSize', 9, 'MarkerFaceColor', 'k', ...
         'DisplayName', 'Arranque proyección');

    % EOL
    plot(ciclo_objetivo_val, SoH_objetivo*100, 'gp', ...
         'MarkerSize', 14, 'MarkerFaceColor', 'g', ...
         'DisplayName', sprintf('EOL ciclo %d', ciclo_objetivo_val));

    text(ciclo_objetivo_val + ciclos_rest*0.02, ...
         SoH_objetivo*100 + 1.5, ...
         sprintf('+%d ciclos\n≈ %.0f h\n≈ %.0f días', ...
                 ciclos_rest, horas_rest, dias_rest), ...
         'FontSize', 9, 'Color', [0 0.5 0], 'FontWeight', 'bold');
end

xline(ciclo_base, 'k:', 'Inicio proyección', ...
      'LineWidth', 1.2, 'LabelVerticalAlignment', 'bottom', ...
      'LabelHorizontalAlignment', 'right');
yline(SoH_objetivo*100, 'g--', ...
      sprintf('Objetivo: %.0f%%', SoH_objetivo*100), 'LineWidth', 1.5);

xlabel('Ciclo'); ylabel('SoH [%]');
title('Proyección de vida útil remanente — Modelo LSTM V7');
legend('Location', 'southwest'); grid on;

%% FIGURA 2 — Barra de vida útil
if ~isnan(ciclo_objetivo_val)
    figure('Color','w','Name','Vida Útil Remanente', ...
           'Position',[100 660 750 210]);

    SoH_inicio     = SoH_est(1);
    vida_consumida = max(0, min(1, ...
                        (SoH_inicio - SoH_arranque) / ...
                        (SoH_inicio - SoH_objetivo)));
    vida_restante  = 1 - vida_consumida;

    b = barh(1, [vida_consumida, vida_restante], 'stacked');
    b(1).FaceColor = [0.85 0.2 0.2];
    b(2).FaceColor = [0.2  0.7 0.2];
    xlim([0 1]); ylim([0.5 1.5]); yticks([]);
    xticks(0:0.1:1);
    xticklabels(arrayfun(@(x) sprintf('%.0f%%',x*100), ...
                0:0.1:1,'UniformOutput',false));
    title('Estado de Vida Útil del Banco de Baterías');
    text(vida_consumida/2, 1, ...
         sprintf('Consumida\n%.1f%%', vida_consumida*100), ...
         'HorizontalAlignment','center','FontSize',11, ...
         'Color','w','FontWeight','bold');
    text(vida_consumida + vida_restante/2, 1, ...
         sprintf('Restante\n%.1f%%\n(%.0f días)', ...
                 vida_restante*100, dias_rest), ...
         'HorizontalAlignment','center','FontSize',11, ...
         'Color','w','FontWeight','bold');
    grid on;
end

%% FIGURA 3 — Tasa de degradación proyectada
if exist('SoH_proy','var') && n_proj > 2
    figure('Color','w','Name','Tasa de degradación', ...
           'Position',[100 100 750 300]);
    dSoH = -diff(SoH_proy) * 100;
    plot(ciclo_proy(2:end), dSoH, 'Color',[0.8 0.2 0.2], 'LineWidth',1);
    hold on
    yline(mean(dSoH), 'b--', ...
          sprintf('Media = %.5f%%/ciclo', mean(dSoH)), 'LineWidth',1.2);
    xlabel('Ciclo'); ylabel('Pérdida SoH por ciclo [%]');
    title('Tasa de degradación proyectada'); grid on;
end

fprintf('\n✔ Proyección V7 completada.\n');