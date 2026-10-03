import { useEffect, useState } from "react";
import Icon from "./Icon.jsx";
import { HIGHLIGHT_COLORS, itemKey, shareContent } from "./useStudyData.js";

const COLOR_LABEL = { yellow: "Amarillo", green: "Verde", blue: "Azul", pink: "Rosa" };

export function NoteComposer({ initial = "", onSave, onCancel, placeholder = "Escribe tu comentario…" }) {
  const [text, setText] = useState(initial);
  return (
    <form className="note-composer" onSubmit={(e) => { e.preventDefault(); onSave(text); }}>
      <textarea autoFocus value={text} onChange={(e) => setText(e.target.value)} placeholder={placeholder} rows={3} />
      <div>
        <button type="button" className="ghost-button" onClick={onCancel}>Cancelar</button>
        <button type="submit" className="ask-cta" disabled={!text.trim()}><Icon name="check" size={15} /> Guardar nota</button>
      </div>
    </form>
  );
}

export function NoteItem({ note, study, onToast, showSource, onOpen }) {
  const [editing, setEditing] = useState(false);
  return (
    <div className="note-item">
      {showSource && (
        <button className="note-source" onClick={onOpen}>
          {note.title}{note.number ? ` · ${note.bible ? "versículo" : "párrafo"} ${note.number}` : ""}
        </button>
      )}
      {note.quote && <blockquote>{note.quote}</blockquote>}
      {editing ? (
        <NoteComposer initial={note.text} onCancel={() => setEditing(false)}
          onSave={(t) => { study.saveNote(null, t, note.id); setEditing(false); onToast("Nota actualizada"); }} />
      ) : (
        <p>{note.text}</p>
      )}
      {!editing && (
        <div className="note-actions">
          <button onClick={() => setEditing(true)}><Icon name="edit" size={14} /> Editar</button>
          <button onClick={async () => onToast(await shareContent({ title: `${note.title}${note.number ? `, ${note.bible ? "versículo" : "párrafo"} ${note.number}` : ""}`, text: `${note.quote ? `“${note.quote}”\n` : ""}Nota: ${note.text}` }))}><Icon name="share" size={14} /> Compartir</button>
          <button onClick={() => { study.deleteNote(note.id); onToast("Nota eliminada"); }}><Icon name="trash" size={14} /> Eliminar</button>
        </div>
      )}
    </div>
  );
}

export function MessageReader({ message, loading, error, onRetry, jumpTo, onBack, onAsk, study, onToast }) {
  const [composer, setComposer] = useState(null);

  useEffect(() => {
    if (!message || !jumpTo) return;
    const timer = window.setTimeout(() => document.getElementById(`p-${jumpTo}`)?.scrollIntoView({ block: "center", behavior: "smooth" }), 80);
    return () => window.clearTimeout(timer);
  }, [message, jumpTo]);

  useEffect(() => { setComposer(null); }, [message?.id]);

  if (loading) return <div className="reader-loading"><span className="spinner" /> Cargando mensaje…</div>;
  if (error) return (
    <div className="reader-loading">
      <div>
        <p>{error}</p>
        <button className="ghost-button" onClick={onRetry}>Reintentar</button>{" "}
        <button className="ghost-button" onClick={onBack}>Volver</button>
      </div>
    </div>
  );
  if (!message) return null;

  const meta = [message.date, message.location].filter(Boolean).join(" · ");
  const paragraphs = message.paragraphs || [];
  const wholeKey = itemKey(message.id, 0);
  const wholeFav = study.favorites.some((f) => f.key === wholeKey);
  const messageItem = { messageId: message.id, number: 0, title: message.title, text: "" };
  const messageNotes = study.notes.filter((n) => n.messageId === message.id && !n.number);

  return (
    <article className="reader">
      <div className="reader-toolbar">
        <button className="ghost-button" onClick={onBack}><Icon name="back" size={15} /> Mensajes</button>
        <div className="toolbar-actions">
          <button className={wholeFav ? "tool-btn on" : "tool-btn"} onClick={() => { study.toggleFavorite(messageItem); onToast(wholeFav ? "Quitado de favoritos" : "Agregado a favoritos"); }}>
            <Icon name="star" size={16} filled={wholeFav} /><span>Favorito</span>
          </button>
          <button className="tool-btn" onClick={() => setComposer({ number: 0 })}><Icon name="note" size={16} /><span>Nota</span></button>
          <button className="tool-btn" onClick={async () => onToast(await shareContent({ title: `${message.title} (${message.id})`, text: `Mensaje: ${message.title}${meta ? `\n${meta}` : ""}` }))}>
            <Icon name="share" size={16} /><span>Compartir</span>
          </button>
        </div>
      </div>

      <header className="reader-heading">
        <h1>{message.title}</h1>
        <div className="reader-meta">{message.id}{meta ? ` · ${meta}` : ""} · {paragraphs.length} párrafos</div>
        <button className="ask-cta" onClick={() => onAsk("")}><Icon name="spark" size={17} /> Consultar este mensaje</button>
      </header>

      {message.audioUrl && (
        <section className="message-audio" aria-label="Audio del mensaje">
          <strong>Escuchar mensaje</strong>
          <audio controls preload="none" src={message.audioUrl}>
            Tu navegador no puede reproducir este audio.
          </audio>
        </section>
      )}

      {(composer?.number === 0 || messageNotes.length > 0) && (
        <div className="notes-block">
          {messageNotes.map((n) => <NoteItem key={n.id} note={n} study={study} onToast={onToast} />)}
          {composer?.number === 0 && (
            <NoteComposer onCancel={() => setComposer(null)}
              onSave={(t) => { study.saveNote({ messageId: message.id, number: 0, title: message.title, quote: "" }, t); setComposer(null); onToast("Nota guardada"); }} />
          )}
        </div>
      )}

      <div className="paragraphs">
        {paragraphs.map((p) => {
          const key = itemKey(message.id, p.number);
          const fav = study.favorites.some((f) => f.key === key);
          const hl = study.highlights.find((h) => h.key === key);
          const notes = study.notes.filter((n) => n.messageId === message.id && n.number === p.number);
          const item = { messageId: message.id, number: p.number, title: message.title, text: p.text };
          return (
            <section className={`paragraph${hl ? ` hl hl-${hl.color}` : ""}${jumpTo === p.number ? " jumped" : ""}`} id={`p-${p.number}`} key={p.number}>
              <span className="paragraph-number">{p.number}</span>
              <div className="paragraph-body">
                <p>{p.text}</p>
                <div className="paragraph-actions">
                  {HIGHLIGHT_COLORS.map((c) => (
                    <button key={c} className={`swatch swatch-${c}${hl?.color === c ? " on" : ""}`} aria-label={`Resaltar ${COLOR_LABEL[c]}`} title={`Resaltar ${COLOR_LABEL[c]}`}
                      onClick={() => { study.setHighlight(item, c); onToast(hl?.color === c ? "Resaltado quitado" : "Resaltado"); }} />
                  ))}
                  {hl && (
                    <button className="mini" title="Quitar resaltado" aria-label="Quitar resaltado"
                      onClick={() => { study.setHighlight(item, hl.color); onToast("Resaltado quitado"); }}><Icon name="trash" size={15} /></button>
                  )}
                  <button className={fav ? "mini on" : "mini"} title="Favorito" aria-label="Favorito"
                    onClick={() => { study.toggleFavorite(item); onToast(fav ? "Quitado de favoritos" : "Agregado a favoritos"); }}>
                    <Icon name="star" size={15} filled={fav} />
                  </button>
                  <button className="mini" title="Agregar nota" aria-label="Agregar nota" onClick={() => setComposer({ number: p.number })}><Icon name="note" size={15} /></button>
                  <button className="mini" title="Compartir" aria-label="Compartir"
                    onClick={async () => onToast(await shareContent({ title: `${message.title}, ${message.id}, párrafo ${p.number}`, text: `“${p.text}”` }))}>
                    <Icon name="share" size={15} />
                  </button>
                </div>
                {notes.map((n) => <NoteItem key={n.id} note={n} study={study} onToast={onToast} />)}
                {composer?.number === p.number && (
                  <NoteComposer onCancel={() => setComposer(null)}
                    onSave={(t) => { study.saveNote({ messageId: message.id, number: p.number, title: message.title, quote: p.text }, t); setComposer(null); onToast("Nota guardada"); }} />
                )}
              </div>
            </section>
          );
        })}
      </div>
    </article>
  );
}

const TITLES = {
  favorites: ["Favoritos", "Mensajes, párrafos y versículos que guardaste."],
  notes: ["Notas", "Tus comentarios, fijos en cada pasaje."],
  highlights: ["Resaltados", "Pasajes que marcaste mientras leías."],
};

export function StudyListView({ kind, study, onOpen, onToast }) {
  const [title, subtitle] = TITLES[kind];
  const items = study[kind];
  return (
    <section className="library-view study-view">
      <div className="welcome-row"><div><h1>{title}</h1><p>{subtitle}</p></div>
        {items.length > 0 && (
          <button className="ghost-button danger" onClick={() => { if (window.confirm(`¿Eliminar todos los elementos de ${title}?`)) { study.clearAll(kind); onToast("Todo eliminado"); } }}>
            <Icon name="trash" size={15} /> Eliminar todo
          </button>
        )}
      </div>
      {items.length === 0 ? (
        <div className="empty-study"><Icon name={kind === "notes" ? "note" : kind === "favorites" ? "star" : "highlight"} size={26} />
          <p>Aún no tienes {title.toLowerCase()}. Ábrelos desde cualquier mensaje o versículo.</p></div>
      ) : (
        <div className="study-list">
          {items.map((it) => {
            const open = () => (it.bible ? onOpen(it.bible) : onOpen(it.messageId, it.number || null));
            if (kind === "notes") return <NoteItem key={it.id} note={it} study={study} onToast={onToast} showSource onOpen={open} />;
            const ref = it.number ? `${it.title} · ${it.bible ? "versículo" : "párrafo"} ${it.number}` : it.title;
            return (
              <div className={`study-item${kind === "highlights" ? ` hl hl-${it.color}` : ""}`} key={it.key}>
                <button className="note-source" onClick={open}>{ref}</button>
                {it.text && <p>{it.text}</p>}
                <div className="note-actions">
                  <button onClick={open}><Icon name="arrow" size={14} /> Abrir</button>
                  <button onClick={async () => onToast(await shareContent({ title: `${ref}`, text: it.text ? `“${it.text}”` : it.title }))}><Icon name="share" size={14} /> Compartir</button>
                  <button onClick={() => { kind === "favorites" ? study.toggleFavorite(it) : study.setHighlight(it, it.color); onToast("Eliminado"); }}><Icon name="trash" size={14} /> Quitar</button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
