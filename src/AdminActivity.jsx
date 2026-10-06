import { useCallback, useEffect, useState } from "react";
import Icon from "./Icon.jsx";

const COLLECTION_LABELS = { favorites: "Favoritos", notes: "Notas", highlights: "Resaltados", multiNotes: "Nota múltiple" };

function formatDate(value) {
  if (!value) return "sin fecha";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "sin fecha" : date.toLocaleString("es", { dateStyle: "medium", timeStyle: "short" });
}

function initials(user) {
  const source = user.name || user.email || user.userId || "?";
  return source.replace(/[^A-Za-z0-9@. ]/g, "").split(/[\s@.]+/).filter(Boolean).slice(0, 2)
    .map((part) => part[0].toUpperCase()).join("") || "?";
}

function ActivityItems({ collection, items }) {
  return (
    <div className="admin-group">
      <h3><Icon name={collection === "favorites" ? "star" : collection === "notes" ? "note" : collection === "highlights" ? "highlight" : "edit"} size={14} /> {COLLECTION_LABELS[collection]}<span>{items.length}</span></h3>
      <ul className="admin-items">
        {items.map((item, index) => (
          <li key={index} className={collection === "highlights" ? `admin-item hl-dot-${item.color}` : "admin-item"}>
            <span className="admin-item-head">
              <strong>{collection === "multiNotes" ? item.title || "Sin título" : item.source || "Sin referencia"}</strong>
              <small>{formatDate(item.updatedAt || item.createdAt)}</small>
            </span>
            {collection === "highlights" && <em className="admin-color">{item.color === "yellow" ? "Amarillo" : item.color === "green" ? "Verde" : item.color === "blue" ? "Azul" : "Rosa"}</em>}
            {item.quote && <blockquote>“{item.quote}”</blockquote>}
            {item.text && <p>{item.text}</p>}
            {collection === "multiNotes" && item.quotes > 0 && <small className="admin-quotes">{item.quotes} cita{item.quotes === 1 ? "" : "s"} insertada{item.quotes === 1 ? "" : "s"}</small>}
          </li>
        ))}
      </ul>
    </div>
  );
}

function UserCard({ user }) {
  const counts = [
    ["Favoritos", user.counts.favorites],
    ["Notas", user.counts.notes],
    ["Nota múltiple", user.counts.multiNotes],
    ["Resaltados", user.counts.highlights],
    ["Mensajes de chat", user.counts.chat],
  ];
  const groups = Object.keys(COLLECTION_LABELS).filter((collection) => user.items[collection]?.length);
  return (
    <article className="user-card">
      <details className="user-details">
        <summary className="user-head">
          <span className="user-avatar">
            {user.picture ? <img src={user.picture} alt="" /> : initials(user)}
          </span>
          <span className="user-main">
            <strong>{user.name || user.email || "Cuenta de Google"}</strong>
            <small>{user.email || `Identificador ${user.userId}`}</small>
          </span>
          <span className="user-counts">
            {counts.map(([label, value]) => (
              <span className="admin-chip" key={label}><b>{value}</b>{label}</span>
            ))}
          </span>
          <span className="user-toggle"><Icon name="right" size={16} /></span>
        </summary>
        <div className="user-body">
          <p className="user-meta">
            Último acceso: {formatDate(user.lastLoginAt)} · Última actividad: {formatDate(user.lastActivityAt)}
            {user.registeredAt ? ` · Se registró: ${formatDate(user.registeredAt)}` : ""}
          </p>
          {!user.registered && (
            <p className="user-warning">Guardó datos en la página pero todavía no aparece en la tabla <code>google_users</code>. Su fila se crea en cuanto vuelva a iniciar sesión.</p>
          )}
          {user.chat && (
            <div className="admin-group">
              <h3><Icon name="chat" size={14} /> Chat con IA<span>{user.counts.chat}</span></h3>
              <ul className="admin-items">
                <li className="admin-item">
                  <span className="admin-item-head"><strong>{user.counts.chat} mensaje{user.counts.chat === 1 ? "" : "s"} guardados</strong><small>{formatDate(user.chat.updatedAt)}</small></span>
                  {user.chat.lastQuestion && <blockquote>Última pregunta: “{user.chat.lastQuestion}”</blockquote>}
                </li>
              </ul>
            </div>
          )}
          {groups.map((collection) => <ActivityItems key={collection} collection={collection} items={user.items[collection]} />)}
          {!groups.length && !user.chat && <p className="admin-empty">Esta cuenta aún no guardó favoritos, notas, resaltados ni conversaciones.</p>}
        </div>
      </details>
    </article>
  );
}

export function AdminActivityView() {
  const [state, setState] = useState({ loading: true, error: "", data: null });

  const load = useCallback(async () => {
    setState((current) => ({ ...current, loading: true, error: "" }));
    try {
      const response = await fetch("/api/admin/activity");
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || "No se pudo cargar la actividad de los usuarios.");
      setState({ loading: false, error: "", data });
    } catch (error) {
      setState({ loading: false, error: error.message, data: null });
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const { totals, users } = state.data || { totals: null, users: [] };

  return (
    <section className="admin-view">
      <div className="settings-intro">
        <p className="eyebrow">ADMINISTRACIÓN</p>
        <h1>Usuarios y actividad</h1>
        <p>Quien inicia sesión con Google y qué guardó en la página. Los mismos datos viven en tu Supabase: tabla <code>google_users</code> (usuarios) y <code>shared_page_state</code> (favoritos, notas, resaltados y chats).</p>
      </div>

      <div className="admin-toolbar">
        <span className="admin-updated">{state.data ? `Actualizado ${formatDate(state.data.generatedAt)}` : "Cargando información de Supabase…"}</span>
        <button className="ghost-button" onClick={load} disabled={state.loading}><Icon name="spark" size={15} /> {state.loading ? "Cargando…" : "Actualizar"}</button>
      </div>

      {state.error && <div className="inline-error">{state.error} <button onClick={load}>Reintentar</button></div>}

      {totals && (
        <div className="stat-strip">
          <div><strong>{totals.users.toLocaleString("es")}</strong><span>usuarios</span></div>
          <i />
          <div><strong>{totals.favorites.toLocaleString("es")}</strong><span>favoritos</span></div>
          <i />
          <div><strong>{(totals.notes + totals.multiNotes).toLocaleString("es")}</strong><span>notas</span></div>
          <i />
          <div><strong>{totals.highlights.toLocaleString("es")}</strong><span>resaltados</span></div>
          <i />
          <div><strong>{totals.chat.toLocaleString("es")}</strong><span>mensajes de chat</span></div>
        </div>
      )}

      {state.loading && !state.data && <div className="loading-line"><span /> Consultando Supabase…</div>}

      {!state.loading && !state.error && users.length === 0 && (
        <div className="empty-study">
          <Icon name="settings" size={24} />
          <strong>Todavía no hay usuarios</strong>
          <span>Cuando alguien entre con “Continuar con Google” aparecerá aquí y en <code>google_users</code>.</span>
        </div>
      )}

      <div className="user-list">
        {users.map((user) => <UserCard key={user.userId} user={user} />)}
      </div>
    </section>
  );
}
