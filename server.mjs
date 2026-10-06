import { getBible, searchVerses, verseRange, pickVerse, parseReference, strip } from "./bible.mjs";
import dotenv from "dotenv";
import express from "express";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, ".env.local") });
dotenv.config({ path: path.join(__dirname, ".env") });
const catalogPath = path.join(__dirname, "Resources", "bro_branham_sermons_es.json");
const audioCatalogPath = path.join(__dirname, "Resources", "branham_audio_catalog.json");
const sourceController = "https://tabernaculozoe.org/dove/controller/";
const port = Number(process.env.PORT || 5173);
const app = express();
let sourceCatalog;
let sourceCatalogExpiresAt = 0;
let sourceCatalogPromise;
const sourceDetailCache = new Map();
const sourceSearchCache = new Map();

app.use(express.json({ limit: "2mb" }));

function getGeminiApiKey() {
  return process.env.GEMINI_API_KEY || process.env.GEMINI_BIBLE_API_KEY;
}

const sharedCollections = new Set(["favorites", "notes", "highlights", "multiNotes", "chat"]);

function getSupabaseConfig() {
  const url = process.env.SUPABASE_URL?.replace(/\/+$/, "");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    const error = new Error("La sincronización pública requiere SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY configuradas en el servidor.");
    error.status = 503;
    throw error;
  }
  return { url, key };
}

async function supabaseRequest(path, options = {}) {
  const { url, key } = getSupabaseConfig();
  const response = await fetch(`${url}/rest/v1/${path}`, {
    ...options,
    headers: {
      apikey: key,
      ...(key.startsWith("sb_secret_") ? {} : { Authorization: `Bearer ${key}` }),
      "Content-Type": "application/json",
      ...options.headers,
    },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    const error = new Error("No se pudo sincronizar la información compartida.");
    error.status = 502;
    throw error;
  }
  return response;
}

function sharedCollection(value) {
  if (!sharedCollections.has(value)) {
    const error = new Error("La sección compartida indicada no existe.");
    error.status = 404;
    throw error;
  }
  return value;
}

app.get("/api/shared-state", async (request, response) => {
  try {
    const query = new URLSearchParams({ select: "collection,item_key,payload", order: "collection.asc,item_key.asc" });
    if (request.query.collection) query.set("collection", `eq.${sharedCollection(String(request.query.collection))}`);
    const result = await supabaseRequest(`shared_page_state?${query}`);
    response.json({ entries: await result.json() });
  } catch (error) {
    response.status(error.status || 500).json({ error: error.status ? error.message : "No se pudo cargar la información compartida." });
  }
});

app.put("/api/shared-state/:collection/:key", async (request, response) => {
  try {
    const collection = sharedCollection(request.params.collection);
    const itemKey = request.params.key;
    if (!itemKey || itemKey.length > 240) {
      response.status(400).json({ error: "La clave del elemento no es válida." });
      return;
    }
    const payload = request.body?.payload;
    if (payload === undefined || Buffer.byteLength(JSON.stringify(payload)) > 1_000_000) {
      response.status(400).json({ error: "El contenido compartido no es válido o excede el límite permitido." });
      return;
    }
    if (collection === "chat") {
      if (itemKey !== "global" || !Array.isArray(payload) || payload.length > 2000
        || payload.some((message) => !message || !["assistant", "user"].includes(message.role) || typeof message.text !== "string")) {
        response.status(400).json({ error: "La conversación compartida no tiene un formato válido." });
        return;
      }
    } else {
      const keyField = collection === "notes" || collection === "multiNotes" ? "id" : "key";
      if (!payload || typeof payload !== "object" || Array.isArray(payload) || payload[keyField] !== itemKey) {
        response.status(400).json({ error: "El elemento compartido no tiene un formato válido." });
        return;
      }
      if (collection === "highlights" && !["yellow", "green", "blue", "pink"].includes(payload.color)) {
        response.status(400).json({ error: "El color del resaltado no es válido." });
        return;
      }
    }
    const query = new URLSearchParams({ on_conflict: "collection,item_key" });
    await supabaseRequest(`shared_page_state?${query}`, {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({ collection, item_key: itemKey, payload }),
    });
    response.status(204).end();
  } catch (error) {
    response.status(error.status || 500).json({ error: error.status ? error.message : "No se pudo guardar la información compartida." });
  }
});

app.delete("/api/shared-state/:collection/:key", async (request, response) => {
  try {
    const collection = sharedCollection(request.params.collection);
    const itemKey = request.params.key;
    if (!itemKey || itemKey.length > 240) {
      response.status(400).json({ error: "La clave del elemento no es válida." });
      return;
    }
    const query = new URLSearchParams({ collection: `eq.${collection}`, item_key: `eq.${itemKey}` });
    await supabaseRequest(`shared_page_state?${query}`, { method: "DELETE", headers: { Prefer: "return=minimal" } });
    response.status(204).end();
  } catch (error) {
    response.status(error.status || 500).json({ error: error.status ? error.message : "No se pudo eliminar la información compartida." });
  }
});

let catalogPromise;
let audioCatalogPromise;
function getCatalog() {
  catalogPromise ??= readFile(catalogPath, "utf8").then((contents) => {
    const catalog = JSON.parse(contents);
    if (!Array.isArray(catalog.sermons)) {
      throw new Error("El catálogo no contiene una lista válida de mensajes.");
    }
    return catalog.sermons;
  }).catch((error) => {
    if (error.code === "ENOENT") return [];
    throw error;
  });
  return catalogPromise;
}

function getAudioCatalog() {
  audioCatalogPromise ??= readFile(audioCatalogPath, "utf8").then((contents) => {
    const catalog = JSON.parse(contents);
    if (!Array.isArray(catalog)) {
      throw new Error("El catálogo de audio no contiene una lista válida de mensajes.");
    }
    return catalog;
  }).catch((error) => {
    if (error.code === "ENOENT") return [];
    throw error;
  });
  return audioCatalogPromise;
}

async function postSource(endpoint, fields) {
  const response = await fetch(new URL(endpoint, sourceController), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
    body: new URLSearchParams(fields),
    signal: AbortSignal.timeout(15_000),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.state !== 1 || !Array.isArray(payload.resultado)) {
    throw new Error("No se pudo consultar el catálogo de mensajes remoto.");
  }
  return payload.resultado;
}

function mapSourceMetadata(record) {
  const id = String(record?.MessageId ?? "").trim();
  if (!id) return null;
  const date = String(record.Date ?? "");
  return {
    id,
    code: date || id,
    title: String(record.Title ?? ""),
    date,
    location: String(record.Place ?? ""),
    paragraphCount: null,
  };
}

function getSourceCatalog() {
  if (sourceCatalog && sourceCatalogExpiresAt > Date.now()) return Promise.resolve(sourceCatalog);
  sourceCatalogPromise ??= postSource("list_by_date.php", {}).then((records) => {
    sourceCatalog = records.map(mapSourceMetadata).filter(Boolean);
    sourceCatalogExpiresAt = Date.now() + 5 * 60_000;
    return sourceCatalog;
  }).finally(() => {
    sourceCatalogPromise = undefined;
  });
  return sourceCatalogPromise;
}

async function getAvailableCatalog() {
  try {
    return { sermons: await getSourceCatalog(), remote: true };
  } catch (sourceError) {
    const sermons = await getCatalog();
    if (sermons.length) return { sermons, remote: false };
    throw sourceError;
  }
}

function mapSourceParagraph(record) {
  const id = String(record.MessageId ?? "");
  return {
    id,
    code: String(record.Date ?? "") || id,
    title: String(record.Title ?? ""),
    number: Number.parseInt(record.Number, 10),
    text: String(record.Content ?? ""),
  };
}

async function searchSourceParagraphs(query, limit = 8) {
  const search = String(query ?? "").trim().slice(0, 200);
  if (search.length < 2) return [];
  const key = normalize(search);
  let cached = sourceSearchCache.get(key);
  if (!cached || cached.expiresAt <= Date.now()) {
    cached = {
      expiresAt: Date.now() + 5 * 60_000,
      promise: postSource("search_message_1.php", { text: search })
        .then((records) => records.map(mapSourceParagraph).filter((item) => item.id && item.text)),
    };
    sourceSearchCache.set(key, cached);
    cached.promise.catch(() => {
      if (sourceSearchCache.get(key) === cached) sourceSearchCache.delete(key);
    });
    if (sourceSearchCache.size > 50) sourceSearchCache.delete(sourceSearchCache.keys().next().value);
  }
  return (await cached.promise).slice(0, limit);
}

async function getSourceSermon(id, metadata = null) {
  let pending = sourceDetailCache.get(id);
  if (!pending) {
    pending = postSource("show_message.php", { id }).then((records) => {
      if (!records.length) return null;
      const summary = mapSourceMetadata(records[0]) ?? { id };
      const paragraphs = records.map((record) => ({
        number: Number.parseInt(record.Number, 10),
        text: String(record.Content ?? ""),
      }));
      return { ...summary, ...metadata, paragraphCount: paragraphs.length, paragraphs };
    }).catch((error) => {
      sourceDetailCache.delete(id);
      throw error;
    });
    sourceDetailCache.set(id, pending);
    if (sourceDetailCache.size > 25) sourceDetailCache.delete(sourceDetailCache.keys().next().value);
  }
  return pending;
}

async function getSpanishAudio(id) {
  const catalog = await getAudioCatalog();
  const matches = catalog.filter((entry) => entry.code === id && entry.audio);
  const match = matches.find((entry) => entry.lang === "SPN");
  if (!match) return "";
  const url = new URL(match.audio);
  return url.protocol === "https:" ? url.href : "";
}

function getSummary(sermon) {
  return {
    id: sermon.id,
    code: sermon.code ?? sermon.date ?? sermon.id,
    title: sermon.title,
    date: sermon.date ?? sermon.meta?.date ?? "",
    location: sermon.location ?? sermon.meta?.location ?? "",
    paragraphCount: sermon.paragraphCount ?? sermon.paragraphs?.length ?? 0,
  };
}

function normalize(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("es")
    .trim();
}

function queryTerms(query) {
  const ignored = new Set([
    "a", "al", "algo", "como", "con", "cual", "cuando", "de", "del", "donde",
    "el", "ella", "en", "es", "esa", "ese", "esta", "este", "la", "las", "lo",
    "los", "mas", "me", "mi", "para", "por", "que", "se", "sin", "sobre", "su",
    "sus", "un", "una", "y", "yo", "dime", "podrias", "quisiera", "mensaje",
    "mensajes", "sermon", "sermones", "william", "branham",
    "dice", "dijo", "habla", "hablan", "ensenar", "ensena",
  ]);
  return [...new Set(normalize(query).split(/[^\p{L}\p{N}]+/u)
    .filter((term) => (term.length > 2 || term === "fe") && !ignored.has(term)))];
}

function searchTerms(query) {
  return normalize(query).split(/[^\p{L}\p{N}]+/u).filter((term) => term.length > 1);
}

function searchParagraphs(sermons, query, limit = 5) {
  const terms = queryTerms(query);
  if (!terms.length) return [];

  const termSet = new Set(terms);
  const documentFrequency = new Map(terms.map((term) => [term, 0]));
  const results = [];
  let paragraphCount = 0;
  for (const sermon of sermons) {
    for (const paragraph of sermon.paragraphs ?? []) {
      paragraphCount += 1;
      const words = normalize(paragraph.text).split(/[^\p{L}\p{N}]+/u);
      const wordCounts = new Map();
      for (const word of words) {
        if (termSet.has(word)) wordCounts.set(word, (wordCounts.get(word) ?? 0) + 1);
      }
      if (!wordCounts.size) continue;
      for (const term of terms) {
        if (wordCounts.has(term)) {
          documentFrequency.set(term, documentFrequency.get(term) + 1);
        }
      }
      results.push({
        wordCounts,
        source: {
          id: sermon.id,
          code: sermon.id,
          title: sermon.title,
          number: paragraph.number,
          text: paragraph.text,
        },
      });
    }
  }

  const ranked = results.map(({ source, wordCounts }) => {
    let score = 0;
    let matchedTerms = 0;
    for (const term of terms) {
      const frequency = wordCounts.get(term) ?? 0;
      if (!frequency) continue;
      matchedTerms += 1;
      const inverseFrequency = Math.log1p(
        (paragraphCount - documentFrequency.get(term) + 0.5)
          / (documentFrequency.get(term) + 0.5),
      );
      score += inverseFrequency * (1 + Math.min(frequency - 1, 3) * 0.15);
    }
    score *= 1 + matchedTerms / terms.length;
    return { ...source, score };
  }).sort((a, b) => b.score - a.score || a.code.localeCompare(b.code) || a.number - b.number);

  const selected = [];
  const sermonCounts = new Map();
  for (const result of ranked) {
    const count = sermonCounts.get(result.id) ?? 0;
    if (count >= 2) continue;
    selected.push(result);
    sermonCounts.set(result.id, count + 1);
    if (selected.length === limit) break;
  }
  return selected;
}

app.get("/api/health", (_request, response) => {
  response.json({ ok: true });
});

app.get("/api/bible/books", async (_request, response, next) => {
  try {
    const bible = await getBible();
    response.json({
      translation: bible.translation,
      books: bible.books.map((book, index) => ({ index, name: book.name, chapters: book.chapters.length })),
    });
  } catch (error) { next(error); }
});

app.get("/api/bible/chapter/:book/:chapter", async (request, response, next) => {
  try {
    const bible = await getBible();
    const book = bible.books[Number(request.params.book)];
    const verses = book?.chapters[Number(request.params.chapter) - 1];
    if (!verses) { response.status(404).json({ error: "Capítulo no encontrado." }); return; }
    response.json({ book: book.name, chapter: Number(request.params.chapter), chapters: book.chapters.length, verses: verses.map((text, i) => ({ verse: i + 1, text })) });
  } catch (error) { next(error); }
});

app.get("/api/bible/search", async (request, response, next) => {
  try {
    const bible = await getBible();
    const q = String(request.query.q ?? "").trim().slice(0, 200);
    response.json({ verses: q.length < 2 ? [] : searchVerses(bible, q, 30).map(pickVerse) });
  } catch (error) { next(error); }
});

app.post("/api/bible/chat", async (request, response, next) => {
  try {
    const apiKey = getGeminiApiKey();
    if (!apiKey) { response.status(503).json({ error: "Configura GEMINI_API_KEY o GEMINI_BIBLE_API_KEY en el entorno del servidor." }); return; }
    const question = String(request.body?.question ?? "").trim().slice(0, 600);
    if (!question) { response.status(400).json({ error: "Escribe una pregunta antes de enviar." }); return; }

    const bible = await getBible();
    // Gemini solo amplía la pregunta con palabras clave; los versículos salen del archivo.
    let extra = "";
    try {
      const kw = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(process.env.GEMINI_MODEL || "gemini-3.1-flash-lite")}:generateContent?key=${encodeURIComponent(apiKey)}`,
        { method: "POST", headers: { "Content-Type": "application/json" }, signal: AbortSignal.timeout(20_000),
          body: JSON.stringify({
            contents: [{ role: "user", parts: [{ text: `Da de 6 a 10 palabras clave en español (sinónimos y formas bíblicas antiguas, como en la Reina-Valera 2009) para buscar versículos que respondan: "${question}". Responde solo las palabras separadas por espacios.` }] }],
            generationConfig: { temperature: 0, maxOutputTokens: 80 },
          }) },
      );
      const kp = await kw.json().catch(() => ({}));
      extra = String(kp?.candidates?.[0]?.content?.parts?.map((x) => x.text ?? "").join(" ") ?? "").slice(0, 200);
    } catch { /* se usa solo la pregunta */ }
    const candidates = searchVerses(bible, `${question} ${extra}`, 14);
    if (!candidates.length) {
      response.json({ answer: "No encontré versículos que respondan eso en la Biblia (Reina-Valera 2009).", verses: [] });
      return;
    }
    const context = candidates.map((v, i) => `V${i + 1} (${v.book} ${v.chapter}:${v.verse}): ${v.text}`).join("\n");
    const model = process.env.GEMINI_MODEL || "gemini-3.1-flash-lite";
    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: AbortSignal.timeout(45_000),
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: [
            "Eres un asistente de estudio bíblico. Respondes en español usando únicamente los versículos V1, V2… proporcionados (Reina-Valera 2009).",
            "Elige los 1 a 4 versículos que respondan directamente la pregunta y explica en una o dos oraciones cortas, basándote solo en ellos.",
            "No uses conocimiento externo ni cites versículos que no estén en la lista. No inventes texto bíblico.",
            'Devuelve JSON: {"versiculos":[números de V],"explicacion":"..."}.',
            'Si ningún versículo responde la pregunta, devuelve {"versiculos":[],"explicacion":""}.',
          ].join(" ") }] },
          contents: [{ role: "user", parts: [{ text: `${context}\n\nPregunta: ${question}` }] }],
          generationConfig: { temperature: 0, maxOutputTokens: 600, responseMimeType: "application/json" },
        }),
      },
    );
    const payload = await geminiResponse.json().catch(() => ({}));
    if (!geminiResponse.ok) {
      response.status(geminiResponse.status === 429 ? 429 : 502).json({ error: payload?.error?.message || "No se pudo consultar Gemini. Inténtalo de nuevo." });
      return;
    }
    const raw = payload?.candidates?.[0]?.content?.parts?.map((part) => part.text ?? "").join("").trim();
    let parsed = {};
    try { parsed = JSON.parse(String(raw).replace(/^```(?:json)?|```$/g, "").trim()); } catch { parsed = {}; }
    // El texto bíblico siempre sale del archivo, nunca del modelo.
    const chosen = [...new Set((Array.isArray(parsed.versiculos) ? parsed.versiculos : []).map((x) => Number(String(x).replace(/\D/g, ""))))]
      .map((n) => candidates[n - 1]).filter(Boolean).slice(0, 4);
    if (!chosen.length) {
      response.json({ answer: "No encontré versículos que respondan eso con precisión en la Biblia (Reina-Valera 2009).", verses: [] });
      return;
    }
    response.json({
      answer: typeof parsed.explicacion === "string" ? parsed.explicacion.trim().slice(0, 500) : "",
      verses: chosen.map(pickVerse),
    });
  } catch (error) { next(error); }
});

app.get("/api/sermons", async (request, response, next) => {
  try {
    const { sermons, remote } = await getAvailableCatalog();
    const search = normalize(request.query.search);
    const terms = searchTerms(search);
    const offset = Math.max(0, Number.parseInt(request.query.offset, 10) || 0);
    const limit = Math.min(100, Math.max(1, Number.parseInt(request.query.limit, 10) || 40));
    let matches = sermons;
    if (search && remote) {
      const metadataMatches = sermons.filter((sermon) => {
        const metadata = normalize(`${sermon.id} ${sermon.code} ${sermon.title} ${sermon.date} ${sermon.location}`);
        return metadata.includes(search);
      });
      let paragraphMatches = [];
      try {
        paragraphMatches = await searchSourceParagraphs(search, Number.MAX_SAFE_INTEGER);
      } catch (error) {
        if (!metadataMatches.length) throw error;
      }
      const matchingIds = new Set([
        ...metadataMatches.map((sermon) => sermon.id),
        ...paragraphMatches.map((paragraph) => paragraph.id),
      ]);
      matches = sermons.filter((sermon) => matchingIds.has(sermon.id));
    } else if (search) {
      matches = sermons.filter((sermon) => {
          const metadata = normalize(`${sermon.id} ${sermon.title} ${sermon.date} ${sermon.location}`);
          return metadata.includes(search)
            || (sermon.paragraphs ?? []).some((paragraph) => {
              const text = normalize(paragraph.text);
              return text.includes(search) || (terms.length > 1 && terms.every((term) => text.includes(term)));
            });
        });
    }
    response.json({
      total: matches.length,
      sermons: matches.slice(offset, offset + limit).map(getSummary),
    });
  } catch (error) {
    next(error);
  }
});

app.get("/api/passages", async (request, response, next) => {
  try {
    const q = String(request.query.q ?? "").trim().slice(0, 200);
    if (q.length < 2) {
      response.json({ passages: [] });
      return;
    }
    const { sermons, remote } = await getAvailableCatalog();
    const pick = ({ id, code, title, number, text }) => ({ id, code: code ?? id, title, number, text });
    const ref = q.match(/^(\d{2}-\d{4}[A-Za-z]?)\s*(?:[:,]|\s)\s*(?:p[áa]rrafo\s*)?(\d+)$/i);
    if (remote && ref) {
      const metadata = sermons.find((item) => item.code.toLowerCase() === ref[1].toLowerCase());
      const sermon = metadata ? await getSourceSermon(metadata.id, metadata) : null;
      const paragraph = sermon?.paragraphs.find((item) => item.number === Number(ref[2]));
      response.json({ passages: paragraph ? [pick({ id: sermon.id, code: sermon.code, title: sermon.title, ...paragraph })] : [] });
      return;
    }
    if (ref) {
      const sermon = sermons.find((item) => item.id.toLowerCase() === ref[1].toLowerCase());
      const paragraph = sermon?.paragraphs?.find((item) => item.number === Number(ref[2]));
      response.json({ passages: paragraph ? [pick({ id: sermon.id, code: sermon.code, title: sermon.title, ...paragraph })] : [] });
      return;
    }
    const passages = remote
      ? await searchSourceParagraphs(q, 8)
      : searchParagraphs(sermons, q, 8);
    response.json({ passages: passages.map(pick) });
  } catch (error) {
    next(error);
  }
});

app.get("/api/sermons/:id", async (request, response, next) => {
  try {
    const { sermons, remote } = await getAvailableCatalog();
    const metadata = sermons.find((item) => String(item.id) === request.params.id);
    let sermon = metadata;
    if (remote && metadata) {
      try {
        sermon = await getSourceSermon(metadata.id, metadata);
      } catch (error) {
        const localSermon = (await getCatalog()).find((item) => item.id === request.params.id);
        if (!localSermon) throw error;
        sermon = localSermon;
      }
    }
    if (!sermon) {
      response.status(404).json({ error: "No se encontró ese mensaje." });
      return;
    }
    response.json({
      ...getSummary(sermon),
      audioUrl: await getSpanishAudio(sermon.code ?? sermon.id),
      paragraphs: sermon.paragraphs ?? [],
    });
  } catch (error) {
    next(error);
  }
});

app.post("/api/chat", async (request, response, next) => {
  try {
    const apiKey = getGeminiApiKey();
    if (!apiKey) {
      response.status(503).json({
        error: "Configura GEMINI_API_KEY o GEMINI_BIBLE_API_KEY en el entorno del servidor.",
      });
      return;
    }

    const question = typeof request.body?.question === "string"
      ? request.body.question.trim().slice(0, 2000)
      : "";
    if (!question) {
      response.status(400).json({ error: "Escribe una pregunta antes de enviar." });
      return;
    }

    let sources;
    try {
      sources = await searchSourceParagraphs(question, 5);
    } catch {
      sources = searchParagraphs(await getCatalog(), question, 5);
    }
    if (!sources.length) {
      response.json({
        answer: "No encontré evidencia suficiente sobre eso en los mensajes disponibles.",
        sources: [],
      });
      return;
    }

    const history = Array.isArray(request.body?.history)
      ? request.body.history.slice(-6).flatMap((message) => {
          if (!message || message.role !== "user" || typeof message.text !== "string") return [];
          return [{ role: "user", parts: [{ text: message.text.slice(0, 500) }] }];
        })
      : [];
    const context = sources
      .map((source, index) => `PASAJE ${index + 1}: ${source.text.slice(0, 1500)}`)
      .join("\n\n");
    const asksForDetail = /\b(lista|enumera|puntos|pasos|detalla|detalladamente|con detalle|compara|diferencias|varios|menciona)\b/i.test(question);
    const maxQuotes = asksForDetail ? 3 : 1;
    const model = process.env.GEMINI_MODEL || "gemini-3.1-flash-lite";
    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: AbortSignal.timeout(45_000),
        body: JSON.stringify({
          systemInstruction: {
            parts: [{
              text: [
                "Eres un buscador de citas en un catálogo de mensajes. No redactas respuestas propias.",
                "Dada la pregunta, elige de los PASAJES numerados el fragmento que la responde directamente.",
                `Devuelve hasta ${maxQuotes} cita(s) en JSON: {"citas":[{"pasaje":N,"texto":"..."}]}.`,
                "El campo texto debe ser una copia LITERAL, carácter por carácter, de una o dos oraciones consecutivas del pasaje elegido. No resumas, no parafrasees, no cambies palabras ni unas fragmentos distantes.",
                "Si ningún pasaje responde específicamente la pregunta, devuelve {\"citas\":[]}.",
              ].join(" "),
            }],
          },
          contents: [
            ...history,
            { role: "user", parts: [{ text: `${context}\n\nPregunta: ${question}` }] },
          ],
          generationConfig: { temperature: 0, maxOutputTokens: 700, responseMimeType: "application/json" },
        }),
      },
    );

    const payload = await geminiResponse.json().catch(() => ({}));
    if (!geminiResponse.ok) {
      const detail = payload?.error?.message;
      response.status(geminiResponse.status === 429 ? 429 : 502).json({
        error: detail || "No se pudo consultar Gemini. Inténtalo de nuevo.",
      });
      return;
    }

    const rawAnswer = payload?.candidates?.[0]?.content?.parts?.map((part) => part.text ?? "").join("").trim();
    if (!rawAnswer) {
      response.status(502).json({ error: "Gemini devolvió una respuesta vacía." });
      return;
    }

    let picks = [];
    try {
      const parsed = JSON.parse(rawAnswer.replace(/^```(?:json)?|```$/g, "").trim());
      picks = Array.isArray(parsed?.citas) ? parsed.citas : [];
    } catch {
      picks = [];
    }

    // Una cita solo se acepta si existe literalmente dentro del párrafo del catálogo.
    const flat = (value) => normalize(String(value)).replace(/[^\p{L}\p{N}]+/gu, " ").trim();
    const verified = [];
    const used = new Set();
    for (const pick of picks.slice(0, maxQuotes)) {
      const source = sources[Number(pick?.pasaje) - 1];
      const quote = typeof pick?.texto === "string" ? pick.texto.replace(/^[“"«\s]+|[”"»\s]+$/g, "") : "";
      if (!source || quote.length < 15 || used.has(source) || !flat(source.text).includes(flat(quote))) continue;
      used.add(source);
      verified.push({ source, quote });
    }

    if (!verified.length) {
      response.json({
        answer: "No encontré una cita que responda eso con precisión en los mensajes disponibles.",
        sources: [],
      });
      return;
    }

    const answer = verified
      .map(({ source, quote }) => `“${quote}” [${source.code}, párrafo ${source.number}]`)
      .join("\n\n");

    response.json({
      answer,
      sources: verified.map(({ source: { id, code, title, number, text } }) => ({
        id, code, title, number, text: text.slice(0, 360),
      })),
    });
  } catch (error) {
    next(error);
  }
});

app.use((error, _request, response, _next) => {
  console.error("Error en la API:", error);
  if (response.headersSent) return;
  response.status(500).json({ error: "Ocurrió un error al consultar el catálogo." });
});

if (process.env.NODE_ENV === "production") {
  app.use(express.static(path.join(__dirname, "public")));
  app.get("*", (_request, response) => response.sendFile(path.join(__dirname, "public", "index.html")));
} else {
  const { createServer: createViteServer } = await import("vite");
  const vite = await createViteServer({ server: { middlewareMode: true }, appType: "spa" });
  app.use(vite.middlewares);
}

export default app;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  app.listen(port, () => {
    console.log(`Mensajes web disponible en http://localhost:${port}`);
  });
}
