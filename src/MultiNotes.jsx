import { useEffect, useState } from "react";
import Icon from "./Icon.jsx";
import { shareContent } from "./useStudyData.js";

const newNote = () => ({ id: `m${Date.now()}`, title: "", text: "", quotes: [] });

const qLabel = (q) => (q.bible ? `${q.title}:${q.number} (RV 1960)` : `${q.title} · ${q.code}, párrafo ${q.number}`);
const bibleQuote = (v) => ({ id: "", code: `bible:${v.bookIndex}:${v.chapter}`, title: `${v.book} ${v.chapter}`, number: v.verse, text: v.text, bible: { book: v.bookIndex, chapter: v.chapter, verse: v.verse } });

function noteToText(note) {
  const quotes = note.quotes.map((q) => `“${q.text}” — ${qLabel(q)}`).join("\n\n");
  return [note.title, note.text, quotes].filter(Boolean).join("\n\n");
}

function QuoteSearch({ onAdd, added }) {
  const [source, setSource] = useState("messages");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) { setResults([]); setError(""); return undefined; }
    const controller = new AbortController();
    const timer = window.setTimeout(async () => {
      setLoading(true);
      setError("");
      try {
        const url = source === "bible" ? `/api/bible/search?q=${encodeURIComponent(term)}` : `/api/passages?q=${encodeURIComponent(term)}`;
        const res = await fetch(url, { signal: controller.signal });
        const data = await res.json();
        setResults(source === "bible" ? (data.verses || []).map(bibleQuote) : data.passages || []);
      } catch (e) {
        if (e.name !== "AbortError") setError("No se pudo buscar.");
      } finally {
        setLoading(false);
      }
    }, 350);
    return () => { controller.abort(); window.clearTimeout(timer); };
  }, [query, source]);

  return (
    <div className="quote-search">
      <div className="bible-tabs">
        <button type="button" className={source === "messages" ? "tool-btn on-tab" : "tool-btn"} onClick={() => { setSource("messages"); setResults([]); }}>Mensajes</button>
        <button type="button" className={source === "bible" ? "tool-btn on-tab" : "tool-btn"} onClick={() => { setSource("bible"); setResults([]); }}>Biblia</button>
      </div>
      <label className="quote-search-input">
        <Icon name="search" size={16} />
        <input value={query} onChange={(e) => setQuery(e.target.value)}
          placeholder={source === "bible" ? "Buscar versículo por palabra o referencia (ej. Juan 3:16)" : "Buscar una cita por tema o referencia (ej. 47-0412 19)"} aria-label="Buscar cita" />
      </label>
      {loading && <p className="quote-hint">Buscando…</p>}
      {error && <p className="quote-hint">{error}</p>}
      {!loading && query.trim().length >= 2 && !results.length && !error && <p className="quote-hint">Sin resultados.</p>}
      <div className="quote-results">
        {results.map((r) => {
          const isAdded = added.some((q) => q.code === r.code && q.number === r.number);
          return (
            <div className="quote-result" key={`${r.code}-${r.number}`}>
              <strong>{qLabel(r)}</strong>
              <p>{r.text.length > 320 ? `${r.text.slice(0, 320)}…` : r.text}</p>
              <button className="tool-btn" disabled={isAdded} onClick={() => onAdd(r)}>
                <Icon name={isAdded ? "check" : "note"} size={14} /><span>{isAdded ? "Añadida" : "Insertar cita"}</span>
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function MultiNotesView({ study, onToast, onOpen }) {
  const [draft, setDraft] = useState(null);

  if (draft) {
    const update = (patch) => setDraft((d) => ({ ...d, ...patch }));
    const canSave = draft.title.trim() || draft.text.trim() || draft.quotes.length;
    return (
      <section className="library-view study-view">
        <div className="welcome-row"><div><h1>{study.multiNotes.some((n) => n.id === draft.id) ? "Editar nota múltiple" : "Nueva nota múltiple"}</h1>
          <p>Escribe libremente y busca citas: su texto se inserta automáticamente.</p></div></div>
        <div className="multi-editor">
          <input className="multi-title" value={draft.title} onChange={(e) => update({ title: e.target.value })} placeholder="Título (opcional)" />
          <textarea value={draft.text} onChange={(e) => update({ text: e.target.value })} rows={6} placeholder="Escribe tu nota…" />
          {draft.quotes.length > 0 && (
            <div className="multi-quotes">
              {draft.quotes.map((q) => (
                <blockquote key={`${q.code}-${q.number}`} className="multi-quote">
                  <p>“{q.text}”</p>
                  <footer>{qLabel(q)}
                    <button onClick={() => update({ quotes: draft.quotes.filter((x) => x !== q) })}><Icon name="trash" size={13} /> Quitar</button>
                  </footer>
                </blockquote>
              ))}
            </div>
          )}
          <QuoteSearch added={draft.quotes} onAdd={(r) => update({ quotes: [...draft.quotes, { id: r.id, code: r.code, title: r.title, number: r.number, text: r.text, ...(r.bible ? { bible: r.bible } : {}) }] })} />
          <div className="note-composer"><div>
            <button className="ghost-button" onClick={() => setDraft(null)}>Cancelar</button>
            <button className="ask-cta" disabled={!canSave} onClick={() => { study.saveMultiNote(draft); setDraft(null); onToast("Nota múltiple guardada"); }}>
              <Icon name="check" size={15} /> Guardar nota</button>
          </div></div>
        </div>
      </section>
    );
  }

  return (
    <section className="library-view study-view">
      <div className="welcome-row"><div><h1>Nota múltiple</h1><p>Combina tus apuntes con citas de los mensajes y de la Biblia.</p></div>
        <div className="head-actions">
          {study.multiNotes.length > 0 && (
            <button className="ghost-button danger" onClick={() => { if (window.confirm("¿Eliminar todas las notas múltiples?")) { study.clearAll("multiNotes"); onToast("Todo eliminado"); } }}>
              <Icon name="trash" size={15} /> Eliminar todo
            </button>
          )}
          <button className="ask-cta" onClick={() => setDraft(newNote())}><Icon name="note" size={16} /> Nueva nota múltiple</button>
        </div></div>
      {study.multiNotes.length === 0 ? (
        <div className="empty-study"><Icon name="note" size={26} /><p>Aún no tienes notas múltiples.</p></div>
      ) : (
        <div className="study-list">
          {study.multiNotes.map((n) => (
            <div className="study-item" key={n.id}>
              {n.title && <strong>{n.title}</strong>}
              {n.text && <p className="multi-text">{n.text}</p>}
              {n.quotes.map((q) => (
                <blockquote key={`${q.code}-${q.number}`} className="multi-quote">
                  <p>“{q.text}”</p>
                  <footer><button className="note-source" onClick={() => (q.bible ? onOpen(q.bible) : onOpen(q.id, q.number))}>{qLabel(q)}</button></footer>
                </blockquote>
              ))}
              <div className="note-actions">
                <button onClick={() => setDraft({ ...n })}><Icon name="edit" size={14} /> Editar</button>
                <button onClick={async () => onToast(await shareContent({ title: n.title || "Nota múltiple", text: noteToText(n) }))}><Icon name="share" size={14} /> Compartir</button>
                <button onClick={() => { study.deleteMultiNote(n.id); onToast("Nota eliminada"); }}><Icon name="trash" size={14} /> Eliminar</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
