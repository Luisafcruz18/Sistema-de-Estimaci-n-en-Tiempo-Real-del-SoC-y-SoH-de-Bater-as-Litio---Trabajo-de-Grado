# Sistema-de-Estimaci-n-en-Tiempo-Real-del-SoC-y-SoH-de-Bater-as-Litio---Trabajo-de-Grado
Este repositorio contiene los archivos desarrollados para el trabajo de grado **"Desarrollo de un Sistema Integrado de Medición y Estimación en Tiempo Real del Estado de Carga (SoC) y Salud (SoH) de Baterías Ion-Litio"**.

El proyecto tiene como objetivo desarrollar e implementar algoritmos para la estimación del **Estado de Carga (SoC)** y el **Estado de Salud (SoH)** de baterías ion-litio, a partir de variables eléctricas medidas experimentalmente, principalmente voltaje y corriente. Para ello, se emplean modelos eléctricos equivalentes, métodos de estimación como Coulomb Counting y filtros de Kalman, además de herramientas de simulación y análisis mediante un gemelo digital.

## Contenido del repositorio

- `Dataset/`: contiene los datos experimentales y/o simulados utilizados para el entrenamiento, validación y comparación de los algoritmos de estimación. Estos datos incluyen registros asociados a ciclos de carga, descarga, voltaje, corriente, temperatura y variables relacionadas con el comportamiento de la batería.

- `Estimadores/`: contiene los scripts y modelos desarrollados para la estimación del SoC y SoH. En esta carpeta se incluyen los algoritmos de procesamiento de datos, estimadores basados en Coulomb Counting, filtros de Kalman, modelos eléctricos equivalentes y rutinas asociadas al análisis del comportamiento de la batería.

## Descripción general del proyecto

El sistema desarrollado busca estimar en tiempo real parámetros internos de baterías de ion-litio que no pueden medirse directamente, como el Estado de Carga y el Estado de Salud. Para esto, se parte de mediciones externas como voltaje, corriente y temperatura, las cuales son procesadas mediante algoritmos implementados en software.

La estimación del SoC permite conocer la energía disponible en la batería durante su operación, mientras que la estimación del SoH permite evaluar el nivel de degradación y vida útil remanente. Estos parámetros son fundamentales en aplicaciones como movilidad eléctrica, sistemas de almacenamiento energético, microrredes y dispositivos alimentados por baterías.

## Metodología general

El desarrollo del proyecto se estructuró en las siguientes etapas:

1. Adquisición de datos experimentales de la batería.
2. Procesamiento y limpieza de las señales medidas.
3. Implementación de modelos eléctricos equivalentes de la batería.
4. Estimación del SoC mediante métodos clásicos y filtros de Kalman.
5. Estimación del SoH a partir del comportamiento de degradación.
6. Validación de los resultados mediante datos experimentales y simulados.
7. Comparación entre métodos de estimación.

## Algoritmos y modelos implementados

Dentro del repositorio se consideran los siguientes enfoques:

- **Coulomb Counting**: método basado en la integración de corriente para estimar el SoC.
- **Filtro de Kalman**: estimador utilizado para corregir errores acumulados y mejorar la robustez frente al ruido de medición.
- **Modelo ECM**: modelo eléctrico equivalente empleado para representar el comportamiento dinámico de la batería.
- **Gemelo digital**: representación virtual del sistema físico utilizada para simular y validar el comportamiento de la batería.
- **Estimación de SoH**: análisis del estado de salud de la batería a partir de datos de ciclos y degradación.

## Software requerido

Para ejecutar y analizar los archivos del repositorio se recomienda contar con:

- MATLAB
- Arduino IDE
- Librerías de análisis numérico y procesamiento de datos, según el lenguaje utilizado
- Controladores necesarios para comunicación serial con Arduino y equipos de adquisición

## Hardware asociado al proyecto

El sistema experimental documentado utiliza los siguientes elementos principales:

- Baterías de ion-litio
- Arduino Mega
- Sensor de corriente ACS712
- Sensor de voltaje FZ0430 o divisor resistivo
- Sensores de temperatura DS18B20
- Carga electrónica BK Precision
- Fuente de alimentación regulada
- Circuito de conmutación y protección

## Uso general

1. Descargar o clonar el repositorio.
