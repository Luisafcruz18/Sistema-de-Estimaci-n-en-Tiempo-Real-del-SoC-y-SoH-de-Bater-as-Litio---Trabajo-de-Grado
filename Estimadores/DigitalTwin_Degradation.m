% =========================================================================
%      DIGITAL TWIN CON DEGRADACIÓN TRIFÁSICA JUSTIFICADA LITERARIAMENTE
%      V2 — Modelo knee-point validado en literatura
%
%  MODELO DE DEGRADACIÓN IMPLEMENTADO:
%
%  Fase 1 (ciclos 0 → N_knee): degradación lenta dominada por SEI
%           C(k) = Cn_nom * (1 - alpha_sei * sqrt(k))
%
%  Fase 2 (ciclos N_knee → EOL): aceleración por agrietamiento de
%           electrodo y pérdida de material activo (LAM)
%           C(k) = C(N_knee) * (1 - alpha_lam * (k - N_knee))
%
%  JUSTIFICACIÓN:
%  [1] Pinson & Bazant (2012), J. Electrochem. Soc. 160:A243.
%      Fundamentan sqrt(N) para dominio SEI.
%  [2] Severson et al. (2019), Nature Energy 4:383.
%      Confirman degradación negligible en los primeros 100 ciclos
%      y aceleración cerca del EOL ("knee-point").
%  [3] Attia et al. (NREL, 2022), DOE/79499.
%      Modelo NMC con términos SEI + agrietamiento de electrodo.
%      EOL a 80% capacidad, Rint aumenta ~50% al EOL.
%  [4] Wang et al. (2014), J. Power Sources 247:332.
%      Coeficientes empíricos de fade para celdas NMC/grafito.
%  [5] Burke & Zhao (EVS30, 2017). Criterio 20% capacidad / 50%
%      resistencia como estándar de fin de vida.
% =========================================================================

clear; clc; close all;

%% CONFIGURACIÓN GENERAL
Ts        = 1;
sim_hours = 60000;
t_total   = sim_hours * 3600;
N         = floor(t_total / Ts);
fprintf('Puntos temporales: %d (%.1f millones)\n', N, N/1e6);

%% PARÁMETROS NOMINALES
Cn_nom = 5.2;   % [Ah]
eta    = 1;

%% =========================================================================
% MODELO DE DEGRADACIÓN TRIFÁSICO — JUSTIFICADO EN LITERATURA
%
% FASE 1 — SEI dominante (sqrt(N)):
%   alpha_sei = 0.0003 produce ~10% de fade a 1111 ciclos
%   Referencia: Wang et al. (2014) reportan B≈0.0315 para NMC a 25°C
%   con z=0.55. Adaptado a nuestro rango de operación (C/10):
%   tasas bajas → degradación más lenta → alpha_sei conservador.
%
% FASE 2 — LAM + agrietamiento (lineal post-knee):
%   Activada cuando SoH < SoH_knee (típicamente 0.94-0.96 según [3])
%   alpha_lam produce caída más rápida hacia EOL
%   Referencia: Attia et al. (NREL 2022) identifican el knee-point
%   como transición entre pérdida de inventario Li (LLI) y pérdida
%   de material activo (LAM) que acelera la degradación.
%
% RESISTENCIA — sqrt(N) en ambas fases:
%   gamma_rise = 0.0008: produce ~50% de aumento al EOL
%   Criterio estándar: [Burke & Zhao 2017], [Wikipedia Li-ion]
%   "Ah throughput needed to increase resistance by about 50%"
% =========================================================================

% Coeficientes Fase 1 (SEI, sqrt-law)
alpha_sei   = 0.0012;    % fade lento inicial — dominado por SEI [1][2][4]
SoH_knee    = 0.94;      % punto de inflexión — inicio de LAM [3]

% Coeficientes Fase 2 (LAM, lineal post-knee)
% Se calcula dinámicamente para llegar a EOL en ~N_total ciclos
% alpha_lam se define abajo una vez conocido N_knee

% Resistencia (aplica en ambas fases)
gamma_rise  = 0.0016;    % ~50% aumento Rint al EOL [5]
SoH_EOL     = 0.80;

% Calcular el ciclo donde se alcanzará el knee-point con alpha_sei
% C(N_knee) = Cn_nom*(1 - alpha_sei*sqrt(N_knee)) = Cn_nom*SoH_knee
% N_knee = ((1-SoH_knee)/alpha_sei)^2
N_knee_est = ceil(((1 - SoH_knee) / alpha_sei)^2);
fprintf('\n=== PARÁMETROS DE DEGRADACIÓN ===\n');
fprintf('Fase 1 (SEI sqrt): alpha_sei = %.4f\n', alpha_sei);
fprintf('Knee-point estimado: ciclo ~%d (SoH=%.2f)\n', N_knee_est, SoH_knee);
fprintf('Fase 2 (LAM lineal): se activa post-knee\n');
fprintf('Resistencia: gamma_rise = %.4f\n', gamma_rise);
fprintf('EOL: SoH = %.2f\n\n', SoH_EOL);

%% PRE-ALLOCACIÓN
SoC          = zeros(N, 1);
Vt           = zeros(N, 1);
I_vec        = zeros(N, 1);
Vrc          = zeros(N, 1);
cycle_number = zeros(N, 1);
SoH_vec      = ones(N,  1);
Cn_vec       = zeros(N, 1);

%% ESTADO INICIAL
SoC(1)    = 1;
Vt(1)     = 16.4800*SoC(1)^3 - 35.0493*SoC(1)^2 + 27.6924*SoC(1) + 2.8081;
Cn_vec(1) = Cn_nom;
SoH_vec(1)= 1.0;

%% MÁQUINA DE ESTADOS
mode         = "discharge";
rest_counter = 0;
cycle        = 0;
N_knee_real  = NaN;   % se registra cuando realmente se cruza el knee
alpha_lam    = NaN;   % se calcula al cruzar el knee
Cn_at_knee   = NaN;

fprintf('Iniciando simulación...\n');
fprintf('Condición de parada: SoH <= %.2f o fin de tiempo\n\n', SoH_EOL);
tic;

for k = 2:N

    %% ----------------------------------------------------------------
    % CÁLCULO DE CAPACIDAD DEGRADADA — MODELO TRIFÁSICO
    %% ----------------------------------------------------------------

    if isnan(N_knee_real)
        % FASE 1: SEI dominante — sqrt(N)
        % C(k) = Cn_nom * (1 - alpha_sei * sqrt(cycle))
        % Ref: Pinson & Bazant (2012), Wang et al. (2014)
        Cn_k  = Cn_nom * (1 - alpha_sei * sqrt(max(cycle, 0)));
        Cn_k  = max(Cn_k, 0.5 * Cn_nom);
        SoH_k = Cn_k / Cn_nom;

        % Detectar cruce del knee-point
        if SoH_k <= SoH_knee && cycle > 10
            N_knee_real = cycle;
            Cn_at_knee  = Cn_k;

            % Calibrar alpha_lam para que EOL ocurra en ~2*N_knee ciclos
            % más (degradación post-knee 2x más rápida que pre-knee)
            % Ref: Severson et al. (2019) — aceleración observable post-knee
            cycles_to_EOL = N_knee_real;   % igual cantidad de ciclos extra
            delta_SoH     = SoH_knee - SoH_EOL;   % 0.94 - 0.80 = 0.14
            alpha_lam     = delta_SoH / (Cn_nom * cycles_to_EOL);
            % alpha_lam en unidades Ah/ciclo, convertimos a fracción:
            alpha_lam_frac = delta_SoH / cycles_to_EOL;

            fprintf('>>> Knee-point alcanzado en ciclo %d (SoH=%.4f)\n', ...
                    N_knee_real, SoH_k);
            fprintf('    alpha_lam calibrado = %.6f/ciclo\n', alpha_lam_frac);
        end
    else
        % FASE 2: LAM + agrietamiento — lineal post-knee
        % C(k) = C_knee - alpha_lam_frac * (k - N_knee)
        % Ref: Attia et al. NREL (2022), Severson et al. (2019)
        delta_ciclos = cycle - N_knee_real;
        SoH_k = SoH_knee - alpha_lam_frac * delta_ciclos;
        SoH_k = max(SoH_k, 0);
        Cn_k  = Cn_nom * SoH_k;
        Cn_k  = max(Cn_k, 0.5 * Cn_nom);
    end

    Cn_vec(k)  = Cn_k;
    SoH_vec(k) = SoH_k;

    %% EOL
    if SoH_k <= SoH_EOL && cycle > 0
        fprintf('>>> EOL alcanzado en ciclo %d (SoH = %.4f)\n', cycle, SoH_k);
        N = k;
        break;
    end

    %% TENSIÓN DE CORTE
    V_min_k = 9.2;

    %% MÁQUINA DE ESTADOS (sin cambios respecto a V1)
    current_time = (k-1) * Ts;

    switch mode
        case "charge"
            pulse_time = mod(current_time, 720);
            if pulse_time <= 600
                I_vec(k) = -0.5;
            else
                I_vec(k) = 0;
            end
            if SoC(k-1) >= 0.97
                mode = "rest_after_charge";
                rest_counter = 0;
            end

        case "rest_after_charge"
            I_vec(k) = 0;
            rest_counter = rest_counter + Ts;
            if rest_counter >= 300
                mode = "discharge";
            end

        case "discharge"
            pulse_time = mod(current_time, 720);
            if pulse_time <= 600
                I_vec(k) = 0.5;
            else
                I_vec(k) = 0;
            end
            if Vt(k-1) <= V_min_k
                mode = "rest_after_discharge";
                rest_counter = 0;
                cycle = cycle + 1;
                if mod(cycle, 50) == 0
                    fase_str = 'SEI';
                    if ~isnan(N_knee_real), fase_str = 'LAM'; end
                    fprintf('Ciclo %4d | SoH=%.4f | Fase: %s | t=%.1fh | real=%.1fs\n', ...
                        cycle, SoH_k, fase_str, current_time/3600, toc);
                end
            end

        case "rest_after_discharge"
            I_vec(k) = 0;
            rest_counter = rest_counter + Ts;
            if rest_counter >= 300
                mode = "charge";
            end
    end

    %% ECM
    [Vt(k), SoC(k), Vrc(k)] = batteryECM_step_degraded( ...
        SoC(k-1), Vrc(k-1), I_vec(k), Ts, Cn_k, eta, cycle, gamma_rise);

    Vt(k) = min(Vt(k), 12.6);
    Vt(k) = max(Vt(k), 8.0);
    cycle_number(k) = cycle;
end

%% TRUNCAR
SoC          = SoC(1:N);
Vt           = Vt(1:N);
I            = I_vec(1:N);
Vrc          = Vrc(1:N);
cycle_number = cycle_number(1:N);
SoH_vec      = SoH_vec(1:N);
Cn_vec       = Cn_vec(1:N);
t            = (0:N-1)' * Ts;
total_cycles = max(cycle_number);

fprintf('\n=================================================\n');
fprintf('SIMULACIÓN FINALIZADA\n');
fprintf('=================================================\n');
fprintf('Ciclos totales     : %d\n', total_cycles);
fprintf('Knee-point         : ciclo %d\n', N_knee_real);
fprintf('SoH final          : %.4f\n', SoH_vec(end));
fprintf('Tiempo simulado    : %.1f h\n', t(end)/3600);
fprintf('Tiempo real        : %.1f s\n', toc);

%% EXPORTAR
results = table(t, Vt, I, SoC, Vrc, cycle_number, SoH_vec, Cn_vec, ...
    'VariableNames',{'Time_s','Voltage_V','Current_A','SOC','Vrc', ...
                     'Cycle','SoH','Cn_Ah'});
writetable(results,'DT_Degradation_Dataset.csv');
save('DT_Degradation_Dataset.mat','t','Vt','I','SoC','Vrc', ...
     'cycle_number','SoH_vec','Cn_vec','Cn_nom');
fprintf('\n✔ Dataset exportado\n');

%% =========================================================================
% FIGURA PRINCIPAL — muestra las dos fases de degradación
%% =========================================================================
soh_per_cycle = zeros(total_cycles, 1);
for c = 1:total_cycles
    idx = find(cycle_number == c, 1,'last');
    if ~isempty(idx), soh_per_cycle(c) = SoH_vec(idx); end
end

figure('Color','w','Name','Degradación Trifásica - Resumen');

subplot(3,1,1)
plot(t/3600, Vt,'b','LineWidth',0.8)
xlabel('Tiempo [h]'); ylabel('Voltaje [V]')
title('Voltaje Terminal'); grid on

subplot(3,1,2)
plot(1:total_cycles, soh_per_cycle*100,'r','LineWidth',1.5); hold on
if ~isnan(N_knee_real)
    xline(N_knee_real,'b--', ...
          sprintf('Knee-point (ciclo %d)', N_knee_real), ...
          'LineWidth',1.2,'LabelVerticalAlignment','bottom')
end
yline(80,'k--','EOL (80%)','LineWidth',1.2)
% Sombrear las dos fases
if ~isnan(N_knee_real)
    patch([1 N_knee_real N_knee_real 1],[79 79 101 101], ...
          [0.8 0.9 1],'FaceAlpha',0.3,'EdgeColor','none', ...
          'DisplayName','Fase 1: SEI dominante (√N)')
    patch([N_knee_real total_cycles total_cycles N_knee_real],[79 79 101 101], ...
          [1 0.85 0.85],'FaceAlpha',0.3,'EdgeColor','none', ...
          'DisplayName','Fase 2: LAM + agrietamiento (lineal)')
end
xlabel('Ciclo'); ylabel('SoH [%]')
title('Degradación de SoH — Modelo trifásico (literatura)')
legend('Location','southwest','FontSize',7); grid on; ylim([79 101])

subplot(3,1,3)
plot(t/3600, SoC*100,'g','LineWidth',0.8)
xlabel('Tiempo [h]'); ylabel('SoC [%]')
title('Estado de Carga'); grid on

%% FUNCIÓN OCV
function Voc = ocv_model(soc)
    Voc = 16.4800*soc.^3 - 35.0493*soc.^2 + 27.6924*soc + 2.8081;
end