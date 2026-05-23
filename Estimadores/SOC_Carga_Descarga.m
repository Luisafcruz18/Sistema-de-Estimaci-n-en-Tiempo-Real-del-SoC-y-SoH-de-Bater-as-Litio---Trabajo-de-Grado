% --- GEMELO DIGITAL: MONITOREO + FILTRADO + PERFIL DINÁMICO + SOC (V15) ---
clear all; clc;
if ~isempty(serialportfind), delete(serialportfind); end

% --- CONFIGURACIÓN DE PUERTOS ---
puertoArdu = "COM4"; 
puertoBK = "COM9"; 
puertoK = "COM11"; 
baudios = 9600;

% --- VARIABLES DE CONTROL Y HISTÉRESIS ---
vLimiteCarga = 12.6; 
vLimiteDescarga = 9; 
estadoLogico = 1;

% --- VARIABLES DE CONTROL Y FILTRADO ---
maxPuntos = 100;

dataVArdu = NaN(1, maxPuntos); 
dataVBK   = NaN(1, maxPuntos);

dataIArdu = NaN(1, maxPuntos); 
dataIBK   = NaN(1, maxPuntos);

% =========================
% SOC
% =========================
SOC_hist = NaN(1, maxPuntos);

tiempo = 1:maxPuntos;

estadoAnterior = -1;

alpha = 0.15; 
vFilt = 0; 
iFilt = 0;

logSesion = []; 
timestampSesion = datestr(now, 'yyyy-mm-dd_HHMM');

% ============================================================
% SOC + COULOMB COUNTING + UKF SIMPLE
% ============================================================
Qnom = 5.2;              % Ah nominal batería
eta = 0.995;
dt = 1;

SOC = 0.5;              % SOC inicial

% ============================================================
% SOH - LSTM
% ============================================================

load('LSTM_SoH_Model.mat');

SOH = 1.0;
SOH_percent = 100;

SOH_hist = NaN(1, maxPuntos);

% Buffer ventana LSTM
feature_window = [];

% Datos ciclo actual
cycle_V = [];
cycle_I = [];
cycle_SOC = [];

cycle_count = 0;



iPrev = 0;


% Kalman simple
P = 0.01;
Qk = 0.0001;
Rk = 0.01;

% ============================================================
% CURVA REAL VOC vs SOC (3S2P Li-ion)
% ============================================================

OCV = @(SOC) ...
    16.4800*(SOC.^3) ...
    -35.0493*(SOC.^2) ...
    +27.6924*SOC ...
    +2.8081;

% --- PERFILES DINÁMICOS ---
durDescarga = [420, 900, 420, 900]; 
corrDescarga = [1.4, 0.0, 2.4, 0.0]; 
metasDescarga = [0.5, 0.0, 0.9, 0.0]; 

durCarga = [420, 900, 420, 900];
corrCarga = [0.600, 0.0, 1.100, 0.0]; 

vKeithley = 15.22;

% --- COMPENSACIÓN DINÁMICA ---
pasoActual = 1; 
timerPaso = tic; 
timerCompensacion = tic;

corrienteObjetivo = 0; 

alcanzoMeta = false; 

muestrasSimilaresReq = 8;
contadorEstabilidad = 0; 
iAnteriorEstable = 0; 
pasosVerifRealizados = 0;

pasosVerifReq = 7; 
margenRuido = 0.035; 

% --- MAPEO FÍSICO ---
mapeo = containers.Map();

mapeo('2873714600000096') = 8; 
mapeo('2846CB4400000065') = 1; 
mapeo('28D602450000008A') = 2; 
mapeo('28D4B6440000003B') = 3; 
mapeo('28B67B460000005F') = 7; 
mapeo('2800174500000052') = 6; 
mapeo('28DDCB440000002C') = 5; 
mapeo('28CD964600000009') = 4; 

% ============================================================
% INTERFAZ GRÁFICA
% ============================================================

fig1 = figure('Name', 'Gemelo Digital', ...
              'NumberTitle', 'off', ...
              'Color', 'w', ...
              'Position', [100, 400, 560, 550], ...
              'MenuBar', 'none', ...
              'ToolBar', 'none');

subplot(2,1,1);

h_heatmap = imagesc(zeros(2, 4)); 
colorbar; 
colormap('parula'); 

title('Mapa de Calor del Banco de Baterías (°C)'); 

xticks(1:4); 
yticks(1:2); 

caxis([20 45]); 
grid on;

h_panel = uicontrol('Style', 'text', ...
                    'Parent', fig1, ...
                    'Units', 'normalized', ...
                    'Position', [0.1, 0.15, 0.8, 0.25], ...
                    'BackgroundColor', 'w', ...
                    'FontSize', 10, ...
                    'FontName', 'Consolas', ...
                    'HorizontalAlignment', 'left');

% --- BOTÓN DE GUARDADO ---
solicitudGuardar = false;

btn_save = uicontrol('Style', 'pushbutton', ...
                     'String', 'GUARDAR LOG AHORA', ...
                     'Units', 'normalized', ...
                     'Position', [0.2, 0.05, 0.6, 0.07], ...
                     'BackgroundColor', [0.8 0.9 1], ...
                     'FontWeight', 'bold', ...
                     'Callback', @(src, event) evalin('base', 'solicitudGuardar = true;'));

% ============================================================
% FIGURA ELÉCTRICA
% ============================================================

fig2 = figure('Name', 'Análisis Eléctrico', ...
              'NumberTitle', 'off', ...
              'Color', 'w', ...
              'Position', [670, 400, 560, 620]);

% ---------------- VOLTAJE ----------------
axV = subplot(4,1,1);
hold on; 
grid on;

p_vArdu = plot(NaN, NaN, 'r', ...
               'LineWidth', 1.5, ...
               'DisplayName', 'V Ardu');

p_vBK = plot(NaN, NaN, 'b--', ...
             'DisplayName', 'V BK');

legend('show', 'Location', 'northeastoutside'); 
title('Voltajes (V)');

% ---------------- CORRIENTE ----------------
axI = subplot(4,1,2); 
hold on; 
grid on;

p_iArdu = plot(NaN, NaN, 'm', ...
               'LineWidth', 1.5, ...
               'DisplayName', 'I Ardu');

p_iBK = plot(NaN, NaN, 'k--', ...
             'DisplayName', 'I BK');

legend('show', 'Location', 'northeastoutside'); 
title('Corrientes (A)');

% ---------------- SOC ----------------
axSOC = subplot(4,1,3);

hold on;
grid on;

p_soc = plot(NaN, NaN, ...
             'g', ...
             'LineWidth', 2, ...
             'DisplayName', 'SOC');

title('SOC en Tiempo Real (%)');

xlabel('Muestras');
ylabel('SOC (%)');

ylim([0 100]);

legend('show');

calcCS = @(msg) mod(sum(msg(1:25)), 256);

vBK_last = 0; 
iBK_last = 0;


% ---------------- SOH ----------------
axSOH = subplot(4,1,4);

hold on;
grid on;

p_soh = plot(NaN, NaN, ...
             'c', ...
             'LineWidth', 2, ...
             'DisplayName', 'SOH');

title('SOH en Tiempo Real (%)');

xlabel('Muestras');
ylabel('SOH (%)');

ylim([70 100]);

legend('show');




try

    s = serialport(puertoArdu, baudios, "Timeout", 5); 
    configureTerminator(s, "LF");

    bk = serialport(puertoBK, baudios, "Timeout", 1); 

    k = serialport(puertoK, baudios, "Timeout", 1); 
    configureTerminator(k, "LF");
    
    writeline(k, 'SYST:REM'); 
    pause(0.1);

    writeline(k, 'APPL CH2, 0.0, 0.0'); 
    pause(0.1);

    writeline(k, 'OUTP ON'); 
    
    write(bk, uint8([170, 0, 32, 1, zeros(1, 21), 203]), "uint8"); 
    pause(0.2);

    cmdQuery = uint8([170, 0, 95, zeros(1, 22), 9]);
    
    contador = 1;

    while ishandle(fig1) && ishandle(fig2)

        % ============================================================
        % GUARDADO MANUAL
        % ============================================================

        if solicitudGuardar

            nombreManual = ['MANUALSOCSOH_SAVE_' ...
                            datestr(now, 'HHMMSS') '_' ...
                            timestampSesion '.mat'];

            save(nombreManual, 'logSesion');

            fprintf('Guardado manual exitoso: %s\n', nombreManual);

            solicitudGuardar = false; 

        end

        if s.NumBytesAvailable > 0

            datosRaw = readline(s);

            partes = strsplit(strtrim(datosRaw), ',');

            if length(partes) >= 11

                % ====================================================
                % PROCESAMIENTO ARDUINO
                % ====================================================

                vRaw = str2double(partes{1}) * 5.0 * 0.9845; 

                iRaw = ((str2double(partes{2}) - 2.5) / 0.066) - 0.190;

                if isnan(vRaw)
                    vRaw = vFilt;
                end

                vFilt = (1 - alpha) * vFilt + alpha * vRaw; 

                iFilt = (1 - alpha) * iFilt + alpha * iRaw;

                % ====================================================
                    % SOC : COULOMB COUNTING
                    % ====================================================
                    
                    SOC_pred = SOC - ((iFilt * dt * eta) / (Qnom * 3600));
                    
                    SOC_pred = max(0, min(1, SOC_pred));
                    
                    % ====================================================
                    % OCV ACTUAL Y ANTERIOR
                    % ====================================================
                    
                    Voc_k   = OCV(SOC_pred);
                    Voc_km1 = OCV(SOC);
                    
                    % ====================================================
                    % SELECCIÓN DE PARÁMETROS THEVENIN
                    % ====================================================
                    
                    if estadoLogico == 1
                    
                        % CARGA
                        Rint = 0.09998944;
                        R0   = 0.09997222;
                        C0   = 4000;
                    
                    else
                    
                        % DESCARGA
                        Rint = 0.50523032;
                        R0   = 0.55510210;
                        C0   = 5380.22;
                    
                    end
                    
                    % ====================================================
                    % MODELO THEVENIN 1RC DISCRETO
                    % ====================================================
                    
                    expTerm = exp(-dt / (R0 * C0));
                    
                    V_pred = Voc_k ...
                           + (vFilt - Voc_km1) * expTerm ...
                           - (R0 - (R0 + Rint) * expTerm) * iPrev ...
                           - Rint * iFilt;
                    
                    % ====================================================
                    % KALMAN ESCALAR
                    % ====================================================
                    
                    P_pred = P + Qk;
                    
                    K = P_pred / (P_pred + Rk);
                    
                    % Corrección del SOC usando error de voltaje
                    
                    SOC = SOC_pred + K * (vFilt - V_pred);
                    
                    P = (1 - K) * P_pred;
                    
                    SOC = max(0, min(1, SOC));
                    
                    SOC_percent = SOC * 100;
                    
                    % ====================================================
                    % ACTUALIZAR VARIABLES PREVIAS
                    % ====================================================
                    
                    iPrev = iFilt;


                   % ====================================================
                    % ACUMULAR DATOS PARA SOH
                    % ====================================================
                    
                    cycle_V(end+1)   = vFilt;
                    cycle_I(end+1)   = iFilt;
                    cycle_SOC(end+1) = SOC;


                % ====================================================
                % LÓGICA DE ESTADOS
                % ====================================================

                enValleReposo = (estadoLogico == 1) && ...
                                (corrCarga(pasoActual) == 0);
                
                if estadoLogico == 1

                    if enValleReposo && (vFilt >= vLimiteCarga)

                        estadoLogico = 0;

                        fprintf('[%s] Transición CARGA→DESCARGA: V=%.3f V (valle reposo, paso %d)\n', ...
                                datestr(now,'HH:MM:SS'), ...
                                vFilt, ...
                                pasoActual);

                    end

                else

                    if vFilt <= vLimiteDescarga

                        estadoLogico = 1;

                        fprintf('[%s] Transición DESCARGA→CARGA: V=%.3f V\n', ...
                                datestr(now,'HH:MM:SS'), ...
                                vFilt);

                    end

                end
                
                necesitaCambioBK = false; 
                necesitaCambioK = false; 
                esCompensando = false;

                % ====================================================
                % CONTROL
                % ====================================================

                if estadoLogico == 0

                    if estadoAnterior ~= 0

                        pasoActual = 1; 
                        timerPaso = tic; 
                        timerCompensacion = tic; 

                        alcanzoMeta = false;

                        corrienteObjetivo = corrDescarga(pasoActual);

                        necesitaCambioBK = true; 
                        necesitaCambioK = true;

                    elseif toc(timerPaso) > durDescarga(pasoActual)

                        pasoActual = mod(pasoActual, length(corrDescarga)) + 1;

                        timerPaso = tic; 
                        timerCompensacion = tic; 

                        alcanzoMeta = false;

                        corrienteObjetivo = corrDescarga(pasoActual);

                        necesitaCambioBK = true;

                    end
                    
                    metaActual = metasDescarga(pasoActual);

                    if metaActual > 0

                        if ~alcanzoMeta

                            if iFilt >= (metaActual - 0.02)

                                alcanzoMeta = true; 
                                timerPaso = tic;

                            else

                                timerPaso = tic;

                            end

                        end

                        if toc(timerCompensacion) > 10

                            if abs(iFilt - iAnteriorEstable) < margenRuido

                                contadorEstabilidad = contadorEstabilidad + 1;

                            else

                                contadorEstabilidad = 0;

                            end

                            iAnteriorEstable = iFilt;

                            if contadorEstabilidad >= muestrasSimilaresReq && ...
                               iFilt < (metaActual - 0.02)

                                corrienteObjetivo = min(corrienteObjetivo + 0.05, 4.5);

                                necesitaCambioBK = true; 

                                esCompensando = true; 

                                contadorEstabilidad = 0;

                            end

                        end

                    else

                        alcanzoMeta = true;

                    end

                    colorEst = [0.8 0 0]; 

                    txtM = 'DESCARGA';

                    if esCompensando
                        txtM = 'DESCARGA (COMPENSANDO)';
                    end

                else

                    if estadoAnterior ~= 1

                        pasoActual = 1; 
                        timerPaso = tic; 

                        corrienteObjetivo = corrCarga(pasoActual);

                        necesitaCambioK = true; 
                        necesitaCambioBK = true;

                    elseif toc(timerPaso) > durCarga(pasoActual)

                        pasoActual = mod(pasoActual, length(corrCarga)) + 1;

                        timerPaso = tic; 

                        corrienteObjetivo = corrCarga(pasoActual);

                        necesitaCambioK = true;

                    end

                    colorEst = [0 0.5 0]; 

                    txtM = 'CARGA';

                    if enValleReposo
                        txtM = 'CARGA (VALLE - Midiendo V real)';
                    end

                end

                % ====================================================
                % BK Y KEITHLEY
                % ====================================================

                if necesitaCambioBK

                    flush(bk);

                    valI = uint32((estadoLogico == 0) * ...
                                  corrienteObjetivo * 10000);

                    bytesI = typecast(valI, 'uint8');

                    cmdSetI = uint8([170, 0, 42, ...
                                     bytesI(1:4), ...
                                     zeros(1, 18), 0]);

                    cmdSetI(26) = calcCS(cmdSetI);

                    write(bk, cmdSetI, "uint8");

                    pause(0.05);

                    cmdPwr = uint8([170, 0, 33, ...
                                    uint8(valI > 0), ...
                                    zeros(1, 21), 0]);

                    cmdPwr(26) = calcCS(cmdPwr);

                    write(bk, cmdPwr, "uint8");

                end

                if necesitaCambioK

                    vSet = (estadoLogico == 1) * vKeithley;

                    iSet = (estadoLogico == 1) * corrienteObjetivo;

                    writeline(k, sprintf('APPL CH2, %.2f, %.3f', ...
                                         vSet, iSet));

                end


                estadoPrevioSOH = estadoAnterior;

                estadoAnterior = estadoLogico;


                % ====================================================
                % DETECCIÓN DE CICLO COMPLETO PARA SOH
                % ====================================================
                
                if estadoPrevioSOH == 0 && estadoLogico == 1
                
                    cycle_count = cycle_count + 1;
                
                    fprintf('\n=== CICLO COMPLETADO #%d ===\n', cycle_count);
                
                    if length(cycle_V) > 20
                
                        % ====================================================
                        % FEATURES
                        % ====================================================
                
                        idx_dis = find(cycle_I > 0.01);
                        idx_chg = find(cycle_I < -0.01);
                
                        feat = zeros(1,11);
                
                        % ---------------- DESCARGA ----------------
                        if length(idx_dis) > 5
                
                            V_dis = cycle_V(idx_dis);
                            I_dis = cycle_I(idx_dis);
                            S_dis = cycle_SOC(idx_dis);
                
                            feat(1) = mean(V_dis);
                            feat(2) = min(V_dis);
                            feat(3) = max(V_dis) - min(V_dis);
                
                            t_dis = (0:length(V_dis)-1);
                
                            if length(V_dis) > 2
                                p = polyfit(t_dis/max(t_dis), V_dis, 1);
                                feat(4) = p(1);
                            end
                
                            feat(5) = sum(abs(I_dis)) * dt / 3600;
                
                            feat(6) = mean(S_dis);
                
                            feat(7) = max(S_dis) - min(S_dis);
                
                            feat(8) = mean(I_dis);
                
                        end
                
                        % ---------------- CARGA ----------------
                        if length(idx_chg) > 5
                
                            V_chg = cycle_V(idx_chg);
                            I_chg = cycle_I(idx_chg);
                
                            feat(9)  = mean(V_chg);
                            feat(10) = sum(abs(I_chg)) * dt / 3600;
                
                        end
                
                        feat(11) = min(cycle_count / 5000, 1);
                
                        % ====================================================
                        % NORMALIZACIÓN
                        % ====================================================
                
                        feat_norm = (feat - feat_min) ./ feat_range;
                
                        % ====================================================
                        % ACTUALIZAR VENTANA
                        % ====================================================
                
                        if isempty(feature_window)
                
                            feature_window = repmat(feat_norm, W, 1);
                
                        else
                
                            feature_window = [feature_window; feat_norm];
                
                            if size(feature_window,1) > W
                                feature_window(1,:) = [];
                            end
                
                        end
                
                        % ====================================================
                        % PREDICCIÓN LSTM
                        % ====================================================
                
                        if size(feature_window,1) >= W
                
                            entrada = feature_window';
                
                            SOH_norm = predict(net, {entrada}, ...
                                               'MiniBatchSize', 1);
                
                            SOH = double(SOH_norm) * Y_std + Y_mean;
                
                            SOH = max(0.7, min(1.0, SOH));
                
                            SOH_percent = SOH * 100;
                
                            fprintf('SOH estimado: %.2f %%\n', SOH_percent);
                
                        end
                
                    end
                
                    % ====================================================
                    % RESETEAR BUFFERS
                    % ====================================================
                
                    cycle_V = [];
                    cycle_I = [];
                    cycle_SOC = [];
                
                end


                % ====================================================
                % TEMPERATURAS
                % ====================================================

                tTotal = zeros(1, 8);

                for idxT = 4:11

                    subPart = strsplit(partes{idxT}, ':');

                    if length(subPart) == 2

                        idSen = char(subPart{1});

                        if isKey(mapeo, idSen)

                            tTotal(mapeo(idSen)) = ...
                                str2double(subPart{2});

                        end

                    end

                end

                tMax = max(tTotal);

                grad = tMax - min(tTotal(tTotal>0));

                % ====================================================
                % BK
                % ====================================================

                if mod(contador, 3) == 0

                    flush(bk);

                    write(bk, cmdQuery, "uint8");

                    pause(0.1);

                    if bk.NumBytesAvailable >= 26

                        raw = read(bk, bk.NumBytesAvailable, "uint8");

                        idx = find(raw == 170, 1, 'last');

                        if ~isempty(idx) && (length(raw) >= idx + 25)

                            frame = double(raw(idx:idx+25));

                            if calcCS(frame) == frame(26)

                                vBK_last = ...
                                    (frame(4) + ...
                                     frame(5)*256 + ...
                                     frame(6)*65536 + ...
                                     frame(7)*16777216) / 1000;

                                iBK_last = ...
                                    (frame(8) + ...
                                     frame(9)*256 + ...
                                     frame(10)*65536 + ...
                                     frame(11)*16777216) / 10000;

                            end

                        end

                    end

                end

                vBK = vBK_last; 
                iBK = iBK_last;

                % ====================================================
                % LOGS
                % ====================================================

                logSesion = [logSesion; ...
                             now, ...
                             vFilt, ...
                             iFilt, ...
                             vBK, ...
                             iBK, ...
                             SOC_percent, ...
                             SOH_percent, ...
                             tTotal, ...
                             estadoLogico, ...
                             pasoActual, ...
                             corrienteObjetivo];

                dataVArdu = [dataVArdu(2:end), vFilt]; 
                dataVBK   = [dataVBK(2:end), vBK];

                dataIArdu = [dataIArdu(2:end), iFilt]; 
                dataIBK   = [dataIBK(2:end), iBK];

                SOC_hist = [SOC_hist(2:end), SOC_percent];
                SOH_hist = [SOH_hist(2:end), SOH_percent];

                % ====================================================
                % ACTUALIZAR GUI
                % ====================================================

                if length(dataVArdu) == length(tiempo)

                    set(h_heatmap, ...
                        'CData', ...
                        [tTotal(1:4); tTotal(5:8)]);

                    tRest = max(0, ...
                               (estadoLogico==0)*durDescarga(pasoActual) + ...
                               (estadoLogico==1)*durCarga(pasoActual) - ...
                               toc(timerPaso));

                    infoStr = sprintf([ ...
                        'Muestra: %d | ESTADO: %s\n' ...
                        'V_Ardu: %.2f V | V_BK: %.2f V\n' ...
                        'I_Ardu: %.3f A | I_BK: %.3f A\n' ...
                        'SOC: %.2f %% | SOH: %.2f %%\n' ...
                        'T_Máx: %.1f °C | Gradiente: %.1f °C\n' ...
                        'T. Restante: %.1f s | Set BK: %.2f A'], ...
                        contador, ...
                        txtM, ...
                        vFilt, ...
                        vBK, ...
                        iFilt, ...
                        iBK, ...
                        SOC_percent, ...
                        SOH_percent, ...
                        tMax, ...
                        grad, ...
                        tRest, ...
                        corrienteObjetivo);

                    set(h_panel, ...
                        'String', infoStr, ...
                        'ForegroundColor', colorEst);

                    set(p_vArdu, ...
                        'XData', tiempo, ...
                        'YData', dataVArdu);

                    set(p_vBK, ...
                        'XData', tiempo, ...
                        'YData', dataVBK);

                    set(p_iArdu, ...
                        'XData', tiempo, ...
                        'YData', dataIArdu);

                    set(p_iBK, ...
                        'XData', tiempo, ...
                        'YData', dataIBK);

                    set(p_soc, ...
                        'XData', tiempo, ...
                        'YData', SOC_hist);

                    set(p_soh, ...
                        'XData', tiempo, ...
                        'YData', SOH_hist);

                end
                
                if mod(contador, 50) == 0

                    save(['AUTO_SAVE_SOC_SOH_' timestampSesion '.mat'], ...
                         'logSesion');

                end

                drawnow limitrate;

                contador = contador + 1;

            end

        end

        pause(0.01);

    end

catch ME

    save(['FINAL_LOG_' timestampSesion '.mat'], ...
         'logSesion');

    fprintf('\nError: %s en línea %d\n', ...
            ME.message, ...
            ME.stack(1).line);

end

delete(serialportfind);