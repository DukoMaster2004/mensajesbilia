import { useRef, useState } from "react";
import { HIGHLIGHT_COLORS } from "./useStudyData.js";

const COLOR_LABEL = { yellow: "Amarillo", green: "Verde", blue: "Azul", pink: "Rosa" };

function getOffset(root, node, offset) {
  const range = document.createRange();
  range.selectNodeContents(root);
  range.setEnd(node, offset);
  return range.toString().length;
}

export function HighlightableText({ text, highlights, onSave }) {
  const textRef = useRef(null);
  const [manualMode, setManualMode] = useState(false);
  const [selection, setSelection] = useState(null);

  function captureSelection() {
    if (!manualMode) return;
    const root = textRef.current;
    const selected = window.getSelection();
    if (!root || !selected || selected.isCollapsed || !root.contains(selected.anchorNode) || !root.contains(selected.focusNode)) {
      setSelection(null);
      return;
    }

    const range = selected.getRangeAt(0);
    const start = getOffset(root, range.startContainer, range.startOffset);
    const end = getOffset(root, range.endContainer, range.endOffset);
    if (start === end || !text.slice(start, end).trim()) {
      setSelection(null);
      return;
    }
    setSelection({ start, end });
  }

  const boundaries = new Set([0, text.length]);
  highlights.forEach(({ start, end }) => {
    if (Number.isInteger(start) && Number.isInteger(end) && start >= 0 && end <= text.length && start < end) {
      boundaries.add(start);
      boundaries.add(end);
    }
  });
  const points = [...boundaries].sort((a, b) => a - b);
  const pieces = points.slice(0, -1).map((start, index) => {
    const end = points[index + 1];
    const mark = highlights
      .filter((highlight) => highlight.start <= start && highlight.end >= end)
      .sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0))[0];
    return { start, end, color: mark?.color };
  });

  return (
    <>
      <span ref={textRef} className="highlightable-text" onMouseUp={captureSelection} onTouchEnd={captureSelection}>
        {pieces.map(({ start, end, color }) => color
          ? <mark className={`text-highlight hl-${color}`} key={`${start}-${end}`}>{text.slice(start, end)}</mark>
          : <span key={`${start}-${end}`}>{text.slice(start, end)}</span>)}
      </span>
      <span className="manual-highlight-controls">
        <button className={manualMode ? "manual-highlight-toggle active" : "manual-highlight-toggle"}
          type="button" aria-pressed={manualMode}
          onClick={() => { setManualMode((active) => !active); setSelection(null); }}>
          {manualMode ? "Cancelar resaltado manual" : "Resaltar texto"}
        </button>
        {manualMode && (selection ? (
          <div className="manual-highlight-palette" aria-label="Elegir color del resaltado">
            <span>Elige un color:</span>
            {HIGHLIGHT_COLORS.map((color) => (
              <button key={color} type="button" className={`swatch swatch-${color}`}
                aria-label={`Resaltar selección en ${COLOR_LABEL[color]}`}
                title={`Resaltar selección en ${COLOR_LABEL[color]}`}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => {
                  onSave(selection.start, selection.end, color);
                  setSelection(null);
                  window.getSelection()?.removeAllRanges();
                }} />
            ))}
          </div>
        ) : <span className="manual-highlight-hint">Selecciona con el cursor la parte que quieres resaltar.</span>)}
      </span>
    </>
  );
}
