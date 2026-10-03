#!/usr/bin/env python3
"""
convertir_sermones_v2.py

Convierte una carpeta de archivos PDF y/o Word (.docx) con transcripciones
de sermones en español a un único archivo JSON con el formato REAL que
espera tu app (BroSermonCatalogEntry / BroSermonCatalogEnvelope):

{
  "sermons": [
    {
      "id": "50-0405",
      "title": "Expectación",
      "meta": { "date": null, "location": "Nueva York, NY", "building": null },
      "date": null,
      "location": "Nueva York, NY",
      "paragraphs": [
        { "number": 1, "text": "..." },
        { "number": 2, "text": "..." }
      ]
    }
  ]
}

USO:
    python3 convertir_sermones_v2.py /ruta/a/carpeta_con_pdfs_o_docx bro_branham_sermons_es.json

REQUISITOS (instalar una sola vez):
    pip install pypdf python-docx --break-system-packages

CÓMO FUNCIONA:
1. Recorre todos los .pdf y .docx de la carpeta indicada.
2. Extrae el texto completo de cada archivo.
3. Divide el texto en párrafos (separados por línea en blanco) y les
   asigna número consecutivo -> eso llena "paragraphs".
4. Intenta adivinar el "id" (código, ej. 50-0405) y el "title" a partir
   del nombre del archivo o de las primeras líneas del documento.
5. Deja "location", "date" y "building" vacíos para que los completes a
   mano si no vienen en un formato detectable.

NOTA IMPORTANTE:
Este script NO inventa ni traduce contenido. Solo extrae y reorganiza
texto de los archivos que tú ya descargaste (por ejemplo desde
branham.org), para asegurar que uses siempre la traducción oficial.
"""

import sys
import os
import re
import json
import argparse

try:
    from pypdf import PdfReader
except ImportError:
    PdfReader = None

try:
    import docx  # python-docx
except ImportError:
    docx = None


CODE_PATTERN = re.compile(r"\b(\d{2}-\d{4}[A-Za-z]?)\b")


def extraer_texto_pdf(ruta):
    if PdfReader is None:
        raise RuntimeError(
            "Falta la librería pypdf. Instálala con:\n"
            "  pip install pypdf --break-system-packages"
        )
    reader = PdfReader(ruta)
    partes = [page.extract_text() or "" for page in reader.pages]
    return "\n".join(partes).strip()


def extraer_texto_docx(ruta):
    if docx is None:
        raise RuntimeError(
            "Falta la librería python-docx. Instálala con:\n"
            "  pip install python-docx --break-system-packages"
        )
    documento = docx.Document(ruta)
    partes = [p.text for p in documento.paragraphs]
    return "\n".join(partes).strip()


def limpiar_texto(texto):
    texto = re.sub(r"[ \t]+", " ", texto)
    texto = re.sub(r"\n{3,}", "\n\n", texto)
    return texto.strip()


def adivinar_code(nombre_archivo, texto):
    m = CODE_PATTERN.search(nombre_archivo)
    if m:
        return m.group(1)
    primeras_lineas = "\n".join(texto.splitlines()[:5])
    m = CODE_PATTERN.search(primeras_lineas)
    if m:
        return m.group(1)
    return ""


def adivinar_title(nombre_archivo, texto, code):
    base = os.path.splitext(nombre_archivo)[0]
    if code:
        base = base.replace(code, "")
    base = re.sub(r"[_\-]+", " ", base).strip()
    if base:
        return base
    for linea in texto.splitlines():
        linea = linea.strip()
        if linea and not CODE_PATTERN.fullmatch(linea):
            return linea
    return "Sin título"


def dividir_en_parrafos(texto):
    """Divide el texto en párrafos usando líneas en blanco como separador
    y les asigna número consecutivo, tal como espera BroSermonParagraph."""
    crudos = re.split(r"\n\s*\n", texto)
    parrafos = []
    numero = 1
    for bloque in crudos:
        bloque = bloque.strip().replace("\n", " ")
        bloque = re.sub(r"\s+", " ", bloque).strip()
        if not bloque:
            continue
        parrafos.append({"number": numero, "text": bloque})
        numero += 1
    return parrafos


def procesar_archivo(ruta):
    nombre_archivo = os.path.basename(ruta)
    extension = os.path.splitext(ruta)[1].lower()

    if extension == ".pdf":
        texto_crudo = extraer_texto_pdf(ruta)
    elif extension == ".docx":
        texto_crudo = extraer_texto_docx(ruta)
    else:
        return None

    texto = limpiar_texto(texto_crudo)
    code = adivinar_code(nombre_archivo, texto)
    title = adivinar_title(nombre_archivo, texto, code)
    paragraphs = dividir_en_parrafos(texto)

    return {
        "id": code if code else nombre_archivo,
        "title": title,
        "meta": {
            "date": None,        # completar manualmente si se conoce
            "location": None,    # completar manualmente si se conoce
            "building": None,
        },
        "date": None,
        "location": None,
        "paragraphs": paragraphs,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Convierte PDFs/Word de sermones al formato BroSermonCatalogEntry."
    )
    parser.add_argument("carpeta_entrada", help="Carpeta con los .pdf / .docx")
    parser.add_argument("archivo_salida", help="Ruta del JSON de salida, ej. bro_branham_sermons_es.json")
    args = parser.parse_args()

    if not os.path.isdir(args.carpeta_entrada):
        print(f"Error: '{args.carpeta_entrada}' no es una carpeta válida.")
        sys.exit(1)

    sermones = []
    archivos = sorted(os.listdir(args.carpeta_entrada))

    for nombre in archivos:
        ruta = os.path.join(args.carpeta_entrada, nombre)
        if not os.path.isfile(ruta):
            continue
        extension = os.path.splitext(nombre)[1].lower()
        if extension not in (".pdf", ".docx"):
            continue

        print(f"Procesando: {nombre} ...")
        try:
            registro = procesar_archivo(ruta)
            if registro:
                sermones.append(registro)
                print(f"  -> id='{registro['id']}' title='{registro['title']}' "
                      f"({len(registro['paragraphs'])} párrafos)")
        except Exception as e:
            print(f"  ⚠️  Error procesando {nombre}: {e}")

    envelope = {"sermons": sermones}

    with open(args.archivo_salida, "w", encoding="utf-8") as f:
        json.dump(envelope, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Listo. Se guardaron {len(sermones)} sermón(es) en '{args.archivo_salida}'.")
    print("Revisa 'meta.location', 'meta.date' y 'meta.building': quedaron en null para que los completes a mano.")


if __name__ == "__main__":
    main()
