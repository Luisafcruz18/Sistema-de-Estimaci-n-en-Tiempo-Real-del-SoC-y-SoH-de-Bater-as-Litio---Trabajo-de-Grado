% --- LECTOR DEFINITIVO BK 8502 (MENTE FRESCA) ---
clear all; clc;
delete(instrfindall);

bk = serialport("COM9", 9600, "Timeout", 1);
flush(bk);

% Enviamos Query de Estado (0x5F)
tramaQuery = uint8([170, 0, 95, zeros(1, 22), 9]);
write(bk, tramaQuery, "uint8");
pause(0.3);

if bk.NumBytesAvailable >= 26
    raw = read(bk, bk.NumBytesAvailable, "uint8");
    
    % Buscamos el inicio 170
    idx = find(raw == 170, 1, 'last'); % Usamos el último para tener el más fresco
    
    if length(raw) >= idx + 25
        trama = raw(idx : idx+25);
        
        % VOLTAJE: Bytes 4, 5, 6, 7
        % v_raw = byte4 + byte5*256 + byte6*65536 + byte7*16777216
        v_bytes = double(trama(4:7));
        voltaje = (v_bytes(1) + v_bytes(2)*256 + v_bytes(3)*65536 + v_bytes(4)*16777216) / 1000;
        
        % CORRIENTE: Bytes 8, 9, 10, 11
        i_bytes = double(trama(8:11));
        corriente = (i_bytes(1) + i_bytes(2)*256 + i_bytes(3)*65536 + i_bytes(4)*16777216) / 10000;
        
        fprintf('====================================\n');
        fprintf('   ESTADO DE LA CARGA BK 8502      \n');
        fprintf('====================================\n');
        fprintf('   Voltaje:   %.3f V\n', voltaje);
        fprintf('   Corriente: %.4f A\n', corriente);
        fprintf('====================================\n');
    end
else
    fprintf('No hay suficientes bytes en el buffer.\n');
end