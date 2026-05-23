#include <OneWire.h>
#include <DallasTemperature.h>

// --- CONFIGURACIÓN ---
const int ONE_WIRE_BUS = 2;
const int PIN_CARGA = 52;    // MOSFET Carga
const int PIN_DESCARGA = 53; // MOSFET Descarga

OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);

// Umbrales de seguridad (Histéresis)
float umbralDescarga = 8.5;
float umbralCargaCompleta = 12.5;
bool modoCarga = false; // Estado inicial: Descarga

void setup() {
  Serial.begin(9600);
  sensors.begin();
  
  // Configuración de pines de control
  pinMode(PIN_CARGA, OUTPUT);
  pinMode(PIN_DESCARGA, OUTPUT);
  
  // Estado inicial SEGURO: Todo apagado
  digitalWrite(PIN_CARGA, LOW);
  digitalWrite(PIN_DESCARGA, LOW);
}

void loop() {
  // 1. LECTURA DE SENSORES ELÉCTRICOS
  float rawV = analogRead(A0);
  float rawI = analogRead(A1);
  
  float vVoltaje = rawV * 5.0 / 1023.0;
  float vCorriente = rawI * 5.0 / 1023.0;
  
  // Cálculo de voltaje real para la toma de decisiones interna
  // Usamos tu factor de división 5.0 que definimos en Matlab
  float voltajeReal = vVoltaje * 5.0; 

  // 2. LÓGICA DE CONTROL (PROTECCIÓN DE HARDWARE)
  if (voltajeReal < umbralDescarga) {
    modoCarga = true;
  } else if (voltajeReal > umbralCargaCompleta) {
    modoCarga = false;
  }

  // APLICACIÓN DE ESTADOS (BLOQUEO DE CORTO CIRCUITO)
  if (modoCarga) {
    digitalWrite(PIN_DESCARGA, LOW); // APAGAR descarga primero (CRÍTICO)
    delay(50);                       
    digitalWrite(PIN_CARGA, HIGH);   // Activar carga
  } else {
    digitalWrite(PIN_CARGA, LOW);    // APAGAR carga primero (CRÍTICO)
    delay(50);                      
    digitalWrite(PIN_DESCARGA, HIGH);// Activar descarga
  }

  // 3. ENVÍO DE DATOS A MATLAB
  sensors.requestTemperatures();
  
  Serial.print(vVoltaje, 3); Serial.print(",");
  Serial.print(vCorriente, 3); Serial.print(",");
  
  // Enviar estado actual para que Matlab lo sepa (0: Descarga, 1: Carga)
  Serial.print(modoCarga); Serial.print(",");

  const char* IDs[] = {
    "28B67B460000005F", "28CD964600000009", "28DDCB440000002C",
    "2846CB4400000065", "28D602450000008A", "2873714600000096",
    "28D4B6440000003B", "2800174500000052"
  };

  for (int i = 0; i < 8; i++) {
    float temp = sensors.getTempCByIndex(i);
    if (temp < -50 || temp > 150) temp = 0.00; 
    Serial.print(IDs[i]);
    Serial.print(":");
    Serial.print(temp, 2);
    if (i < 7) Serial.print(","); 
  }

  Serial.println(); 
  delay(1000);
}