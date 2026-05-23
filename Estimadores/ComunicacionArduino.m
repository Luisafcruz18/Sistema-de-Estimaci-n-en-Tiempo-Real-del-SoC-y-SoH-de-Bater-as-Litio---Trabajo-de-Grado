% --- GEMELO DIGITAL ALMAGUER: MONITOREO + FILTRADO + HISTORIAL ---
clear all; clc;
if ~isempty(serialportfind), delete(serialportfind); end

% --- CONFIGURACIÓN ---
puertoArdu = "COM4"; puertoBK = "COM9"; baudios = 9600;

% --- MAPEO FÍSICO ---
mapeo = containers.Map();
mapeo('2873714600000096') = 8; mapeo('2846CB4400000065') = 1; 
mapeo('28D602450000008A') = 2; mapeo('28D4B6440000003B') = 3; 
mapeo('28B67B460000005F') = 7; mapeo('2800174500000052') = 6; 
mapeo('28DDCB440000002C') = 5; mapeo('28CD964600000009') = 4; 

% --- VENTANAS DE VISUALIZACIÓN ---
fig1 = figure('Name', 'Gemelo Digital - Estado de Batería', 'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 400, 560, 450]);
subplot(2,1,1); h_heatmap = imagesc(zeros(2, 4)); colorbar; colormap('parula'); 
title('Mapa de Calor del Banco de Baterías (°C)'); xticks(1:4); yticks(1:2); caxis([20 45]); grid on;
subplot(2,1,2); axis off; h_text = text(0.05, 0.5, 'Sincronizando...', 'FontSize', 11, 'FontName', 'Consolas');

fig2 = figure('Name', 'Análisis Eléctrico', 'NumberTitle', 'off', 'Color', 'w', 'Position', [670, 400, 560, 420]);
axV = subplot(2,1,1); hold on; grid on;
p_vArdu = plot(NaN, NaN, 'r', 'LineWidth', 1.5, 'DisplayName', 'V Ardu (Filt)'); 
p_vBK   = plot(NaN, NaN, 'b--', 'LineWidth', 1.5, 'DisplayName', 'V BK');
legend('show'); title('Voltajes (V)');
axI = subplot(2,1,2); hold on; grid on;
p_iArdu = plot(NaN, NaN, 'm', 'LineWidth', 1.5, 'DisplayName', 'I Ardu (Filt)'); 
p_iBK   = plot(NaN, NaN, 'k--', 'LineWidth', 1.5, 'DisplayName', 'I BK');
legend('show'); title('Corrientes (A)'); xlabel('Tiempo (Muestras)');

% --- VARIABLES DE CONTROL Y FILTRADO ---
maxPuntos = 50;
dataVArdu = NaN(1, maxPuntos); dataVBK = NaN(1, maxPuntos);
dataIArdu = NaN(1, maxPuntos); dataIBK = NaN(1, maxPuntos);
tiempo = 1:maxPuntos;
estadoAnterior = -1; 
txtEstado = 'Iniciando...';
colorEstado = [0 0 0];

% Filtro Paso Bajo
alpha = 0.15;
vFilt = 0; iFilt = 0;

% --- HISTORIAL DEL GEMELO DIGITAL (CORREGIDO) ---
logSesion = []; 
numCicloTotal = 1; % Contador correlativo para no sobrescribir
timestampSesion = datestr(now, 'yyyy-mm-dd_HHMM');

% Función Checksum BK
calcCS = @(msg) mod(sum(msg(1:25)), 256);

try
    s = serialport(puertoArdu, baudios, "Timeout", 5); configureTerminator(s, "LF");
    bk = serialport(puertoBK, baudios, "Timeout", 0.5); 
    
    % Modo Remoto BK
    cmdRemote = uint8([170, 0, 32, 1, zeros(1, 21), 0]);
    cmdRemote(26) = calcCS(cmdRemote);
    write(bk, cmdRemote, "uint8"); pause(0.1);
    cmdQuery = uint8([170, 0, 95, zeros(1, 22), 9]);
    contador = 1;

    while ishandle(fig1) && ishandle(fig2)
        if s.NumBytesAvailable > 0
            datosRaw = readline(s);
            partes = strsplit(strtrim(datosRaw), ',');
            
            if length(partes) >= 11
                % 1. LECTURA Y FILTRADO
                vRaw = str2double(partes(1)) * 5.0; 
                iRaw = ((str2double(partes(2)) - 2.5) / 0.066) - 0.190;
                estadoControl = str2double(partes(3)); 
                
                if contador == 1
                    vFilt = vRaw; iFilt = iRaw;
                else
                    vFilt = (1 - alpha) * vFilt + alpha * vRaw;
                    iFilt = (1 - alpha) * iFilt + alpha * iRaw;
                end

                % 2. LOGICA DE CONTROL BK Y GUARDADO DE DATOS
                if estadoControl ~= estadoAnterior
                    % --- GUARDAR CICLO TERMINADO (SIN SOBREESCRITURA) ---
                    if ~isempty(logSesion)
                        tipoCiclo = 'Descarga';
                        if estadoAnterior == 1, tipoCiclo = 'Carga'; end
                        
                        nombreArchivo = sprintf('Gemelo_Data_%s_Num%d_%s.mat', ...
                                                timestampSesion, numCicloTotal, tipoCiclo);
                        save(nombreArchivo, 'logSesion');
                        fprintf('>>> Datos guardados: %s\n', nombreArchivo);
                        
                        logSesion = []; % Limpiar para el siguiente ciclo
                        numCicloTotal = numCicloTotal + 1; % Incrementar contador
                    end

                    if estadoControl == 0 % DESCARGA
                        cmdSetI = uint8([170, 0, 42, 192, 93, 0, 0, zeros(1, 18), 0]); % 2.4A
                        cmdSetI(26) = calcCS(cmdSetI);
                        write(bk, cmdSetI, "uint8"); pause(0.1);
                        cmdOn = uint8([170, 0, 33, 1, zeros(1, 21), 0]);
                        cmdOn(26) = calcCS(cmdOn);
                        write(bk, cmdOn, "uint8");
                        txtEstado = 'DESCARGANDO (BK 2.4A)'; colorEstado = [0.8, 0, 0];
                    else % CARGA
                        cmdSetI = uint8([170, 0, 42, 0, 0, 0, 0, zeros(1, 18), 0]); % 0A
                        cmdSetI(26) = calcCS(cmdSetI);
                        write(bk, cmdSetI, "uint8"); pause(0.1);
                        cmdOff = uint8([170, 0, 33, 0, zeros(1, 21), 0]);
                        cmdOff(26) = calcCS(cmdOff);
                        write(bk, cmdOff, "uint8");
                        txtEstado = 'CARGANDO (BK 0A)'; colorEstado = [0, 0.5, 0];
                    end
                    estadoAnterior = estadoControl;
                end

                % 3. LECTURA BK
                write(bk, cmdQuery, "uint8"); pause(0.12); vBK = 0; iBK = 0;
                if bk.NumBytesAvailable >= 26
                    raw = read(bk, bk.NumBytesAvailable, "uint8");
                    idx = find(raw == 170, 1, 'last');
                    if ~isempty(idx) && (length(raw) >= idx + 25)
                        t = double(raw(idx:idx+25));
                        vBK = (t(4) + t(5)*256 + t(6)*65536 + t(7)*16777216) / 1000;
                        iBK = (t(8) + t(9)*256 + t(10)*65536 + t(11)*16777216) / 10000;
                    end
                end
                
                % 4. PROCESAR TEMPERATURAS
                tTotal = zeros(1, 8);
                for k = 4:11
                    sub = strsplit(partes{k}, ':');
                    if length(sub) == 2
                        id = char(sub{1}); valT = str2double(sub{2});
                        if isKey(mapeo, id), tTotal(mapeo(id)) = valT; end
                    end
                end

                % 5. ALMACENAR EN LOG (Para el Gemelo)
                logSesion = [logSesion; now, vFilt, iFilt, vBK, iBK, tTotal, estadoControl];

                % 6. ACTUALIZAR INTERFAZ
                dataVArdu = [dataVArdu(2:end), vFilt]; dataVBK = [dataVBK(2:end), vBK];
                dataIArdu = [dataIArdu(2:end), iFilt]; dataIBK = [dataIBK(2:end), iBK];
                
                if length(dataVArdu) == length(tiempo)
                    set(h_heatmap, 'CData', [tTotal(1:4); tTotal(5:8)]);
                    infoStr = sprintf(['Muestra [%d] | %s\n' ...
                                       '------------------------------------------\n' ...
                                       'ARDUINO (F) -> V: %.2f V | I: %.3f A\n' ...
                                       'BK LOAD     -> V: %.3f V | I: %.4f A\n' ...
                                       '------------------------------------------\n' ...
                                       'T. Máx: %.2f °C | Gradiente: %.1f °C'], ...
                                       contador, txtEstado, vFilt, iFilt, vBK, iBK, max(tTotal), max(tTotal)-min(tTotal(tTotal>0)));
                    set(h_text, 'String', infoStr, 'Color', colorEstado);
                    
                    set(p_vArdu, 'XData', tiempo, 'YData', dataVArdu); set(p_vBK, 'XData', tiempo, 'YData', dataVBK);
                    set(p_iArdu, 'XData', tiempo, 'YData', dataIArdu); set(p_iBK, 'XData', tiempo, 'YData', dataIBK);
                end
                drawnow limitrate; contador = contador + 1;
            end
        end
        pause(0.01); 
    end
catch ME
    nombreError = sprintf('ERROR_LOG_%s_Num%d.mat', timestampSesion, numCicloTotal);
    save(nombreError, 'logSesion');
    fprintf('\nError: %s en línea %d. Datos salvados en %s\n', ME.message, ME.stack(1).line, nombreError);
end
delete(serialportfind);