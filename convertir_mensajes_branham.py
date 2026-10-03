#!/usr/bin/env python3
"""
convertir_mensajes_branham.py

Convierte los archivos JSON del repositorio Mensajes.git (mensajes en español)
al formato que espera la app iOS SwiftUI:

{
  "sermons": [
    {
      "id": "47-0412",
      "title": "Fe Es La Sustancia",
      "meta": { "date": "12 de Abril de 1947", "location": "Oakland, California", "building": null },
      "date": "12 de Abril de 1947",
      "location": "Oakland, California",
      "paragraphs": [
        { "number": 1, "text": "..." },
        { "number": 2, "text": "..." }
      ]
    }
  ]
}

USO:
    python3 convertir_mensajes_branham.py /ruta/a/Mensajes/ES bro_branham_sermons.json

CÓMO FUNCIONA:
1. Recorre todos los archivos JSON en el directorio ES del repositorio Mensajes
2. Extrae el texto de los bloques (blocks)
3. Captura metadatos como fecha y ubicación
4. Genera párrafos numerados a partir del texto
5. Crea un archivo JSON compatible con la app iOS
"""

import sys
import os
import re
import json
from pathlib import Path


def extraer_id_de_nombre(nombre_archivo):
    """
    Extrae el ID (ej: 47-0412) del nombre del archivo.
    Nombre típico: "47-0412 - Fe Es La Sustancia.json"
    """
    match = re.match(r"(\d{2}-\d{4}[A-Za-z]?)", nombre_archivo)
    if match:
        return match.group(1)
    return nombre_archivo.replace(".json", "")


def extraer_titulo_de_nombre(nombre_archivo):
    """
    Extrae el título del nombre del archivo.
    Nombre típico: "47-0412 - Fe Es La Sustancia.json"
    """
    match = re.search(r"(\d{2}-\d{4}[A-Za-z]?)\s*-\s*(.+)\.json", nombre_archivo)
    if match:
        return match.group(2).strip()
    return nombre_archivo.replace(".json", "")


def procesar_json_mensaje(ruta_archivo):
    """
    Lee un archivo JSON de mensaje y extrae:
    - Título
    - Fecha
    - Ubicación
    - Texto de todos los párrafos
    """
    try:
        with open(ruta_archivo, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"  ⚠️  Error leyendo JSON: {e}")
        return None

    nombre_archivo = os.path.basename(ruta_archivo)
    sermon_id = extraer_id_de_nombre(nombre_archivo)
    titulo = extraer_titulo_de_nombre(nombre_archivo)
    
    fecha = None
    ubicacion = None
    texto_completo = []
    
    # Recorrer las páginas
    if "pages" in data and isinstance(data["pages"], list):
        for pagina in data["pages"]:
            if "blocks" in pagina and isinstance(pagina["blocks"], list):
                for bloque in pagina["blocks"]:
                    if "text" in bloque:
                        texto = bloque["text"].strip()
                        
                        # Detectar fecha (formato: "12 de Abril de 1947")
                        if re.search(r"\d{1,2}\s+de\s+\w+\s+de\s+\d{4}", texto) and not fecha:
                            fecha = texto
                        # Detectar ubicación (palabras clave: ciudad, región, país)
                        elif any(loc in texto for loc in ["California", "Indiana", "Texas", "Nueva York", 
                                                           "Jeffersonville", "Phoenix", "Tucson"]) and not ubicacion:
                            ubicacion = texto
                        # Agregar texto si no es vacío
                        elif texto and len(texto) > 5:
                            texto_completo.append(texto)
    
    # Si no se detectó ubicación, intentar extraerla del nombre del archivo
    if not ubicacion and "E.U.A" in nombre_archivo:
        ubicacion = "Estados Unidos"
    
    # Dividir en párrafos
    parrafos = []
    numero = 1
    for texto in texto_completo:
        # Limpiar espacios múltiples
        texto = re.sub(r'\s+', ' ', texto).strip()
        if len(texto) > 10:  # Solo párrafos significativos
            parrafos.append({
                "number": numero,
                "text": texto
            })
            numero += 1
    
    if not parrafos:
        print(f"  ⚠️  No se extrajeron párrafos")
        return None
    
    return {
        "id": sermon_id,
        "title": titulo,
        "meta": {
            "date": fecha,
            "location": ubicacion,
            "building": None
        },
        "date": fecha,
        "location": ubicacion,
        "paragraphs": parrafos
    }


def main():
    if len(sys.argv) < 2:
        print("USO: python3 convertir_mensajes_branham.py /ruta/a/Mensajes/ES [archivo_salida.json]")
        print("\nEjemplo:")
        print("  python3 convertir_mensajes_branham.py ./Mensajes/ES bro_branham_sermons.json")
        sys.exit(1)
    
    carpeta_entrada = sys.argv[1]
    archivo_salida = sys.argv[2] if len(sys.argv) > 2 else "bro_branham_sermons.json"
    
    if not os.path.isdir(carpeta_entrada):
        print(f"Error: '{carpeta_entrada}' no es una carpeta válida.")
        sys.exit(1)
    
    # Buscar todos los archivos JSON en subdirectorios (por año)
    sermon_files = []
    for root, dirs, files in os.walk(carpeta_entrada):
        for file in files:
            if file.endswith('.json'):
                sermon_files.append(os.path.join(root, file))
    
    print(f"📂 Encontrados {len(sermon_files)} archivos JSON")
    print(f"🔄 Procesando...\n")
    
    sermones = []
    for ruta in sorted(sermon_files)[:200]:  # Limitar a 200 por rendimiento
        nombre = os.path.basename(ruta)
        print(f"  Procesando: {nombre}")
        
        resultado = procesar_json_mensaje(ruta)
        if resultado:
            sermones.append(resultado)
            print(f"    ✓ id='{resultado['id']}' title='{resultado['title']}' ({len(resultado['paragraphs'])} párrafos)")
        else:
            print(f"    ✗ Saltado")
    
    # Crear el envelope
    envelope = {"sermons": sermones}
    
    # Guardar el archivo JSON
    try:
        with open(archivo_salida, 'w', encoding='utf-8') as f:
            json.dump(envelope, f, ensure_ascii=False, indent=2)
        
        print(f"\n✅ ¡LISTO! Se guardaron {len(sermones)} mensaje(s) en '{archivo_salida}'")
        print(f"📊 Tamaño: {os.path.getsize(archivo_salida) / 1024 / 1024:.2f} MB")
        print(f"\n📋 Próximos pasos:")
        print(f"   1. Copia el archivo '{archivo_salida}' a tu proyecto Xcode")
        print(f"   2. En Xcode: Add Files to Project > {archivo_salida}")
        print(f"   3. Asegúrate de que esté en Target Membership: mensajedeVGR")
        print(f"   4. Renómbralo a 'bro_branham_sermons.json' si es necesario")
        print(f"   5. Ejecuta la app (eliminando la versión anterior si es necesario)")
        
    except Exception as e:
        print(f"❌ Error guardando archivo: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
