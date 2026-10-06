import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

const KEY = "branham-study";
const empty = { favorites: [], notes: [], highlights: [], multiNotes: [] };
const collections = ["favorites", "notes", "highlights", "multiNotes", "chat"];

function sharedItemKey(collection, item) {
  return collection === "notes" || collection === "multiNotes"
    ? item.id
    : collection === "chat" ? "global" : item.key;
}

function read(storageKey = KEY) {
  try {
    const data = JSON.parse(localStorage.getItem(storageKey) || "{}");
    return {
      favorites: Array.isArray(data.favorites) ? data.favorites : [],
      notes: Array.isArray(data.notes) ? data.notes : [],
      highlights: Array.isArray(data.highlights) ? data.highlights : [],
      multiNotes: Array.isArray(data.multiNotes) ? data.multiNotes : [],
    };
  } catch {
    return empty;
  }
}

export const HIGHLIGHT_COLORS = ["yellow", "green", "blue", "pink"];
export const itemKey = (id, number = 0) => `${id}:${number}`;

export function useStudyData(accountId = "") {
  const storageKey = accountId ? `${KEY}:${accountId}` : `${KEY}:public`;
  const backupKey = `${storageKey}-local-backup`;
  const migrationKey = `${storageKey}-migration-complete`;
  const [data, setData] = useState(() => read(storageKey));
  const [syncError, setSyncError] = useState("");
  const [ready, setReady] = useState(false);
  const initialData = useRef(data);
  const currentAccount = useRef(accountId);
  const migrationData = useRef(data);
  const migrationStarted = useRef(false);
  const baseline = useRef(null);
  const dirty = useRef(new Map());
  const migrationChanges = useRef(new Set());
  const inFlight = useRef(new Set());
  const writeVersion = useRef(0);
  const retryTimer = useRef(null);
  const canEdit = Boolean(accountId) && ready && currentAccount.current === accountId;

  useLayoutEffect(() => {
    if (currentAccount.current === accountId) return;
    currentAccount.current = accountId;
    const accountData = read(storageKey);
    initialData.current = accountData;
    const accountBackup = read(backupKey);
    migrationData.current = Object.values(accountBackup).some((items) => items.length) ? accountBackup : accountData;
    setData(accountData);
    setReady(false);
    setSyncError("");
    baseline.current = null;
    dirty.current.clear();
    migrationChanges.current.clear();
    migrationStarted.current = false;
    writeVersion.current += 1;
  }, [accountId, backupKey, storageKey]);

  useEffect(() => {
    if (currentAccount.current !== accountId) return;
    try { localStorage.setItem(storageKey, JSON.stringify(data)); } catch { /* storage unavailable */ }
  }, [data, accountId, storageKey]);

  useEffect(() => {
    if (!canEdit || !ready || !baseline.current) return;

    for (const collection of collections) {
      const previous = new Map((baseline.current[collection] || []).map((item) => [sharedItemKey(collection, item), item]));
      const current = new Map((data[collection] || []).map((item) => [sharedItemKey(collection, item), item]));
      const keys = new Set([...previous.keys(), ...current.keys()]);
      for (const key of keys) {
        const before = previous.get(key);
        const after = current.get(key);
        if (JSON.stringify(before) !== JSON.stringify(after)) {
          const identity = `${accountId}\u0000${collection}\u0000${key}`;
          dirty.current.set(identity, { accountId, collection, key, payload: after, signature: JSON.stringify(after) });
          if (after === undefined) previous.delete(key);
          else previous.set(key, after);
        }
      }
      baseline.current[collection] = [...previous.values()];
    }

    async function flush() {
      if (retryTimer.current !== null) {
        window.clearTimeout(retryTimer.current);
        retryTimer.current = null;
      }
      for (const [identity, change] of dirty.current) {
        if (inFlight.current.has(identity)) continue;
        inFlight.current.add(identity);
        try {
          if (change.accountId !== currentAccount.current) continue;
          const response = await fetch(`/api/shared-state/${encodeURIComponent(change.collection)}/${encodeURIComponent(change.key)}`, {
            method: change.payload === undefined ? "DELETE" : "PUT",
            headers: {
              ...(change.payload === undefined ? {} : { "Content-Type": "application/json" }),
              "X-Account-Id": change.accountId,
            },
            body: change.payload === undefined ? undefined : JSON.stringify({ payload: change.payload }),
          });
          const result = change.payload === undefined ? null : await response.json().catch(() => null);
          if (!response.ok) {
            if (response.status === 401) window.dispatchEvent(new Event("google-session-expired"));
            throw new Error(result?.error || `Vercel respondió HTTP ${response.status} al guardar. Revisa las variables de Supabase y la ruta de la API.`);
          }
          if (dirty.current.get(identity)?.signature === change.signature) dirty.current.delete(identity);
          migrationChanges.current.delete(identity);
          writeVersion.current += 1;
          setSyncError("");
        } catch (error) {
          setSyncError(error.message || "No se pudo guardar el cambio compartido.");
          if (retryTimer.current === null) {
            retryTimer.current = window.setTimeout(() => {
              retryTimer.current = null;
              flush();
            }, 5000);
          }
        } finally {
          inFlight.current.delete(identity);
        }
      }
      if (migrationStarted.current && migrationChanges.current.size === 0) {
        try { localStorage.setItem(migrationKey, "true"); } catch { /* migration marker unavailable */ }
        migrationStarted.current = false;
      }
    }

    flush();
  }, [data, ready, canEdit, accountId, migrationKey]);

  useEffect(() => {
    let cancelled = false;
    let initialized = false;
    async function synchronize() {
      const versionAtRequest = writeVersion.current;
      try {
        const response = await fetch("/api/shared-state");
        const result = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(result.error || "No se pudo cargar la información compartida.");
        if (cancelled) return;
        if (initialized && (versionAtRequest !== writeVersion.current || inFlight.current.size > 0)) return;

        const remote = Object.fromEntries(collections.map((collection) => [collection, []]));
        for (const entry of result.entries || []) {
          if (remote[entry.collection]) remote[entry.collection].push(entry.payload);
        }
        for (const collection of collections) {
          remote[collection].sort((a, b) => (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0));
        }

        if (!initialized) {
          initialized = true;
          const oldData = migrationData.current || initialData.current;
          if (Object.values(oldData).some((items) => Array.isArray(items) && items.length)) {
            try { localStorage.setItem(backupKey, JSON.stringify(oldData)); } catch { /* local backup unavailable */ }
          }
          const merged = { ...remote };
          let migrationComplete = false;
          try { migrationComplete = localStorage.getItem(migrationKey) === "true"; } catch { /* storage unavailable */ }
          if (canEdit && !migrationComplete) {
            migrationStarted.current = true;
            for (const collection of collections) {
              for (const item of Array.isArray(oldData[collection]) ? oldData[collection] : []) {
                const key = sharedItemKey(collection, item);
                if (remote[collection].some((remoteItem) => sharedItemKey(collection, remoteItem) === key)) continue;
                const identity = `${accountId}\u0000${collection}\u0000${key}`;
                dirty.current.set(identity, { accountId, collection, key, payload: item, signature: JSON.stringify(item) });
                migrationChanges.current.add(identity);
                merged[collection].push(item);
              }
            }
          }
          baseline.current = remote;
          setData(merged);
          setReady(true);
        } else {
          const merged = { ...remote };
          for (const change of dirty.current.values()) {
            const values = merged[change.collection];
            const index = values.findIndex((item) => sharedItemKey(change.collection, item) === change.key);
            if (change.payload === undefined) {
              if (index !== -1) values.splice(index, 1);
            } else if (index === -1) values.push(change.payload);
            else values[index] = change.payload;
          }
          baseline.current = remote;
          setData(merged);
        }
        setSyncError("");
      } catch (error) {
        if (!cancelled) setSyncError(error.message || "No se pudo sincronizar la información compartida.");
      }
    }

    synchronize();
    const interval = window.setInterval(synchronize, 5000);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
      if (retryTimer.current !== null) window.clearTimeout(retryTimer.current);
    };
  }, [canEdit, accountId, backupKey, migrationKey]);

  const toggleFavorite = useCallback((item) => {
    if (!canEdit) return;
    setData((d) => {
      const key = itemKey(item.messageId, item.number);
      const exists = d.favorites.some((f) => f.key === key);
      return {
        ...d,
        favorites: exists
          ? d.favorites.filter((f) => f.key !== key)
          : [{ ...item, key, createdAt: Date.now() }, ...d.favorites],
      };
    });
  }, [canEdit]);

  const setHighlight = useCallback((item, color) => {
    if (!canEdit) return;
    setData((d) => {
      const key = itemKey(item.messageId, item.number);
      const current = d.highlights.find((h) => h.key === key);
      const rest = d.highlights.filter((h) => h.key !== key);
      if (current && current.color === color) return { ...d, highlights: rest };
      return { ...d, highlights: [{ ...item, key, color, createdAt: current?.createdAt || Date.now() }, ...rest] };
    });
  }, [canEdit]);

  const setTextHighlight = useCallback((item, start, end, color) => {
    if (!canEdit) return;
    setData((d) => {
      const key = `${itemKey(item.messageId, item.number)}:text:${start}:${end}`;
      const current = d.highlights.find((h) => h.key === key);
      if (current?.color === color) {
        return { ...d, highlights: d.highlights.filter((h) => h.key !== key) };
      }
      const highlight = { ...item, key, start, end, color, createdAt: current?.createdAt || Date.now() };
      return {
        ...d,
        highlights: current
          ? d.highlights.map((h) => (h.key === key ? highlight : h))
          : [highlight, ...d.highlights],
      };
    });
  }, [canEdit]);

  const removeHighlight = useCallback((key) => {
    if (!canEdit) return;
    setData((d) => ({ ...d, highlights: d.highlights.filter((h) => h.key !== key) }));
  }, [canEdit]);

  const saveNote = useCallback((item, text, id) => {
    if (!canEdit) return;
    const body = text.trim();
    if (!body) return;
    setData((d) => {
      if (id) {
        return { ...d, notes: d.notes.map((n) => (n.id === id ? { ...n, text: body, updatedAt: Date.now() } : n)) };
      }
      const note = { ...item, id: `n${Date.now()}${Math.random().toString(36).slice(2, 6)}`, text: body, createdAt: Date.now(), updatedAt: Date.now() };
      return { ...d, notes: [note, ...d.notes] };
    });
  }, [canEdit]);

  const deleteNote = useCallback((id) => {
    if (!canEdit) return;
    setData((d) => ({ ...d, notes: d.notes.filter((n) => n.id !== id) }));
  }, [canEdit]);

  const saveMultiNote = useCallback((note) => {
    if (!canEdit) return;
    setData((d) => {
      const exists = d.multiNotes.some((n) => n.id === note.id);
      const saved = { ...note, updatedAt: Date.now() };
      return {
        ...d,
        multiNotes: exists ? d.multiNotes.map((n) => (n.id === note.id ? saved : n)) : [saved, ...d.multiNotes],
      };
    });
  }, [canEdit]);

  const deleteMultiNote = useCallback((id) => {
    if (!canEdit) return;
    setData((d) => ({ ...d, multiNotes: d.multiNotes.filter((n) => n.id !== id) }));
  }, [canEdit]);

  const clearAll = useCallback((kind) => {
    if (!canEdit) return;
    setData((d) => ({ ...d, [kind]: [] }));
  }, [canEdit]);

  return { ...data, canEdit, syncError, clearAll, saveMultiNote, deleteMultiNote, toggleFavorite, setHighlight, setTextHighlight, removeHighlight, saveNote, deleteNote };
}

export async function shareContent({ title, text }) {
  const url = window.location.origin;
  const body = `${text}\n— ${title}`;
  if (navigator.share) {
    try {
      await navigator.share({ title, text: body, url });
      return "Compartido";
    } catch (error) {
      if (error?.name === "AbortError") return "";
    }
  }
  try {
    await navigator.clipboard.writeText(`${body}\n${url}`);
    return "Copiado al portapapeles";
  } catch {
    return "No se pudo compartir";
  }
}
