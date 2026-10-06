import { useCallback, useEffect, useRef, useState } from "react";
import Icon from "./Icon.jsx";
import { AdminActivityView } from "./AdminActivity.jsx";
import { BibleView } from "./Bible.jsx";
import { MultiNotesView } from "./MultiNotes.jsx";
import { MessageReader, StudyListView } from "./StudyViews.jsx";
import { conversationToText, shareContent, useStudyData } from "./useStudyData.js";

const emptyPage = { total: 0, sermons: [] };
const initialChat = [
  {
    role: "assistant",
    text: "Hola. Puedo ayudarte a explorar los mensajes disponibles. Pregúntame sobre un tema y te mostraré los pasajes que fundamentan la respuesta.",
    sources: [],
  },
];

async function api(path, options) {
  const response = await fetch(path, options);
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || "No se pudo completar la solicitud.");
  return data;
}

function readSavedChat(key = "branham-chat:public") {
  try {
    const saved = JSON.parse(localStorage.getItem(key) || "[]");
    return saved.length ? saved : initialChat;
  } catch {
    return initialChat;
  }
}

function readPreference(key, fallback, choices) {
  try {
    const value = localStorage.getItem(key);
    return choices.includes(value) ? value : fallback;
  } catch {
    return fallback;
  }
}

function App() {
  const [section, setSection] = useState("library");
  const [authSession, setAuthSession] = useState({ configured: false, authenticated: false, isAdmin: false, user: null, loading: true });
  const [theme, setTheme] = useState(() => readPreference("branham-theme", "light", ["light", "dark"]));
  const [textSize, setTextSize] = useState(() => readPreference("branham-text-size", "medium", ["small", "medium", "large"]));
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(emptyPage);
  const [loadingList, setLoadingList] = useState(true);
  const [listError, setListError] = useState("");
  const [selectedId, setSelectedId] = useState("");
  const [selectedMessage, setSelectedMessage] = useState(null);
  const [selectedError, setSelectedError] = useState("");
  const [selectedParagraph, setSelectedParagraph] = useState(null);
  const [loadingMessage, setLoadingMessage] = useState(false);
  const [chat, setChat] = useState(readSavedChat);
  const [chatSyncError, setChatSyncError] = useState("");
  const [draft, setDraft] = useState("");
  const [chatError, setChatError] = useState("");
  const [sending, setSending] = useState(false);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const accountId = authSession.user?.userId || "";
  const chatStorageKey = accountId ? `branham-chat:${accountId}` : "branham-chat:public";
  const study = useStudyData(accountId);
  const [bibleTarget, setBibleTarget] = useState(null);
  const [toast, setToast] = useState("");
  const showToast = useCallback((text) => {
    if (!text) return;
    setToast(text);
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => setToast(""), 2000);
  }, []);
  const chatEndRef = useRef(null);
  const inputRef = useRef(null);
  const chatReadyRef = useRef(false);
  const chatPendingRef = useRef(0);
  const chatSnapshotRef = useRef("");
  const chatWriteVersionRef = useRef(0);
  const chatWriteQueue = useRef(Promise.resolve());
  const chatLatestRef = useRef(chat);
  const accountIdRef = useRef(accountId);
  accountIdRef.current = accountId;

  useEffect(() => {
    let cancelled = false;
    const query = new URLSearchParams(window.location.search);
    const authOutcome = query.get("auth");
    const authError = query.get("auth_error");
    if (authOutcome || authError) {
      window.history.replaceState({}, "", window.location.pathname);
      if (authOutcome === "success") showToast("Sesión de Google iniciada");
      if (authError === "not_configured") showToast("El inicio de sesión de Google aún no está configurado.");
      if (authError === "cancelled") showToast("Se canceló el inicio de sesión.");
      if (authError === "google" || authError === "invalid_state") showToast("No se pudo verificar la cuenta de Google. Inténtalo de nuevo.");
    }
    api("/api/auth/session")
      .then((session) => {
        if (!cancelled) setAuthSession({ ...session, loading: false });
      })
      .catch((error) => {
        if (!cancelled) {
          setAuthSession({ configured: false, authenticated: false, isAdmin: false, user: null, loading: false });
          showToast(error.message);
        }
      });
    return () => { cancelled = true; };
  }, [showToast]);

  useEffect(() => {
    const handleExpired = () => {
      setAuthSession((session) => ({ ...session, authenticated: false, isAdmin: false, user: null }));
      setSection((current) => (current === "users" ? "library" : current));
      showToast("La sesión terminó. Vuelve a entrar con Google para guardar tus cambios.");
    };
    window.addEventListener("google-session-expired", handleExpired);
    return () => window.removeEventListener("google-session-expired", handleExpired);
  }, [showToast]);

  function signIn() {
    window.location.assign("/api/auth/google");
  }

  async function signOut() {
    try {
      await api("/api/auth/session", { method: "DELETE" });
      setAuthSession((session) => ({ ...session, authenticated: false, isAdmin: false, user: null }));
      setSection((current) => (current === "users" ? "library" : current));
      showToast("Sesión cerrada");
    } catch (error) {
      showToast(error.message);
    }
  }

  const enqueueChatSave = useCallback((messages) => {
    const ownerId = accountIdRef.current;
    if (!ownerId) return;
    const snapshot = JSON.stringify(messages);
    chatPendingRef.current += 1;
    chatWriteQueue.current = chatWriteQueue.current.then(async () => {
      try {
        await api("/api/shared-state/chat/global", {
          method: "PUT",
          headers: { "Content-Type": "application/json", "X-Account-Id": ownerId },
          body: JSON.stringify({ payload: messages }),
        });
        chatSnapshotRef.current = snapshot;
        chatWriteVersionRef.current += 1;
        setChatSyncError("");
      } catch (error) {
        setChatSyncError(error.message);
        if (error.message.includes("Google") || error.message.includes("HTTP 401")) {
          window.dispatchEvent(new Event("google-session-expired"));
        }
        window.setTimeout(() => {
          if (accountIdRef.current === ownerId && chatReadyRef.current
            && chatSnapshotRef.current !== snapshot && JSON.stringify(chatLatestRef.current) === snapshot) {
            enqueueChatSave(chatLatestRef.current);
          }
        }, 5000);
      } finally {
        chatPendingRef.current -= 1;
      }
    });
  }, []);

  useEffect(() => {
    let cancelled = false;
    let initialized = false;
    chatReadyRef.current = false;
    chatSnapshotRef.current = "";
    setChat(readSavedChat(chatStorageKey));
    setChatSyncError("");
    async function synchronizeChat() {
      const versionAtRequest = chatWriteVersionRef.current;
      try {
        const result = await api("/api/shared-state?collection=chat");
        if (cancelled) return;
        if (initialized && (versionAtRequest !== chatWriteVersionRef.current || chatPendingRef.current > 0)) return;
        const remoteEntry = result.entries?.find((entry) => entry.item_key === "global");
        const remote = remoteEntry?.payload || initialChat;
        const snapshot = JSON.stringify(remote);
        if (!initialized) {
          initialized = true;
          const localChat = readSavedChat(chatStorageKey);
          chatSnapshotRef.current = snapshot;
          chatReadyRef.current = true;
          if (accountId && remoteEntry?.owner_id !== accountId && localChat.length > 1) {
            setChat(localChat);
            enqueueChatSave(localChat);
          } else setChat(remote);
        } else if (!chatPendingRef.current && snapshot !== chatSnapshotRef.current) {
          chatSnapshotRef.current = snapshot;
          setChat(remote);
        }
        setChatSyncError("");
      } catch (error) {
        if (!cancelled) setChatSyncError(error.message);
      }
    }
    synchronizeChat();
    const interval = accountId ? window.setInterval(synchronizeChat, 5000) : null;
    return () => {
      cancelled = true;
      if (interval !== null) window.clearInterval(interval);
    };
  }, [accountId, chatStorageKey, enqueueChatSave]);

  const loadMessages = useCallback(async (search = "", offset = 0, append = false) => {
    setLoadingList(true);
    setListError("");
    try {
      const params = new URLSearchParams({ offset: String(offset), limit: "40" });
      if (search.trim()) params.set("search", search.trim());
      const data = await api(`/api/sermons?${params}`);
      setPage((current) => ({
        total: data.total,
        sermons: append ? [...current.sermons, ...data.sermons] : data.sermons,
      }));
    } catch (error) {
      setListError(error.message);
    } finally {
      setLoadingList(false);
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => loadMessages(query), query ? 250 : 0);
    return () => window.clearTimeout(timer);
  }, [query, loadMessages]);

  useEffect(() => {
    chatLatestRef.current = chat;
    try { localStorage.setItem(chatStorageKey, JSON.stringify(chat)); } catch { /* local backup unavailable */ }
    chatEndRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
    if (!accountId || !chatReadyRef.current) return;
    const snapshot = JSON.stringify(chat);
    if (snapshot === chatSnapshotRef.current) return;
    enqueueChatSave(chat);
  }, [chat, enqueueChatSave, accountId, chatStorageKey]);

  useEffect(() => {
    if (study.syncError) showToast(study.syncError);
  }, [study.syncError, showToast]);

  useEffect(() => {
    if (chatSyncError) showToast(chatSyncError);
  }, [chatSyncError, showToast]);

  useEffect(() => {
    try {
      localStorage.setItem("branham-theme", theme);
      localStorage.setItem("branham-text-size", textSize);
    } catch {
      // Preferences still apply for the current session when storage is unavailable.
    }
  }, [theme, textSize]);

  async function openMessage(id, paragraphNumber = null) {
    setSelectedId(id);
    setSelectedError("");
    setSelectedParagraph(paragraphNumber);
    setLoadingMessage(true);
    setSelectedMessage(null);
    try {
      setSelectedMessage(await api(`/api/sermons/${encodeURIComponent(id)}`));
    } catch (error) {
      setSelectedError(error.message);
    } finally {
      setLoadingMessage(false);
    }
  }

  async function sendMessage(event, override, baseChat = chat) {
    event?.preventDefault();
    const question = (override ?? draft).trim();
    if (!question || sending) return;

    const previous = baseChat.filter((message) => message.role !== "assistant" || message.sources?.length)
      .slice(-8)
      .map((message) => ({ role: message.role === "assistant" ? "model" : "user", text: message.text }));
    if (override === undefined) setDraft("");
    setChatError("");
    setSending(true);
    setChat([...baseChat, { role: "user", text: question, sources: [] }]);
    try {
      const result = await api("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, history: previous }),
      });
      setChat((messages) => [...messages, {
        role: "assistant",
        text: result.answer,
        sources: result.sources ?? [],
      }]);
    } catch (error) {
      setChatError(error.message);
    } finally {
      setSending(false);
      inputRef.current?.focus();
    }
  }

  function editChatMessage(index, text, resend) {
    const body = text.trim();
    if (!body) return;
    if (resend) {
      sendMessage(undefined, body, chat.slice(0, index));
    } else {
      setChat((messages) => messages.map((m, i) => (i === index ? { ...m, text: body } : m)));
    }
  }

  function clearChat() {
    setChat(initialChat);
    setChatError("");
    localStorage.removeItem(chatStorageKey);
  }

  function navigate(next) {
    setSection(next);
    setSelectedId("");
    setSelectedMessage(null);
    setMobileNavOpen(false);
  }

  return (
    <div className="app-shell" data-theme={theme} data-text-size={textSize}>
      <aside className={`sidebar ${mobileNavOpen ? "sidebar-open" : ""}`}>
        <button className="brand" onClick={() => navigate("library")} aria-label="Ir al inicio">
          <span className="brand-mark"><Icon name="book" size={22} /></span>
          <span><strong>Palabra</strong><small>Biblioteca de mensajes</small></span>
        </button>
        <p className="nav-label">BIBLIOTECA</p>
        <nav className="main-nav" aria-label="Navegación principal">
          <button className={section === "library" ? "nav-item active" : "nav-item"} onClick={() => navigate("library")}>
            <Icon name="book" /><span>Mensajes</span><span className="nav-count">{page.total || "…"}</span>
          </button>
          <button className={section === "bible" ? "nav-item active" : "nav-item"} onClick={() => navigate("bible")}>
            <Icon name="book" /><span>Biblia</span><span className="nav-count">66</span>
          </button>
          <button className={section === "chat" ? "nav-item active" : "nav-item"} onClick={() => navigate("chat")}>
            <Icon name="chat" /><span>Chat con IA</span><span className="ai-dot" />
          </button>
          <button className={section === "favorites" ? "nav-item active" : "nav-item"} onClick={() => navigate("favorites")}>
            <Icon name="star" /><span>Favoritos</span><span className="nav-count">{study.favorites.length}</span>
          </button>
          <button className={section === "notes" ? "nav-item active" : "nav-item"} onClick={() => navigate("notes")}>
            <Icon name="note" /><span>Notas</span><span className="nav-count">{study.notes.length}</span>
          </button>
          <button className={section === "multinotes" ? "nav-item active" : "nav-item"} onClick={() => navigate("multinotes")}>
            <Icon name="edit" /><span>Nota múltiple</span><span className="nav-count">{study.multiNotes.length}</span>
          </button>
          <button className={section === "highlights" ? "nav-item active" : "nav-item"} onClick={() => navigate("highlights")}>
            <Icon name="highlight" /><span>Resaltados</span><span className="nav-count">{study.highlights.length}</span>
          </button>
          <button className={section === "settings" ? "nav-item active" : "nav-item"} onClick={() => navigate("settings")}>
            <Icon name="settings" /><span>Configuración</span>
          </button>
          {authSession.isAdmin && (
            <button className={section === "users" ? "nav-item active" : "nav-item"} onClick={() => navigate("users")}>
              <Icon name="users" /><span>Usuarios</span>
            </button>
          )}
        </nav>
        <div className="sidebar-bottom">
          <div className="source-card">
            <span className="source-icon"><Icon name="spark" size={16} /></span>
            <strong>Respuestas con fuentes</strong>
            <p>El chat consulta los pasajes de esta biblioteca.</p>
          </div>
          <p className="sidebar-caption">Catálogo local · Español</p>
        </div>
      </aside>

      {mobileNavOpen && <button className="nav-scrim" onClick={() => setMobileNavOpen(false)} aria-label="Cerrar menú" />}

      <main className="main-area">
        <header className="topbar">
          <button className="icon-button mobile-menu" onClick={() => setMobileNavOpen(true)} aria-label="Abrir menú">
            <Icon name="menu" />
          </button>
          <div className="breadcrumbs"><span>Biblioteca</span><Icon name="right" size={14} /><strong>{section === "chat" ? "Chat con IA" : section === "settings" ? "Configuración" : section === "users" ? "Usuarios" : section === "favorites" ? "Favoritos" : section === "notes" ? "Notas" : section === "highlights" ? "Resaltados" : section === "multinotes" ? "Nota múltiple" : section === "bible" ? "Biblia" : selectedMessage?.title || "Mensajes"}</strong></div>
          <div className="topbar-meta"><span className="status-dot" /> Catálogo disponible</div>
          <button className="session-button" disabled={authSession.loading}
            title={authSession.user?.email ? `Cuenta Google: ${authSession.user.email}` : "Inicia sesión con una cuenta de Google"}
            onClick={() => authSession.authenticated ? signOut() : signIn()}>
            {authSession.authenticated ? "Cerrar sesión" : authSession.loading ? "Verificando…" : "Continuar con Google"}
          </button>
        </header>

        <aside className="shared-data-notice" role="note">
          La lectura es pública. Al iniciar sesión con Google puedes guardar y editar tus propios favoritos, notas, resaltados y conversaciones; solo tu cuenta los puede cambiar.
        </aside>

        {section === "library" && (
          selectedId ? (
            <MessageReader
              message={selectedMessage}
              loading={loadingMessage}
              error={selectedError}
              onRetry={() => openMessage(selectedId)}
              jumpTo={selectedParagraph}
              study={study}
              canEdit={study.canEdit}
              onToast={showToast}
              onBack={() => { setSelectedId(""); setSelectedMessage(null); }}
              onAsk={(text) => {
                setSection("chat");
                setDraft(text ? `¿Qué enseña este mensaje sobre ${text}?` : `Ayúdame a entender el mensaje ${selectedId}.`);
                window.setTimeout(() => inputRef.current?.focus(), 50);
              }}
            />
          ) : (
            <section className="library-view">
              <div className="welcome-row">
                <div>
                  <p className="eyebrow">BIBLIOTECA DE ESTUDIO</p>
                  <h1>Mensajes para explorar.</h1>
                  <p className="welcome-copy">Busca un tema, abre un mensaje y estudia sus pasajes.</p>
                </div>
                <button className="ask-cta" onClick={() => navigate("chat")}><Icon name="spark" size={17} /> Preguntar a la IA</button>
              </div>
              <div className="stat-strip">
                <div><strong>{page.total.toLocaleString("es")}</strong><span>mensajes disponibles</span></div>
                <i />
                <div><strong>Texto completo</strong><span>párrafos originales</span></div>
                <i />
                <div><strong>Consulta guiada</strong><span>respuestas con referencias</span></div>
              </div>
              <div className="library-toolbar">
                <div><h2>Todos los mensajes</h2><p>{query ? `${page.total.toLocaleString("es")} resultados` : "Explora el catálogo en español"}</p></div>
                <label className="search-box">
                  <Icon name="search" size={18} />
                  <input value={query} onChange={(event) => setQuery(event.target.value)}
                    placeholder="Buscar por título, fecha o contenido" aria-label="Buscar mensajes" />
                  {query && <button onClick={() => setQuery("")} aria-label="Limpiar búsqueda"><Icon name="close" size={15} /></button>}
                </label>
              </div>
              {listError && <div className="inline-error">{listError} <button onClick={() => loadMessages(query)}>Reintentar</button></div>}
              <div className="message-list">
                {page.sermons.map((sermon, index) => (
                  <button className="message-row" key={sermon.id} onClick={() => openMessage(sermon.id)}>
                    <span className="message-index">{String(index + 1).padStart(2, "0")}</span>
                    <span className="message-main">
                      <strong>{sermon.title}</strong>
                      <span>{sermon.id}{sermon.date ? ` · ${sermon.date}` : ""}</span>
                    </span>
                    <span className="message-location">{sermon.location || "Mensaje"}<small>{sermon.paragraphCount ? `${sermon.paragraphCount} párrafos` : "Texto disponible"}</small></span>
                    <span className="row-arrow"><Icon name="right" size={17} /></span>
                  </button>
                ))}
                {!loadingList && page.sermons.length === 0 && !listError && (
                  <div className="empty-results"><Icon name="search" size={24} /><strong>No encontramos mensajes</strong><span>Prueba con otras palabras o con el código del mensaje.</span></div>
                )}
              </div>
              {loadingList && <div className="loading-line"><span /> Cargando mensajes…</div>}
              {!loadingList && page.sermons.length < page.total && (
                <button className="load-more" onClick={() => loadMessages(query, page.sermons.length, true)}>
                  Cargar más mensajes <Icon name="right" size={15} />
                </button>
              )}
              <p className="catalog-note">Se muestran {page.sermons.length.toLocaleString("es")} de {page.total.toLocaleString("es")} mensajes. El texto completo se carga cuando abres un mensaje.</p>
            </section>
          )
        )}
        {section === "chat" && (
          <ChatView
            chat={chat}
            canEdit={study.canEdit}
            draft={draft}
            setDraft={setDraft}
            sendMessage={sendMessage}
            sending={sending}
            error={chatError}
            clearChat={clearChat}
            inputRef={inputRef}
            chatEndRef={chatEndRef}
            onOpenSource={(id, paragraphNumber) => {
              setSection("library");
              setMobileNavOpen(false);
            openMessage(id, paragraphNumber);
            }}
            onOpenLibrary={() => navigate("library")}
            onToast={showToast}
            onEditMessage={editChatMessage}
            onDeleteMessage={(index) => setChat((messages) => {
              const next = messages.filter((_, i) => i !== index && !(messages[index]?.role === "assistant" && i === index - 1 && messages[i].role === "user"));
              return next.length ? next : initialChat;
            })}
          />
        )}
        {["favorites", "notes", "highlights"].includes(section) && (
          <StudyListView kind={section} study={study} canEdit={study.canEdit} onToast={showToast}
            onOpen={(id, n) => { if (id && typeof id === "object") { setBibleTarget({ ...id, nonce: Date.now() }); setSection("bible"); } else { setSection("library"); openMessage(id, n); } }} />
        )}
        {section === "bible" && <BibleView onToast={showToast} study={study} target={bibleTarget} canEdit={study.canEdit} />}
        {section === "multinotes" && (
          <MultiNotesView study={study} canEdit={study.canEdit} onToast={showToast}
            onOpen={(id, n) => { setSection("library"); openMessage(id, n); }} />
        )}
        {section === "settings" && (
          <SettingsView
            theme={theme}
            setTheme={setTheme}
            textSize={textSize}
            setTextSize={setTextSize}
          />
        )}
        {section === "users" && authSession.isAdmin && <AdminActivityView />}
      </main>
      {toast && <div className="toast" role="status">{toast}</div>}
    </div>
  );
}

function SettingsView({ theme, setTheme, textSize, setTextSize }) {
  const textSizes = [
    { value: "small", label: "Pequeño", sample: "Aa", description: "Más texto en pantalla" },
    { value: "medium", label: "Mediano", sample: "Aa", description: "Tamaño recomendado" },
    { value: "large", label: "Grande", sample: "Aa", description: "Lectura más cómoda" },
  ];

  return (
    <section className="settings-view">
      <div className="settings-intro">
        <p className="eyebrow">PREFERENCIAS</p>
        <h1>Configuración</h1>
        <p>Personaliza la apariencia y la lectura de la biblioteca.</p>
      </div>
      <section className="settings-section" aria-labelledby="appearance-title">
        <div className="settings-section-heading">
          <span className="settings-section-icon"><Icon name="sun" size={18} /></span>
          <div><h2 id="appearance-title">Apariencia</h2><p>Elige cómo se ve la aplicación.</p></div>
        </div>
        <div className="theme-options" role="group" aria-label="Modo de apariencia">
          <button className={`theme-option ${theme === "light" ? "selected" : ""}`}
            aria-pressed={theme === "light"} onClick={() => setTheme("light")}>
            <span className="theme-preview preview-light"><i /><i /><i /></span>
            <span className="option-label"><Icon name="sun" size={16} /> Claro</span>
            {theme === "light" && <span className="selected-indicator">Activo</span>}
          </button>
          <button className={`theme-option ${theme === "dark" ? "selected" : ""}`}
            aria-pressed={theme === "dark"} onClick={() => setTheme("dark")}>
            <span className="theme-preview preview-dark"><i /><i /><i /></span>
            <span className="option-label"><Icon name="moon" size={16} /> Oscuro</span>
            {theme === "dark" && <span className="selected-indicator">Activo</span>}
          </button>
        </div>
      </section>
      <section className="settings-section" aria-labelledby="text-size-title">
        <div className="settings-section-heading">
          <span className="settings-section-icon"><Icon name="type" size={19} /></span>
          <div><h2 id="text-size-title">Tamaño del texto</h2><p>Ajusta el tamaño para leer mensajes y conversaciones.</p></div>
        </div>
        <div className="text-size-options" role="group" aria-label="Tamaño del texto">
          {textSizes.map((option) => (
            <button key={option.value}
              className={`text-size-option ${textSize === option.value ? "selected" : ""}`}
              aria-pressed={textSize === option.value}
              onClick={() => setTextSize(option.value)}>
              <span className={`size-sample sample-${option.value}`}>{option.sample}</span>
              <span className="size-description"><strong>{option.label}</strong><small>{option.description}</small></span>
              <span className="radio-indicator" />
            </button>
          ))}
        </div>
      </section>
      <p className="settings-saved">Tus preferencias se guardan automáticamente en este dispositivo.</p>
    </section>
  );
}

function ChatView({ chat, canEdit, draft, setDraft, sendMessage, sending, error, clearChat, inputRef, chatEndRef, onOpenSource, onOpenLibrary, onToast, onDeleteMessage, onEditMessage }) {
  const [editing, setEditing] = useState(null);
  return (
    <section className="chat-view">
      <div className="chat-heading">
        <div className="chat-title">
          <span className="chat-avatar"><Icon name="spark" size={20} /></span>
          <div><p className="eyebrow">ASISTENTE DE ESTUDIO</p><h1>Pregúntale a los mensajes</h1></div>
        </div>
        <div className="chat-heading-actions">
          <button className="clear-chat" title="Compartir conversación" disabled={chat.length <= 1}
            onClick={async () => onToast(await shareContent({ title: "Mensajes de William Branham", text: conversationToText(chat.slice(1)) }))}>
            <Icon name="share" size={16} /><span>Compartir</span>
          </button>
          <button className="clear-chat" onClick={clearChat} title="Nueva conversación"><Icon name="close" size={16} /><span>Nuevo chat</span></button>
        </div>
      </div>
      <div className="chat-context"><span className="status-dot" /> Respuestas basadas en pasajes del catálogo <span className="context-separator">·</span> Las fuentes aparecen debajo de cada respuesta</div>
      <div className="chat-scroll">
        <div className="conversation">
          {chat.map((message, index) => (
            <div className={`chat-message ${message.role}`} key={`${index}-${message.text.slice(0, 18)}`}>
              {message.role === "assistant" && <span className="message-avatar"><Icon name="spark" size={15} /></span>}
              <div className="bubble-wrap">
                {editing?.index === index ? (
                  <div className="note-composer chat-edit">
                    <textarea autoFocus rows={3} value={editing.text} onChange={(e) => setEditing({ ...editing, text: e.target.value })} />
                    <div>
                      <button type="button" className="ghost-button" onClick={() => setEditing(null)}>Cancelar</button>
                      <button type="button" className="ghost-button" disabled={!editing.text.trim()}
                        onClick={() => { onEditMessage(index, editing.text, false); setEditing(null); onToast("Mensaje editado"); }}>Guardar</button>
                      {message.role === "user" && (
                        <button type="button" className="ask-cta" disabled={!editing.text.trim() || sending}
                          onClick={() => { onEditMessage(index, editing.text, true); setEditing(null); }}>
                          <Icon name="send" size={14} /> Guardar y reenviar</button>
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="bubble">{message.text}</div>
                )}
                {canEdit && index > 0 && (
                  <div className="note-actions chat-actions">
                    <button onClick={() => setEditing({ index, text: message.text })}><Icon name="edit" size={14} /> Editar</button>
                    <button onClick={() => { onDeleteMessage(index); onToast("Mensaje eliminado"); }}><Icon name="trash" size={14} /> Eliminar</button>
                  </div>
                )}
                {message.role === "assistant" && message.sources?.length > 0 && (
                  <div className="note-actions chat-actions">
                    <button onClick={async () => {
                      const question = chat.slice(0, index).reverse().find((m) => m.role === "user")?.text;
                      onToast(await shareContent({
                        title: "Mensajes de William Branham",
                        text: `${question ? `Pregunta: ${question}\n\n` : ""}${message.text}`,
                      }));
                    }}><Icon name="share" size={14} /> Compartir</button>
                  </div>
                )}
                {message.role === "assistant" && message.sources?.length > 0 && (
                  <div className="sources">
                    <p><Icon name="book" size={14} /> PASAJES CONSULTADOS</p>
                    {message.sources.map((source) => (
                      <button className="source-link" key={`${source.id}-${source.number}`}
                        onClick={() => { onOpenSource(source.id, source.number); }}>
                        <span><strong>{source.title}</strong><small>{source.code} · párrafo {source.number}</small></span>
                        <Icon name="arrow" size={14} />
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          ))}
          {sending && <div className="chat-message assistant"><span className="message-avatar"><Icon name="spark" size={15} /></span><div className="bubble typing"><i /><i /><i /></div></div>}
          <div ref={chatEndRef} />
        </div>
      </div>
      <div className="chat-bottom">
        {chat.length <= 1 && (
          <div className="suggestions">
            {["¿Qué dice sobre la fe?", "¿Qué enseñó sobre la oración?", "Busca mensajes sobre la sanidad"].map((suggestion) => (
              <button key={suggestion} onClick={() => setDraft(suggestion)}>{suggestion}</button>
            ))}
          </div>
        )}
        {error && <div className="chat-error">{error}</div>}
        <form className="chat-composer" onSubmit={sendMessage}>
          <textarea ref={inputRef} value={draft} onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); sendMessage(event); } }}
            placeholder="Pregunta sobre un tema o mensaje…" rows="1" aria-label="Escribe tu pregunta" />
          <button type="submit" disabled={!draft.trim() || sending} aria-label="Enviar pregunta"><Icon name="send" size={17} /></button>
        </form>
        <p className="chat-disclaimer">La IA puede equivocarse. Comprueba las referencias y consulta los pasajes originales.</p>
      </div>
    </section>
  );
}

export default App;
