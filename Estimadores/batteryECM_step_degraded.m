% =========================================================================
%                  batteryECM_step_degraded.m
%
%          MODELO ECM THEVENIN 1RC CON DEGRADACIÓN
%
%  Igual que batteryECM_step.m pero Rint crece con sqrt(ciclo)
%
%  Entradas:
%    SoC_prev   - SoC del paso anterior
%    Vrc_prev   - tensión RC del paso anterior
%    I          - corriente [A] (+ descarga, - carga)
%    Ts         - paso temporal [s]
%    Cn         - capacidad actual degradada [Ah]
%    eta        - eficiencia coulómbica
%    cycle      - número de ciclo actual
%    gamma_rise - coeficiente de crecimiento de resistencia
%
%  Salidas:
%    Vt   - tensión terminal [V]
%    SoC  - estado de carga actualizado
%    Vrc  - tensión en la red RC
% =========================================================================

function [Vt, SoC, Vrc] = batteryECM_step_degraded( ...
                                SoC_prev, Vrc_prev, I, ...
                                Ts, Cn, eta, cycle, gamma_rise)

%% =========================================================================
% PARÁMETROS BASE (nominales, del paper)
%% =========================================================================

Rint_charge_0 = 0.09998944;
R0_charge_0   = 0.09999722;
C0_charge     = 4000.00;       % capacitancia RC no varía significativamente

Rint_dis_0    = 0.50523032;
R0_dis_0      = 0.55510210;
C0_dis        = 5380.22;

%% =========================================================================
% FACTOR DE DEGRADACIÓN DE RESISTENCIA
%  R(k) = R0 * (1 + gamma * sqrt(k))
%% =========================================================================

deg_factor = 1 + gamma_rise * sqrt(max(cycle, 0));

%% =========================================================================
% SELECCIÓN Y ESCALADO DE PARÁMETROS SEGÚN MODO
%% =========================================================================

if I < 0
    % CARGA
    Rint = Rint_charge_0 * deg_factor;
    R0   = R0_charge_0   * deg_factor;
    C0   = C0_charge;

elseif I > 0
    % DESCARGA
    Rint = Rint_dis_0 * deg_factor;
    R0   = R0_dis_0   * deg_factor;
    C0   = C0_dis;

else
    % REPOSO
    Rint = Rint_charge_0 * deg_factor;
    R0   = R0_charge_0   * deg_factor;
    C0   = C0_charge;
end

%% =========================================================================
% OCV(SoC) — curva de descarga (misma que en el paper)
%% =========================================================================

Voc = 16.4800 * SoC_prev^3 ...
    - 35.0493 * SoC_prev^2 ...
    + 27.6924 * SoC_prev   ...
    +  2.8081;

%% =========================================================================
% ACTUALIZAR SoC (Coulomb Counting con capacidad degradada)
%% =========================================================================

Ts_h = Ts / 3600;
SoC  = SoC_prev - (eta * Ts_h / Cn) * I;
SoC  = max(0, min(1, SoC));

%% =========================================================================
% DINÁMICA RC
%% =========================================================================

alpha = exp(-Ts / (R0 * C0));
Vrc   = alpha * Vrc_prev + R0 * (1 - alpha) * I;

%% =========================================================================
% TENSIÓN TERMINAL
%% =========================================================================

Vt = Voc - Rint * I - Vrc;

end
