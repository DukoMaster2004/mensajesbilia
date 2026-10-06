import { useCallback, useEffect, useRef, useState } from "react";

const KEY = "branham-study";
const empty = { favorites: [], notes: [], highlights: [], multiNotes: [] };
const collections = ["favorites", "notes", "highlights", "multiNotes", "chat"];

function sharedItemKey(collection, item) {
  return collection === "notes" || collection === "multiNotes"
    ? item.id
    : collection === "chat" ? "global" : item.key;
}

function read() {
  try {
    const data = JSON.parse(localStorage.getItem(KEY) || "{}");
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

export function useStudyData() {
  const [data, setData] = useState(read);
  const [syncError, setSyncError] = useState("");
  const [ready, setReady] = useState(false);
  const initialData = useRef(data);
  const latestData = useRef(data);
  const baseline = useRef(null);
  const dirty = useRef(new Map());
  const inFlight = useRef(new Set());
  const writeVersion = useRef(0);

  useEffect(() => {
    try { localStorage.setItem(KEY, JSON.stringify(data)); } catch { /* storage unavailable */ }
  }, [data]);

  useEffect(() => {
    latestData.current = data;
    if (!ready || !baseline.current) return;

    for (const collection of collections) {
      const previous = new Map((baseline.current[collection] || []).map((item) => [sharedItemKey(collection, item), item]));
      const current = new Map((data[collection] || []).map((item) => [sharedItemKey(collection, item), item]));
      const keys = new Set([...previous.keys(), ...current.keys()]);
      for (const key of keys) {
        const before = previous.get(key);
        const after = current.get(key);
        if (JSON.stringify(before) !== JSON.stringify(after)) {
          const identity = `${collection}\u0000${key}`;
          dirty.current.set(identity, { collection, key, payload: after, signature: JSON.stringify(after) });
          if (after === undefined) previous.delete(key);
          else previous.set(key, after);
        }
      }
      baseline.current[collection] = [...previous.values()];
    }

    async function flush() {
      for (const [identity, change] of dirty.current) {
        if (inFlight.current.has(identity)) continue;
        inFlight.current.add(identity);
        try {
          const response = await fetch(`/api/shared-state/${encodeURIComponent(change.collection)}/${encodeURIComponent(change.key)}`, {
            method: change.payload === undefined ? "DELETE" : "PUT",
            headers: change.payload === undefined ? undefined : { "Content-Type": "application/json" },
            body: change.payload === undefined ? undefined : JSON.stringify({ payload: change.payload }),
          });
          const result = change.payload === undefined ? null : await response.json().catch(() => null);
          if (!response.ok) throw new Error(result?.error || "No se pudo guardar el cambio compartido.");
          if (dirty.current.get(identity)?.signature === change.signature) dirty.current.delete(identity);
          writeVersion.current += 1;
          setSyncError("");
        } catch (error) {
          setSyncError(error.message || "No se pudo guardar el cambio compartido.");
        } finally {
          inFlight.current.delete(identity);
        }
      }
    }

    flush();
  }, [data, ready]);

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
          const oldData = initialData.current;
          if (Object.values(oldData).some((items) => Array.isArray(items) && items.length)) {
            try { localStorage.setItem(`${KEY}-local-backup`, JSON.stringify(oldData)); } catch { /* local backup unavailable */ }
          }
          const currentData = latestData.current;
          const merged = { ...remote };
          for (const collection of collections) {
            const oldItems = new Map((oldData[collection] || []).map((item) => [sharedItemKey(collection, item), item]));
            const currentItems = new Map((currentData[collection] || []).map((item) => [sharedItemKey(collection, item), item]));
            const keys = new Set([...oldItems.keys(), ...currentItems.keys()]);
            for (const key of keys) {
              const before = oldItems.get(key);
              const after = currentItems.get(key);
              if (JSON.stringify(before) === JSON.stringify(after)) continue;
              dirty.current.set(`${collection}\u0000${key}`, { collection, key, payload: after, signature: JSON.stringify(after) });
              const items = merged[collection];
              const index = items.findIndex((item) => sharedItemKey(collection, item) === key);
              if (after === undefined) {
                if (index !== -1) items.splice(index, 1);
              } else if (index === -1) items.push(after);
              else items[index] = after;
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
    return () => { cancelled = true; window.clearInterval(interval); };
  }, []);

  const toggleFavorite = useCallback((item) => {
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
  }, []);

  const setHighlight = useCallback((item, color) => {
    setData((d) => {
      const key = itemKey(item.messageId, item.number);
      const current = d.highlights.find((h) => h.key === key);
      const rest = d.highlights.filter((h) => h.key !== key);
      if (current && current.color === color) return { ...d, highlights: rest };
      return { ...d, highlights: [{ ...item, key, color, createdAt: current?.createdAt || Date.now() }, ...rest] };
    });
  }, []);

  const setTextHighlight = useCallback((item, start, end, color) => {
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
  }, []);

  const removeHighlight = useCallback((key) => {
    setData((d) => ({ ...d, highlights: d.highlights.filter((h) => h.key !== key) }));
  }, []);

  const saveNote = useCallback((item, text, id) => {
    const body = text.trim();
    if (!body) return;
    setData((d) => {
      if (id) {
        return { ...d, notes: d.notes.map((n) => (n.id === id ? { ...n, text: body, updatedAt: Date.now() } : n)) };
      }
      const note = { ...item, id: `n${Date.now()}${Math.random().toString(36).slice(2, 6)}`, text: body, createdAt: Date.now(), updatedAt: Date.now() };
      return { ...d, notes: [note, ...d.notes] };
    });
  }, []);

  const deleteNote = useCallback((id) => {
    setData((d) => ({ ...d, notes: d.notes.filter((n) => n.id !== id) }));
  }, []);

  const saveMultiNote = useCallback((note) => {
    setData((d) => {
      const exists = d.multiNotes.some((n) => n.id === note.id);
      const saved = { ...note, updatedAt: Date.now() };
      return {
        ...d,
        multiNotes: exists ? d.multiNotes.map((n) => (n.id === note.id ? saved : n)) : [saved, ...d.multiNotes],
      };
    });
  }, []);

  const deleteMultiNote = useCallback((id) => {
    setData((d) => ({ ...d, multiNotes: d.multiNotes.filter((n) => n.id !== id) }));
  }, []);

  const clearAll = useCallback((kind) => {
    setData((d) => ({ ...d, [kind]: [] }));
  }, []);

  return { ...data, syncError, clearAll, saveMultiNote, deleteMultiNote, toggleFavorite, setHighlight, setTextHighlight, removeHighlight, saveNote, deleteNote };
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
