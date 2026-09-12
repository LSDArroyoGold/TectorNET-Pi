"""
Arma el nombre de archivo y la carpeta de destino para una deteccion,
usando exactamente la misma convencion que BirdNET-Pi (extract_detection()
en scripts/utils/reporting.py) para que el motor nuevo sea un reemplazo
directo -- todo lo que ya cuenta/sincroniza detecciones parseando ese
patron (cierre_amanecer.sh, cierre_atardecer.sh, sincronizar_detecciones.sh)
sigue funcionando sin tocar nada.
"""
import os


def nombre_archivo(resultado, timestamp_inicio, extension='mp3'):
    r"""resultado: el dict que devuelve Clasificador.decidir_confianza_racha
    (necesita 'especie_comun', 'confianza' y 'confianza_baja'). timestamp_inicio:
    datetime real del inicio del evento (viene de AcumuladorEventos, propagado
    desde procesar_bloque(..., timestamp_bloque=...)).

    Devuelve (nombre_archivo, carpeta_relativa), ej:
    ('Rufous_Hornero-92-2026-08-23-tectornet-09:52:26.mp3',
     'By_Date/2026-08-23/Rufous_Hornero')
    o, si 'confianza_baja' (no se postea a BirdWeather -- ver motor.py):
    ('Vulpes_vulpes-79-2026-08-29-tectornet-19:25:20-nbw.mp3',
     'By_Date/2026-08-29/Vulpes_vulpes')

    El marcador es "tectornet-" desde el 12/9/2026 (antes "birdnet-", que
    hace rato no describia al motor). Los contadores de los cierres de
    LSD-Tector1.1 y 2.1, resumir_dia.py y el servidor de Tector Hub aceptan
    los dos: grep -oP "(?:birdnet|tectornet)-\K[0-9]{2}:[0-9]{2}". Lo que ya
    esta en Drive con el nombre viejo se sigue contando igual. OJO con
    LSD-Tector2.0, que solo acepta "birdnet-": en un equipo con esa version
    "Detecciones subidas" queda en 0 (cosmetico; los archivos suben igual)
    hasta migrarlo a 2.1.

    La hora usa ":" (no "_") para que esa regex de conteo (heredada de
    BirdNET-Pi) siga funcionando -- extrae HH:MM
    igual aunque el nombre tenga tambien los segundos despues (bug real
    encontrado el 25/08: con "_" la regex nunca matcheaba, "Detecciones
    subidas" quedaba en 0 aunque el motor si estuviera detectando).

    Sufijo "-nbw" agregado el 29/08/2026 (a pedido de Diego): distingue en
    Drive, sin necesitar SSH ni mirar motor.log, las detecciones que NO se
    postearon a BirdWeather (confianza_baja=True -- hoy, con TectorNet,
    significa que BirdSet no confirmo la especie que propuso Perch2) de las
    que si. Va DESPUES de la hora y ANTES de la extension a proposito -- la
    regex de conteo de arriba solo mira los 5 caracteres justo despues del
    marcador, nunca llega a leer el sufijo, asi que sigue contando TODO
    archivo *.mp3 por igual (con o sin "-nbw"). cierre_amanecer.sh/
    cierre_atardecer.sh de LSD-Tector1.1 (los que corren en tector1) se
    actualizaron aparte para reportar el desglose confirmadas/total -- ver
    esos archivos.
    """
    if timestamp_inicio is None:
        raise ValueError(
            'timestamp_inicio_evento es None -- procesar_bloque() se llamo '
            'sin timestamp_bloque. En produccion siempre hace falta pasarlo '
            '(la hora real de inicio de cada bloque de grabacion).'
        )

    nombre_comun_seguro = resultado['especie_comun'].replace("'", "").replace(' ', '_')
    confianza_pct = round(resultado['confianza'] * 100)
    fecha = timestamp_inicio.strftime('%Y-%m-%d')
    hora = timestamp_inicio.strftime('%H:%M:%S')
    sufijo = '-nbw' if resultado.get('confianza_baja') else ''

    # "tectornet" y no "birdnet": hace rato que el motor no es BirdNET. Los
    # scripts que cuentan detecciones (LSD-Tector1.1 y 2.1) y el servidor de
    # Tector Hub aceptan los dos nombres, asi que lo viejo que ya esta en
    # Drive se sigue contando bien. Cambiado el 12/9/2026.
    nombre = f'{nombre_comun_seguro}-{confianza_pct}-{fecha}-tectornet-{hora}{sufijo}.{extension}'
    carpeta_relativa = os.path.join('By_Date', fecha, nombre_comun_seguro)
    return nombre, carpeta_relativa
