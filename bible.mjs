import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
let biblePromise;

export function getBible() {
  biblePromise ??= fs.readFile(path.join(here, "Resources", "biblia_rv2009.json"), "utf8").then((raw) => {
    const data = JSON.parse(raw);
    const verses = [];
    data.books.forEach((book, bookIndex) => book.chapters.forEach((chapter, chapterIndex) =>
      chapter.forEach((text, verseIndex) => verses.push({
        book: book.name, bookIndex, chapter: chapterIndex + 1, verse: verseIndex + 1, text,
        words: null,
      }))));
    return { ...data, verses };
  });
  return biblePromise;
}

export const strip = (value) => String(value ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("es").trim();
const STOP = new Set("a al algo como con cual cuales cuando de del donde el ella en es esa ese esta este la las lo los mas me mi para por que se sin sobre su sus un una y yo dice dijo habla hablan biblia dime versiculo versiculos texto textos hay son fue era".split(" "));

export function terms(query) {
  return [...new Set(strip(query).split(/[^\p{L}\p{N}]+/u).filter((t) => t.length > 2 && !STOP.has(t)))];
}

// Reconoce referencias como "Juan 3:16", "1 Corintios 13", "Salmos 23:1-3".
export function parseReference(bible, query) {
  const match = strip(query).match(/^\s*((?:[123]\s*)?[a-z]+(?:\s+[a-z]+)?)\s+(\d+)(?:\s*[:.,]\s*(\d+)(?:\s*-\s*(\d+))?)?\s*$/);
  if (!match) return null;
  const wanted = match[1].replace(/\s+/g, " ");
  const index = bible.books.findIndex((book) => strip(book.name) === wanted)
    ?? -1;
  const found = index >= 0 ? index : bible.books.findIndex((book) => strip(book.name).startsWith(wanted) && wanted.length >= 3);
  if (found < 0) return null;
  const chapter = Number(match[2]);
  const verses = bible.books[found].chapters[chapter - 1];
  if (!verses) return null;
  const from = match[3] ? Number(match[3]) : 1;
  const to = match[3] ? Number(match[4] || match[3]) : verses.length;
  return { bookIndex: found, chapter, from, to };
}

export function verseRange(bible, ref) {
  return bible.verses.filter((v) => v.bookIndex === ref.bookIndex && v.chapter === ref.chapter && v.verse >= ref.from && v.verse <= ref.to);
}

export function searchVerses(bible, query, limit = 8) {
  const ref = parseReference(bible, query);
  if (ref) return verseRange(bible, ref).slice(0, limit);
  const qTerms = terms(query);
  if (!qTerms.length) return [];
  const df = new Map(qTerms.map((t) => [t, 0]));
  const hits = [];
  for (const v of bible.verses) {
    v.words ??= new Set(strip(v.text).split(/[^\p{L}\p{N}]+/u));
    const matched = qTerms.filter((t) => v.words.has(t));
    if (!matched.length) continue;
    matched.forEach((t) => df.set(t, df.get(t) + 1));
    hits.push({ v, matched });
  }
  const total = bible.verses.length;
  return hits
    .map(({ v, matched }) => ({
      v,
      score: matched.reduce((s, t) => s + Math.log1p((total - df.get(t) + 0.5) / (df.get(t) + 0.5)), 0) * (1 + matched.length / qTerms.length),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(({ v }) => v);
}

export const pickVerse = ({ book, bookIndex, chapter, verse, text }) => ({ book, bookIndex, chapter, verse, text });
