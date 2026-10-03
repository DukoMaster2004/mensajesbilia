import { useCallback, useEffect, useState } from "react";

const KEY = "branham-study";
const empty = { favorites: [], notes: [], highlights: [], multiNotes: [] };

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

  useEffect(() => {
    try { localStorage.setItem(KEY, JSON.stringify(data)); } catch { /* storage unavailable */ }
  }, [data]);

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

  return { ...data, clearAll, saveMultiNote, deleteMultiNote, toggleFavorite, setHighlight, saveNote, deleteNote };
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
