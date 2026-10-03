import { readFile, mkdir, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import dictionary from "dictionary-es";
import nspell from "nspell";

const require = createRequire(import.meta.url);
const pdfParse = require("pdf-parse");
const spell = nspell(dictionary.aff, dictionary.dic);

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const inputPath = path.resolve(process.argv[2] ?? path.join(root, "83800_spa.pdf"));
const outputPath = path.resolve(process.argv[3] ?? path.join(root, "Resources", "biblia_rv2009.json"));
const dropOpen = "\uE000";
const dropClose = "\uE001";

const books = [
  ["Génesis", 50, "Génesis"], ["Éxodo", 40, "Éxodo"], ["Levítico", 27, "Levítico"],
  ["Números", 36, "Números"], ["Deuteronomio", 34, "Deuteronomio"], ["Josué", 24, "Josué"],
  ["Jueces", 21, "Jueces"], ["Rut", 4, "Rut"], ["1 Samuel", 31, "Samuel"],
  ["2 Samuel", 24, "Samuel"], ["1 Reyes", 22, "Reyes"], ["2 Reyes", 25, "Reyes"],
  ["1 Crónicas", 29, "Crónicas"], ["2 Crónicas", 36, "Crónicas"], ["Esdras", 10, "Esdras"],
  ["Nehemías", 13, "Nehemías"], ["Ester", 10, "Ester"], ["Job", 42, "Job"],
  ["Salmos", 150, "Salmos"], ["Proverbios", 31, "Proverbios"], ["Eclesiastés", 12, "Eclesiastés"],
  ["Cantares", 8, "Cantar de los Cantares"], ["Isaías", 66, "Isaías"], ["Jeremías", 52, "Jeremías"],
  ["Lamentaciones", 5, "Lamentaciones"], ["Ezequiel", 48, "Ezequiel"], ["Daniel", 12, "Daniel"],
  ["Oseas", 14, "Oseas"], ["Joel", 3, "Joel"], ["Amós", 9, "Amós"], ["Abdías", 1, "Abdías"],
  ["Jonás", 4, "Jonás"], ["Miqueas", 7, "Miqueas"], ["Nahúm", 3, "Nahúm"],
  ["Habacuc", 3, "Habacuc"], ["Sofonías", 3, "Sofonías"], ["Hageo", 2, "Hageo"],
  ["Zacarías", 14, "Zacarías"], ["Malaquías", 4, "Malaquías"], ["Mateo", 28, "San Mateo"],
  ["Marcos", 16, "San Marcos"], ["Lucas", 24, "San Lucas"], ["Juan", 21, "San Juan"],
  ["Hechos", 28, "Hechos"], ["Romanos", 16, "Romanos"], ["1 Corintios", 16, "Corintios"],
  ["2 Corintios", 13, "Corintios"], ["Gálatas", 6, "Gálatas"], ["Efesios", 6, "Efesios"],
  ["Filipenses", 4, "Filipenses"], ["Colosenses", 4, "Colosenses"],
  ["1 Tesalonicenses", 5, "Tesalonicenses"], ["2 Tesalonicenses", 3, "Tesalonicenses"],
  ["1 Timoteo", 6, "Timoteo"], ["2 Timoteo", 4, "Timoteo"], ["Tito", 3, "Tito"],
  ["Filemón", 1, "Filemón"], ["Hebreos", 13, "Hebreos"], ["Santiago", 5, "Santiago"],
  ["1 Pedro", 5, "San Pedro Apóstol"], ["2 Pedro", 3, "San Pedro Apóstol"],
  ["1 Juan", 5, "San Juan Apóstol"], ["2 Juan", 1, "San Juan Apóstol"],
  ["3 Juan", 1, "San Juan Apóstol"], ["Judas", 1, "San Judas Apóstol"],
  ["Apocalipsis", 22, "Apocalipsis"],
].map(([name, chapterCount, title]) => ({ name, chapterCount, title, chapters: [] }));

const fold = (value) => String(value ?? "")
  .normalize("NFD")
  .replace(/[\u0300-\u036f]/g, "")
  .replace(/[^\p{L}\p{N}]+/gu, " ")
  .trim()
  .toLocaleUpperCase("es");

const titleBooks = new Map();
for (const [index, book] of books.entries()) {
  const key = fold(book.title);
  titleBooks.set(key, [...(titleBooks.get(key) ?? []), index]);
}

const knownJoinedPairs = new Set([
  "DE+BAJO", "PER+DONADAS", "CUBIER+TOS", "LUMBRE+RAS", "ES+TACIONES", "HERMA+NOS", "HER+MANOS",
  "HER+MANO", "FUE+RON", "CON+FORME", "CON+MIGO", "MALVA+DOS",
  "JUNTA+MENTE", "VER+DAD", "MAN+DADO", "DIJE+RON", "JE+HOVA",
  "HAM+BRE", "DES+DE", "CIERTA+MENTE", "VOL+VERA", "HER+MANA", "PADR+E",
]);
function joinTextItems(items) {
  let text = "";
  for (const item of items) {
    const part = item.text.trim();
    if (!part) continue;
    const previousWord = text.match(/([\p{L}\p{N}]+)[^\p{L}\p{N}]*$/u)?.[1] ?? "";
    const nextWord = part.match(/^[^\p{L}\p{N}]*([\p{L}\p{N}]+)/u)?.[1] ?? "";
    const pair = `${fold(previousWord)}+${fold(nextWord)}`;
    const combined = `${previousWord.toLocaleLowerCase("es")}${nextWord.toLocaleLowerCase("es")}`;
    const brokenWord = knownJoinedPairs.has(pair)
      || (previousWord.length > 1 && nextWord.length > 1
        && spell.correct(combined) && !spell.correct(nextWord));
    text += `${text && !brokenWord ? " " : ""}${part}`;
  }
  return text;
}

const rawPages = [];
let nextTitleIndex = 0;
const source = await readFile(inputPath);
await pdfParse(source, {
  pagerender: async (page) => {
    const content = await page.getTextContent();
    const rows = new Map();
    const dropCaps = [];
    const titleEvents = [];
    const fontCounts = new Map();

    for (const item of content.items) {
      const text = item.str.trim();
      if (!text) continue;

      if (item.height > 180 && text.length > 3) {
        if (fold(text) === "APENDICE") {
          titleEvents.push({
            type: "end",
            column: item.transform[4] < page.view[2] / 2 ? 0 : 1,
            y: Math.round(item.transform[5]),
          });
        }
        const candidates = titleBooks.get(fold(text)) ?? [];
        const titleIndex = candidates.find((index) => index >= nextTitleIndex);
        if (titleIndex !== undefined) {
          titleEvents.push({
            type: "book",
            bookIndex: titleIndex,
            column: item.transform[4] < page.view[2] / 2 ? 0 : 1,
            y: Math.round(item.transform[5]),
          });
          nextTitleIndex = titleIndex + 1;
        }
      }

      const x = item.transform[4];
      const y = Math.round(item.transform[5]);
      const column = x < page.view[2] / 2 ? 0 : 1;
      if (item.height > 300 && /^[A-ZÁÉÍÓÚÜÑ]$/.test(text)) {
        dropCaps.push({ text, x, y, column, height: item.height });
        continue;
      }
      if (item.height <= 90 || item.height >= 140 || y > 560) continue;

      const key = `${column}:${y}`;
      if (!rows.has(key)) rows.set(key, []);
      fontCounts.set(item.fontName, (fontCounts.get(item.fontName) ?? 0) + 1);
      rows.get(key).push({ x, text, fontName: item.fontName });
    }

    const rawRows = [...rows].map(([key, items]) => {
      const [column, y] = key.split(":").map(Number);
      const sorted = items.sort((a, b) => Math.round(a.x) - Math.round(b.x)
        || Number(/^\d{1,3}$/.test(b.text)) - Number(/^\d{1,3}$/.test(a.text)));
      return { column, y, items: sorted };
    });

    const bodyFont = [...fontCounts].sort((a, b) => b[1] - a[1])[0]?.[0];
    rawPages.push({ pageNumber: page.pageNumber, rows: rawRows, dropCaps, titleEvents, bodyFont });
    return "";
  },
});

if (nextTitleIndex !== books.length) {
  throw new Error(`Se identificaron ${nextTitleIndex} de ${books.length} títulos de libros.`);
}

const pages = rawPages.map((page) => {
  const lines = page.rows.flatMap((row) => {
    const bodyItems = row.items.filter((item) => item.fontName === page.bodyFont);
    if (!bodyItems.length) return [];
    return [{ ...row, items: bodyItems, text: joinTextItems(bodyItems) }];
  });

  for (const dropCap of page.dropCaps) {
    let nearest;
    for (const line of lines) {
      if (line.column !== dropCap.column || line.y <= dropCap.y) continue;
      const xDistance = line.items[0].x - dropCap.x;
      const yDistance = line.y - dropCap.y;
      if (xDistance < 0 || xDistance > 50 || yDistance > dropCap.height / 45) continue;
      if (!nearest || yDistance < nearest.yDistance) nearest = { line, yDistance };
    }
    if (nearest) nearest.line.text = `${dropOpen}${dropCap.text}${dropClose}${nearest.line.text}`;
  }

  const events = [];
  let remainingLines = lines;
  for (const titleEvent of page.titleEvents.sort((a, b) => b.y - a.y)) {
    const beforeTitle = remainingLines.filter((line) => line.y > titleEvent.y)
      .sort((a, b) => a.column - b.column || b.y - a.y);
    events.push(...beforeTitle.map((line) => ({ type: "line", ...line })));
    events.push(titleEvent);
    remainingLines = remainingLines.filter((line) => line.y <= titleEvent.y);
  }
  events.push(...remainingLines.sort((a, b) => a.column - b.column || b.y - a.y)
    .map((line) => ({ type: "line", ...line })));
  return { pageNumber: page.pageNumber, events };
});

const wordFrequency = new Map();
const linePairFrequency = new Map();
for (const page of pages) {
  for (const column of [0, 1]) {
    let previousWord = "";
    for (const event of page.events) {
      if (event.type !== "line" || event.column !== column) continue;
      const tokens = event.text.replace(/[\uE000\uE001]/g, "").match(/[\p{L}]+/gu) ?? [];
      if (!tokens.length) continue;
      for (const token of tokens) {
        const word = token.toLocaleLowerCase("es");
        wordFrequency.set(word, (wordFrequency.get(word) ?? 0) + 1);
      }
      const firstWord = tokens[0].toLocaleLowerCase("es");
      const lastWord = tokens.at(-1).toLocaleLowerCase("es");
      if (previousWord) {
        const pair = `${fold(previousWord)}+${fold(firstWord)}`;
        linePairFrequency.set(pair, (linePairFrequency.get(pair) ?? 0) + 1);
      }
      previousWord = lastWord;
    }
  }
}

const commonBoundaryWords = new Set(["A", "AL", "CON", "DE", "DEL", "EL", "EN", "FUE", "LA", "LAS", "LO", "LOS", "MAS", "ME", "NO", "NOS", "O", "POR", "QUE", "SE", "SI", "SU", "UN", "UNA", "Y"]);
function joinLines(lines) {
  let text = "";
  for (const line of lines) {
    const next = line.replace(/[\u00ad\u200b]/g, "").trim();
    if (!next) continue;
    const previousWord = text.match(/([^\s]+)$/)?.[1] ?? "";
    const nextWord = next.match(/^([^\s]+)/)?.[1] ?? "";
    const left = previousWord.toLocaleLowerCase("es").replace(/[^\p{L}\p{N}]+$/gu, "");
    const right = nextWord.toLocaleLowerCase("es").replace(/^[^\p{L}\p{N}]+/gu, "");
    const pair = `${fold(left)}+${fold(right)}`;
    const combined = left + right;
    const explicitHyphen = /[-‐‑]$/.test(previousWord);
    const combinedFrequency = wordFrequency.get(combined) ?? 0;
    const splitFrequency = linePairFrequency.get(pair) ?? 0;
    const corpusPrefersWord = !commonBoundaryWords.has(fold(left))
      && !commonBoundaryWords.has(fold(right))
      && combinedFrequency >= 10
      && combinedFrequency / (splitFrequency + 1) >= 5;
    const brokenWord = knownJoinedPairs.has(pair)
      || (spell.correct(combined) && !spell.correct(right))
      || (spell.correct(combined) && corpusPrefersWord);
    if (text && (explicitHyphen || brokenWord)) {
      text = text.replace(/[-‐‑]\s*$/u, "") + next;
    } else {
      text += `${text ? " " : ""}${next}`;
    }
  }
  return text.replace(/\s+/gu, " ").trim();
}

function parseVerses(lines, bookName, chapterNumber) {
  const verses = [];
  let currentNumber = 0;
  let currentLines = [];

  const saveCurrent = () => {
    if (!currentLines.length) return;
    const text = joinLines(currentLines);
    if (text.length < 2) throw new Error(`Versículo vacío en ${bookName} ${chapterNumber}:${currentNumber}.`);
    verses.push(text);
  };

  for (const rawLine of lines) {
    const line = rawLine
      .replace(new RegExp(`${dropOpen}([A-ZÁÉÍÓÚÜÑ])${dropClose}`, "gu"), "$1")
      .replace(/[\u00a0\u2007]/gu, " ")
      .trim();
    if (!line) continue;

    const marker = line.match(/^(\d{1,3})(?:\s+(.+))?$/u);
    if (!currentNumber) {
      if (marker?.[1] === "1") {
        currentNumber = 1;
        currentLines = marker[2] ? [marker[2]] : [];
      } else {
        currentNumber = 1;
        currentLines = [line];
      }
      continue;
    }

    if (marker && Number(marker[1]) === currentNumber + 1) {
      saveCurrent();
      currentNumber += 1;
      currentLines = marker[2] ? [marker[2]] : [];
      continue;
    }

    if (marker && Number(marker[1]) > currentNumber + 1 && Number(marker[1]) <= 176) {
      throw new Error(`Falta un marcador antes de ${bookName} ${chapterNumber}:${marker[1]} (se esperaba ${currentNumber + 1}); línea: ${line}; previo: ${currentLines.slice(-3).join(" | ")}`);
    }
    currentLines.push(line);
  }

  saveCurrent();
  return verses;
}

let activeBookIndex = -1;
let pendingImplicitBook = -1;
let currentChapter = null;

function finishChapter() {
  if (!currentChapter) return;
  const book = books[currentChapter.bookIndex];
  const verses = parseVerses(currentChapter.lines, book.name, currentChapter.number);
  if (!verses.length) throw new Error(`No se extrajeron versículos para ${book.name} ${currentChapter.number}.`);
  const expectedNumber = book.chapters.length + 1;
  if (currentChapter.number !== expectedNumber) {
    throw new Error(`${book.name}: se esperaba el capítulo ${expectedNumber}, se encontró ${currentChapter.number}.`);
  }
  book.chapters.push(verses);
  currentChapter = null;
}

function beginChapter(bookIndex, number) {
  const book = books[bookIndex];
  if (number > book.chapterCount) throw new Error(`Capítulo fuera de rango: ${book.name} ${number}.`);
  currentChapter = { bookIndex, number, lines: [] };
}

let reachedAppendix = false;
for (const page of pages) {
  for (const event of page.events) {
    if (event.type === "end") {
      reachedAppendix = true;
      break;
    }
    if (event.type === "book") {
      if (event.bookIndex !== activeBookIndex) {
        finishChapter();
        activeBookIndex = event.bookIndex;
        pendingImplicitBook = books[activeBookIndex].chapterCount === 1 ? activeBookIndex : -1;
      }
      continue;
    }

    const line = event.text;
    const heading = line.match(/^\s*(CAP[IÍ]TULO|SALMO)((?:\s+\d+)+)/i);
    if (heading) {
      if (currentChapter) finishChapter();
      const isPsalm = heading[1].toLocaleUpperCase("es") === "SALMO";
      if (isPsalm) activeBookIndex = 18;
      if (activeBookIndex < 0) throw new Error(`Capítulo sin libro: ${line}`);
      let chapterNumber = Number(heading[2].trim().split(/\s+/)[0]);
      const expectedNumber = books[activeBookIndex].chapters.length + 1;
      if (Number(heading[2].replace(/\s+/g, "")) === expectedNumber) {
        chapterNumber = expectedNumber;
      }
      if (!isPsalm
        && chapterNumber === 1
        && books[activeBookIndex].chapters.length === books[activeBookIndex].chapterCount) {
        activeBookIndex += 1;
        if (activeBookIndex === 18) activeBookIndex += 1;
      }
      beginChapter(activeBookIndex, chapterNumber);
      pendingImplicitBook = -1;
      continue;
    }

    if (!currentChapter && pendingImplicitBook >= 0) {
      beginChapter(pendingImplicitBook, 1);
      pendingImplicitBook = -1;
    }

    if (currentChapter) currentChapter.lines.push(line);
  }
  if (reachedAppendix) break;
}
finishChapter();

for (const book of books) {
  if (book.chapters.length !== book.chapterCount) {
    throw new Error(`${book.name}: se extrajeron ${book.chapters.length} de ${book.chapterCount} capítulos.`);
  }
}

const chapterCount = books.reduce((total, book) => total + book.chapters.length, 0);
const verseCount = books.reduce((total, book) => total + book.chapters.reduce((subtotal, chapter) => subtotal + chapter.length, 0), 0);
if (chapterCount !== 1189 || verseCount < 31000 || verseCount > 31200) {
  throw new Error(`Validación fallida: ${chapterCount} capítulos y ${verseCount} versículos.`);
}
if (books[0].chapters[0].length !== 31 || !books[0].chapters[0][0].startsWith("EN el principio")) {
  throw new Error("La validación de Génesis 1 falló.");
}

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify({ translation: "Reina-Valera 2009", books }, null, 2)}\n`, "utf8");
console.log(`Generado ${outputPath}: ${books.length} libros, ${chapterCount} capítulos y ${verseCount} versículos.`);