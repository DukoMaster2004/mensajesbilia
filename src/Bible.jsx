import { useEffect, useRef, useState } from "react";
import Icon from "./Icon.jsx";
import { conversationToText, HIGHLIGHT_COLORS, itemKey, shareContent } from "./useStudyData.js";
import { NoteComposer, NoteItem } from "./StudyViews.jsx";
import { HighlightableText } from "./HighlightableText.jsx";

const COLOR_LABEL = { yellow: "Amarillo", green: "Verde", blue: "Azul", pink: "Rosa" };

async function getJson(url, options) {
  const res = await fetch(url, options);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || "No se pudo cargar.");
  return data;
}

const ref = (v) => `${v.book} ${v.chapter}:${v.verse}`;
const savedPos = () => {
  try { return JSON.parse(localStorage.getItem("branham-bible-pos")) || { book: 0, chapter: 1 }; } catch { return { book: 0, chapter: 1 }; }
};

function VerseList({ verses, onToast, onOpen }) {
  return verses.map((v) => (
    <div className="bible-hit" key={`${v.book}-${v.chapter}-${v.verse}`}>
      <button className="note-source" onClick={() => onOpen(v)}>{ref(v)}</button>
      <p>{v.text}</p>
      <div className="note-actions">
        <button onClick={async () => onToast(await shareContent({ title: `${ref(v)} (RV 2009)`, text: `“${v.text}”` }))}><Icon name="share" size={14} /> Compartir</button>
      </div>
    </div>
  ));
}

function bibleConversation(chat) {
  return conversationToText(chat.map((m) => {
    if (!m.verses?.length) return m;
    const verses = m.verses.map((v) => `- ${ref(v)}: “${v.text}”`).join("\n");
    return { ...m, text: `${m.text ? `${m.text}\n\n` : ""}Versículos:\n${verses}` };
  }));
}

function BibleChat({ onToast, onOpen }) {
  const [chat, setChat] = useState([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const endRef = useRef(null);
  useEffect(() => { endRef.current?.scrollIntoView({ behavior: "smooth" }); }, [chat, sending]);

  async function send(event) {
    event.preventDefault();
    const question = draft.trim();
    if (!question || sending) return;
    setDraft(""); setError(""); setSending(true);
    setChat((c) => [...c, { role: "user", text: question }]);
    try {
      const r = await getJson("/api/bible/chat", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ question }) });
      setChat((c) => [...c, { role: "assistant", text: r.answer, verses: r.verses }]);
    } catch (e) { setError(e.message); } finally { setSending(false); }
  }

  return (
    <div className="bible-chat">
      <div className="bible-chat-scroll">
        {chat.length === 0 && <p className="quote-hint">Pregunta sobre un tema o pasaje bíblico. Las respuestas muestran versículos reales de la Biblia (Reina-Valera 2009).</p>}
        {chat.map((m, i) => (
          <div className={`chat-message ${m.role}`} key={i}>
            <div className="bubble-wrap">
              {m.text && <div className="bubble">{m.text}</div>}
              {m.verses?.length > 0 && <div className="bible-verses"><VerseList verses={m.verses} onToast={onToast} onOpen={onOpen} /></div>}
              {m.role === "assistant" && !m.verses?.length && !m.text && <div className="bubble">No encontré versículos que respondan eso.</div>}
            </div>
          </div>
        ))}
        {sending && <div className="bubble typing"><i /><i /><i /></div>}
        <div ref={endRef} />
      </div>
      {error && <div className="chat-error">{error}</div>}
      <form className="chat-composer" onSubmit={send}>
        <textarea value={draft} rows="1" onChange={(e) => setDraft(e.target.value)} aria-label="Pregunta bíblica"
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(e); } }}
          placeholder="¿Qué dice la Biblia sobre la fe?" />
        <button type="submit" disabled={!draft.trim() || sending} aria-label="Enviar"><Icon name="send" size={17} /></button>
      </form>
      {chat.length > 0 && (
        <div className="bible-chat-actions">
          <button className="ghost-button" title="Compartir conversación"
            onClick={async () => onToast(await shareContent({ title: "Biblia Reina-Valera 2009", text: bibleConversation(chat) }))}>
            <Icon name="share" size={14} /> Compartir conversación</button>
          <button className="ghost-button danger" title="Borrar conversación" onClick={() => setChat([])}>
            <Icon name="trash" size={14} /> Borrar conversación</button>
        </div>
      )}
    </div>
  );
}

export function BibleView({ onToast, study, target, canEdit }) {
  const [composer, setComposer] = useState(null);
  const [tab, setTab] = useState("read");
  const [books, setBooks] = useState([]);
  const [pos, setPos] = useState(savedPos);
  const [chapter, setChapter] = useState(null);
  const [error, setError] = useState("");
  const [focus, setFocus] = useState(null);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState(null);
  const [speaking, setSpeaking] = useState(false);
  const speechRef = useRef({ active: false, verses: [], index: 0 });
  const topRef = useRef(null);

  const stopReading = () => {
    speechRef.current.active = false;
    window.speechSynthesis?.cancel();
    setSpeaking(false);
  };

  useEffect(() => () => {
    speechRef.current.active = false;
    window.speechSynthesis?.cancel();
  }, []);

  function readNextVerse() {
    const reading = speechRef.current;
    if (!reading.active) return;
    if (reading.index >= reading.verses.length) {
      reading.active = false;
      setSpeaking(false);
      return;
    }
    const verse = reading.verses[reading.index++];
    const utterance = new SpeechSynthesisUtterance(`${verse.verse}. ${verse.text}`);
    utterance.lang = "es-ES";
    const spanishVoice = window.speechSynthesis.getVoices().find((voice) => voice.lang.toLowerCase().startsWith("es"));
    if (spanishVoice) utterance.voice = spanishVoice;
    utterance.onend = readNextVerse;
    utterance.onerror = (event) => {
      if (event.error === "canceled" || !speechRef.current.active) return;
      speechRef.current.active = false;
      setSpeaking(false);
      onToast("No se pudo reproducir la lectura en voz alta.");
    };
    window.speechSynthesis.speak(utterance);
  }

  function startReading() {
    if (!("speechSynthesis" in window) || typeof SpeechSynthesisUtterance === "undefined") {
      onToast("La lectura en voz alta no está disponible en este navegador.");
      return;
    }
    if (!chapter?.verses?.length) return;
    speechRef.current = { active: true, verses: chapter.verses, index: 0 };
    setSpeaking(true);
    window.speechSynthesis.cancel();
    readNextVerse();
  }

  useEffect(() => { getJson("/api/bible/books").then((d) => setBooks(d.books)).catch((e) => setError(e.message)); }, []);
  useEffect(() => {
    setError(""); setChapter(null);
    getJson(`/api/bible/chapter/${pos.book}/${pos.chapter}`).then(setChapter).catch((e) => setError(e.message));
    try { localStorage.setItem("branham-bible-pos", JSON.stringify(pos)); } catch { /* storage unavailable */ }
  }, [pos]);
  useEffect(() => {
    if (chapter && focus) window.setTimeout(() => document.getElementById(`bv-${focus}`)?.scrollIntoView({ block: "center", behavior: "smooth" }), 80);
  }, [chapter, focus]);
  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) { setResults(null); return undefined; }
    const timer = window.setTimeout(() => getJson(`/api/bible/search?q=${encodeURIComponent(term)}`).then((d) => setResults(d.verses)).catch(() => setResults([])), 350);
    return () => window.clearTimeout(timer);
  }, [query]);

  useEffect(() => { if (target) { stopReading(); setPos({ book: target.book, chapter: target.chapter }); setFocus(target.verse); setTab("read"); setQuery(""); } }, [target]);
  useEffect(() => { setComposer(null); }, [pos]);

  const open = (v) => { setPos({ book: v.bookIndex, chapter: v.chapter }); setFocus(v.verse); setTab("read"); setQuery(""); };
  const go = (book, ch) => { stopReading(); setFocus(null); setPos({ book, chapter: ch }); topRef.current?.scrollIntoView(); };
  const total = books[pos.book]?.chapters || 1;
  const prev = () => (pos.chapter > 1 ? go(pos.book, pos.chapter - 1) : pos.book > 0 && go(pos.book - 1, books[pos.book - 1].chapters));
  const next = () => (pos.chapter < total ? go(pos.book, pos.chapter + 1) : pos.book < books.length - 1 && go(pos.book + 1, 1));

  return (
    <section className="library-view bible-view" ref={topRef}>
      <div className="welcome-row"><div><h1>Biblia</h1><p>Reina-Valera 2009 · completa, para leer y consultar.</p></div></div>
      <div className="bible-tabs">
        <button className={tab === "read" ? "tool-btn on-tab" : "tool-btn"} onClick={() => { stopReading(); setTab("read"); }}><Icon name="book" size={15} /> Leer</button>
        <button className={tab === "ai" ? "tool-btn on-tab" : "tool-btn"} onClick={() => { stopReading(); setTab("ai"); }}><Icon name="spark" size={15} /> IA de la Biblia</button>
      </div>

      {tab === "ai" ? <BibleChat onToast={onToast} onOpen={open} /> : (
        <>
          <div className="bible-controls">
            <select value={pos.book} onChange={(e) => go(Number(e.target.value), 1)} aria-label="Libro">
              <optgroup label="Antiguo Testamento">{books.slice(0, 39).map((b) => <option key={b.index} value={b.index}>{b.name}</option>)}</optgroup>
              <optgroup label="Nuevo Testamento">{books.slice(39).map((b) => <option key={b.index} value={b.index}>{b.name}</option>)}</optgroup>
            </select>
            <select value={pos.chapter} onChange={(e) => go(pos.book, Number(e.target.value))} aria-label="Capítulo">
              {Array.from({ length: total }, (_, i) => <option key={i + 1} value={i + 1}>Capítulo {i + 1}</option>)}
            </select>
            <label className="quote-search-input"><Icon name="search" size={16} />
              <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar palabra o ir a (Juan 3:16)" aria-label="Buscar en la Biblia" /></label>
          </div>
          {results ? (
            <div className="bible-results">
              {results.length === 0 ? <p className="quote-hint">Sin resultados.</p> : <VerseList verses={results} onToast={onToast} onOpen={open} />}
            </div>
          ) : error ? <p className="quote-hint">{error}</p> : !chapter ? <div className="reader-loading"><span className="spinner" /> Cargando…</div> : (
            <article className="bible-chapter">
              <h2>{chapter.book} {chapter.chapter}</h2>
              <div className="bible-audio">
                <strong>Escuchar capítulo</strong>
                {speaking ? (
                  <button className="ghost-button" onClick={stopReading}>Detener lectura</button>
                ) : (
                  <button className="ask-cta" onClick={startReading}>Leer en voz alta</button>
                )}
                <span>Voz en español del dispositivo</span>
              </div>
              {chapter.verses.map((v) => {
                const id = `bible:${pos.book}:${chapter.chapter}`;
                const key = itemKey(id, v.verse);
                const fav = study.favorites.some((f) => f.key === key);
                const hl = study.highlights.find((h) => h.key === key);
                const textHighlights = study.highlights.filter((h) => h.messageId === id && h.number === v.verse && Number.isInteger(h.start) && Number.isInteger(h.end));
                const notes = study.notes.filter((n) => n.messageId === id && n.number === v.verse);
                const title = `${chapter.book} ${chapter.chapter}`;
                const item = { messageId: id, number: v.verse, title, text: v.text, bible: { book: pos.book, chapter: chapter.chapter, verse: v.verse } };
                return (
                  <div key={v.verse} id={`bv-${v.verse}`} className={`bible-verse${hl ? ` hl hl-${hl.color}` : ""}${focus === v.verse ? " focus" : ""}`}>
                    <p><sup>{v.verse}</sup>{" "}<HighlightableText text={v.text} highlights={textHighlights} canEdit={canEdit}
                      onSave={(start, end, color) => {
                        study.setTextHighlight(item, start, end, color);
                        onToast("Resaltado actualizado");
                      }} /></p>
                    <div className="paragraph-actions">
                      {canEdit && <>
                      {HIGHLIGHT_COLORS.map((c) => (
                        <button key={c} className={`swatch swatch-${c}${hl?.color === c ? " on" : ""}`} aria-label={`Resaltar ${COLOR_LABEL[c]}`} title={`Resaltar ${COLOR_LABEL[c]}`}
                          onClick={() => { study.setHighlight(item, c); onToast(hl?.color === c ? "Resaltado quitado" : "Resaltado"); }} />
                      ))}
                      {hl && <button className="mini" title="Quitar resaltado" aria-label="Quitar resaltado" onClick={() => { study.setHighlight(item, hl.color); onToast("Resaltado quitado"); }}><Icon name="trash" size={15} /></button>}
                      <button className={fav ? "mini on" : "mini"} title="Favorito" aria-label="Favorito" onClick={() => { study.toggleFavorite(item); onToast(fav ? "Quitado de favoritos" : "Agregado a favoritos"); }}><Icon name="star" size={15} filled={fav} /></button>
                      <button className="mini" title="Agregar nota" aria-label="Agregar nota" onClick={() => setComposer(v.verse)}><Icon name="note" size={15} /></button>
                      </>}
                      <button className="mini" title="Compartir versículo" aria-label="Compartir versículo"
                        onClick={async () => onToast(await shareContent({ title: `${title}:${v.verse} (RV 2009)`, text: `“${v.text}”` }))}><Icon name="share" size={15} /></button>
                    </div>
                    {notes.map((n) => <NoteItem key={n.id} note={n} study={study} onToast={onToast} canEdit={canEdit} />)}
                    {canEdit && composer === v.verse && (
                      <NoteComposer onCancel={() => setComposer(null)}
                        onSave={(t) => { study.saveNote({ ...item, quote: v.text }, t); setComposer(null); onToast("Nota guardada"); }} />
                    )}
                  </div>
                );
              })}
              <div className="bible-nav">
                <button className="ghost-button" onClick={prev} disabled={pos.book === 0 && pos.chapter === 1}><Icon name="back" size={15} /> Anterior</button>
                <button className="ghost-button" onClick={next} disabled={pos.book === books.length - 1 && pos.chapter === total}>Siguiente <Icon name="right" size={15} /></button>
              </div>
            </article>
          )}
        </>
      )}
    </section>
  );
}
