/**
 * ClothingMenu — Two-panel wardrobe layout
 *   Left:  CapturePreview in browse mode (categories + tabs)
 *   Right: Item thumbnail grid with search + recapture
 *   Center: Character visible
 */

import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { FixedSizeGrid as Grid } from 'react-window'
import {
  Search, X, Check, Shirt, RotateCcw, Camera,
  HardHat, Glasses, Watch, Footprints, ShoppingBag,
  Shield, Paintbrush, Ear, Gem, Car, Box,
} from 'lucide-react'
import { CapturePreview, CAT_ICON_MAP, CAT_TYPE_ICON } from './CapturePreview'
import { ScrollArea } from './ui/scroll-area'

const THUMB_BASE = 'https://cfx-nui-uz_AutoShot/shots/'
const CARD_W = 88, GAP = 4
const border = (o = 0.06) => `1px solid rgba(255,255,255,${o})`
const bg     = (o = 0.03) => `rgba(255,255,255,${o})`

// ── Thumbnail ────────────────────────────────────────
const Thumbnail = React.memo(({ item, isSelected, onClick, ext, recaptureMode, recaptureSelected }) => {
  const [src, setSrc] = useState(null)
  const [error, setError] = useState(false)
  const texSuffix = item.texture > 0 ? `_${item.texture}` : ''
  const thumbName = item.type === 'vehicle' ? `vehicles/${item.model || item.id}.${ext}`
    : item.type === 'object' ? `objects/${item.model || item.id}.${ext}`
    : item.type === 'overlay' ? `${item.gender}/overlay_${item.id}/${item.drawable}.${ext}`
    : item.type === 'tattoo' ? `${item.gender}/tattoos/${item.collection.toLowerCase()}/${item.overlay.toLowerCase()}.${ext}`
    : item.type === 'prop' ? `${item.gender}/prop_${item.id}/${item.drawable}${texSuffix}.${ext}`
    : `${item.gender}/${item.id}/${item.drawable}${texSuffix}.${ext}`
  const displayLabel = item.model || item.overlay || `#${item.drawable}`
  const longLabel = !!(item.model || item.overlay)

  useEffect(() => {
    let c = false; setSrc(null); setError(false)
    fetch(THUMB_BASE + thumbName).then(r => { if (!r.ok) throw 0; return r.blob() })
      .then(b => { if (!c) setSrc(URL.createObjectURL(b)) }).catch(() => { if (!c) setError(true) })
    return () => { c = true }
  }, [thumbName])

  const active = recaptureSelected || isSelected
  const accent = recaptureSelected ? '#fb923c' : '#fff'
  return (
    <div className="group relative overflow-hidden cursor-pointer"
      style={{ borderRadius: 7, width: '100%', height: '100%', background: active ? `${accent}06` : 'rgba(255,255,255,0.012)', border: `1px solid ${active ? `${accent}30` : 'rgba(255,255,255,0.04)'}`, display: 'flex', flexDirection: 'column' }}
      onClick={() => onClick(item)}>
      <div style={{ position: 'relative', flex: '1 1 0', minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', background: 'rgba(0,0,0,0.15)' }}>
        {!src && !error && <div style={{ position: 'absolute', inset: 0 }} className="skeleton" />}
        {error && <span style={{ fontSize: 8, color: '#333' }}>{displayLabel}</span>}
        {src && <img src={src} alt="" draggable={false} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'contain', padding: 4, transition: 'transform 0.2s' }}
          onMouseOver={e => e.currentTarget.style.transform = 'scale(1.06)'} onMouseOut={e => e.currentTarget.style.transform = 'scale(1)'} />}
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,0.55)', opacity: 0, pointerEvents: 'none', transition: 'opacity 0.1s' }}
          ref={el => { if (!el) return; const p = el.parentElement?.parentElement; if (!p) return; p.onmouseenter = () => el.style.opacity = '1'; p.onmouseleave = () => el.style.opacity = '0' }}>
          <span style={{ fontSize: longLabel ? 7 : 9, fontWeight: 700, color: '#fff' }}>{displayLabel}</span>
        </div>
        {recaptureSelected && <div style={{ position: 'absolute', top: 3, right: 3, width: 13, height: 13, borderRadius: '50%', background: '#fb923c', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><RotateCcw style={{ width: 6, height: 6, color: '#000' }} strokeWidth={3} /></div>}
        {!recaptureMode && isSelected && <div style={{ position: 'absolute', top: 3, right: 3, width: 13, height: 13, borderRadius: '50%', background: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check style={{ width: 7, height: 7, color: '#000' }} strokeWidth={3} /></div>}
        {item.texture > 0 && <span style={{ position: 'absolute', top: 3, left: 3, fontSize: 7, fontWeight: 700, color: '#777', background: 'rgba(0,0,0,0.65)', border: '1px solid rgba(255,255,255,0.05)', borderRadius: 2, padding: '0 3px' }}>T{item.texture}</span>}
      </div>
      <div style={{ height: 16, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', borderTop: '1px solid rgba(255,255,255,0.025)', background: 'rgba(0,0,0,0.2)' }}>
        <span style={{ fontSize: longLabel ? 6 : 7, fontWeight: active ? 700 : 500, color: active ? '#ccc' : '#444' }} className="truncate" title={displayLabel}>{displayLabel}</span>
      </div>
    </div>
  )
})

function Cell({ columnIndex, rowIndex, style, data }) {
  const { filteredItems, selectedItem, onItemSelect, imgExt, recaptureMode, recaptureSet, toggleRecaptureItem, COLS } = data
  const idx = rowIndex * COLS + columnIndex
  if (idx >= filteredItems.length) return null
  const item = filteredItems[idx]
  const sel = !recaptureMode && selectedItem && selectedItem.type === item.type && selectedItem.id === item.id && selectedItem.drawable === item.drawable && selectedItem.texture === item.texture
  return (
    <div style={{ ...style, left: +style.left + GAP, top: +style.top + GAP, width: +style.width - GAP, height: +style.height - GAP }}>
      <Thumbnail item={item} isSelected={sel} ext={imgExt}
        onClick={recaptureMode ? toggleRecaptureItem : onItemSelect}
        recaptureMode={recaptureMode} recaptureSelected={recaptureMode && recaptureSet.has(`${item.type}-${item.id}-${item.drawable}-${item.texture}`)} />
    </div>
  )
}

// ════════════════════════════════════════════════════════
// ClothingMenu
// ════════════════════════════════════════════════════════
export function ClothingMenu({
  categories, activeCatIdx, onCategoryChange,
  filteredItems, selectedItem, onItemSelect, imgExt,
  searchQuery, onSearchChange,
  onClose, onRecapture,
}) {
  const activeCat = categories[activeCatIdx]
  const [recaptureMode, setRecaptureMode] = useState(false)
  const [recaptureSet, setRecaptureSet]   = useState(new Set())

  // ESC to close
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); onClose?.() } }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const toggleRecaptureMode = useCallback(() => { setRecaptureMode(p => !p); setRecaptureSet(new Set()) }, [])
  const toggleRecaptureItem = useCallback((item) => {
    const key = `${item.type}-${item.id}-${item.drawable}-${item.texture}`
    setRecaptureSet(prev => { const n = new Set(prev); n.has(key) ? n.delete(key) : n.add(key); return n })
  }, [])
  const handleRecaptureStart = useCallback(() => {
    if (recaptureSet.size === 0) return
    const items = Array.from(recaptureSet).map(k => { const p = k.split('-'); return { type: p[0], id: +p[1], drawable: +p[2], texture: +p[3] } })
    onRecapture?.(items); setRecaptureMode(false); setRecaptureSet(new Set())
  }, [recaptureSet, onRecapture])

  const gridRef = useRef(null)
  const [gridSize, setGridSize] = useState({ width: 0, height: 0 })
  useEffect(() => {
    const measure = () => { if (gridRef.current) { const r = gridRef.current.getBoundingClientRect(); setGridSize({ width: r.width, height: r.height }) } }
    measure(); const t = setTimeout(measure, 50); window.addEventListener('resize', measure)
    return () => { window.removeEventListener('resize', measure); clearTimeout(t) }
  }, [activeCatIdx])

  const COLS = Math.max(1, Math.floor((gridSize.width - GAP) / (CARD_W + GAP)))
  const ROWS = Math.ceil(filteredItems.length / COLS)
  const ROW_H = CARD_W + GAP + 16

  const itemData = useMemo(() => ({
    filteredItems, selectedItem, onItemSelect, imgExt, recaptureMode, recaptureSet, toggleRecaptureItem, COLS,
  }), [filteredItems, selectedItem, onItemSelect, imgExt, recaptureMode, recaptureSet, toggleRecaptureItem, COLS])

  // CapturePreview categories format
  const previewCats = useMemo(() => categories.map((cat, idx) => ({
    key: `${cat.type}-${cat.id}-${idx}`, label: cat.label, type: cat.type, id: cat.id,
    camera: cat.camera, models: cat.models, category: cat.category, drawables: cat.drawables,
  })), [categories])

  const catSubtitle = activeCat?.type === 'vehicle' ? activeCat?.id
    : activeCat?.type === 'object' ? activeCat?.id
    : activeCat?.type === 'overlay' ? `Overlay · ID ${activeCat?.id}`
    : activeCat?.type === 'tattoo' ? 'Tattoo zone'
    : activeCat?.type === 'prop' ? `Prop · ID ${activeCat?.id}` : `Component · ID ${activeCat?.id}`

  const ItemIcon = CAT_ICON_MAP[activeCat?.label] ?? CAT_TYPE_ICON[activeCat?.type] ?? Shirt

  return (
    <>
      {/* ═══ LEFT: CapturePreview (browse mode) ═══ */}
      <div data-no-orbit className="fixed left-5 top-5 z-[9999]" style={{ bottom: 160 }}>
        <CapturePreview
          mode="browse"
          categories={previewCats}
          onCancel={onClose}
          onActiveChange={(cat) => {
            const idx = categories.findIndex(c => c.type === cat.type && c.id === cat.id)
            if (idx >= 0) onCategoryChange(idx)
          }}
        />
      </div>

      {/* ═══ RIGHT: Item Grid ═══ */}
      <div data-no-orbit className="fixed right-5 top-5 bottom-5 z-[9999] flex flex-col glass animate-enter"
        style={{ width: 380, borderRadius: 14, border: border(), boxShadow: '0 8px 40px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.02)', overflow: 'hidden' }}>

        {/* Header */}
        <div className="flex items-center gap-2.5 shrink-0" style={{ padding: '12px 14px' }}>
          <div style={{ width: 28, height: 28, borderRadius: 7, display: 'flex', alignItems: 'center', justifyContent: 'center', background: bg(0.04), border: border(0.06) }}>
            <ItemIcon style={{ width: 12, height: 12, color: '#777' }} />
          </div>
          <div className="flex-1 min-w-0">
            <p style={{ fontSize: 13, fontWeight: 700, color: '#eee', letterSpacing: '-0.02em', lineHeight: 1.1 }}>{activeCat?.label || '—'}</p>
            <p style={{ fontSize: 8, color: '#444', marginTop: 1 }}>{catSubtitle}</p>
          </div>
          <span style={{ fontSize: 9, fontWeight: 600, color: '#555', fontVariantNumeric: 'tabular-nums', background: bg(0.03), border: border(0.05), borderRadius: 4, padding: '2px 8px' }}>
            {filteredItems.length}
          </span>
          <button onClick={toggleRecaptureMode} title="Re-capture mode"
            className="flex items-center justify-center shrink-0 cursor-pointer"
            style={{ width: 26, height: 26, borderRadius: 5, background: recaptureMode ? 'rgba(251,146,60,0.1)' : 'transparent', border: recaptureMode ? '1px solid rgba(251,146,60,0.25)' : border(0.06) }}>
            <RotateCcw style={{ width: 10, height: 10, color: recaptureMode ? '#fb923c' : '#444' }} />
          </button>
        </div>

        <div style={{ height: 1, background: bg(0.04) }} />

        {/* Search */}
        <div style={{ padding: '7px 12px' }}>
          <div className="flex items-center gap-2" style={{ height: 30, borderRadius: 6, padding: '0 10px', background: bg(0.015), border: border(0.04) }}>
            <Search style={{ width: 11, height: 11, color: '#444', flexShrink: 0 }} />
            <input value={searchQuery} onChange={e => onSearchChange(e.target.value)}
              placeholder="Search by name or #id..." style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 10, color: '#ccc', caretColor: '#888' }} />
            {searchQuery ? (
              <button onClick={() => onSearchChange('')} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
                <X style={{ width: 10, height: 10, color: '#555' }} />
              </button>
            ) : (
              <span style={{ fontSize: 8, color: '#333', fontVariantNumeric: 'tabular-nums', fontFamily: 'monospace' }}>{activeCat?.drawables ?? 0}</span>
            )}
          </div>
        </div>

        <div style={{ height: 1, background: bg(0.04) }} />

        {/* Grid */}
        <div className="flex-1 overflow-hidden relative" ref={gridRef}>
          {filteredItems.length > 0 && gridSize.height > 0 ? (
            <Grid className="scrollbar-thin" columnCount={COLS} columnWidth={CARD_W + GAP}
              height={gridSize.height} rowCount={ROWS} rowHeight={ROW_H}
              width={gridSize.width} overscanRowCount={3} itemData={itemData}>
              {Cell}
            </Grid>
          ) : (
            <div className="h-full flex flex-col items-center justify-center gap-2">
              <div style={{ width: 40, height: 40, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', background: bg(0.02), border: border(0.04) }}>
                <Search style={{ width: 14, height: 14, color: '#2a2a2a' }} />
              </div>
              <span style={{ fontSize: 10, color: '#444' }}>No items found</span>
              {searchQuery && <button onClick={() => onSearchChange('')} style={{ fontSize: 9, color: '#555', background: 'none', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}>Clear</button>}
            </div>
          )}
        </div>

        {/* Status bar */}
        <div style={{ height: 1, background: bg(0.04) }} />
        {recaptureMode ? (
          <div className="flex items-center gap-2 shrink-0" style={{ padding: '7px 12px', background: 'rgba(251,146,60,0.03)' }}>
            <RotateCcw style={{ width: 9, height: 9, color: '#fb923c', flexShrink: 0 }} />
            <span style={{ fontSize: 9, color: '#888', flex: 1 }}>
              {recaptureSet.size > 0 ? <><span style={{ color: '#fb923c', fontWeight: 700 }}>{recaptureSet.size}</span> selected</> : 'Click items to select for re-capture'}
            </span>
            {recaptureSet.size > 0 && (
              <button onClick={handleRecaptureStart} style={{ height: 20, padding: '0 10px', borderRadius: 4, fontSize: 9, fontWeight: 700, color: '#000', background: '#fb923c', border: 'none', cursor: 'pointer' }}>
                Re-capture
              </button>
            )}
            <button onClick={toggleRecaptureMode} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
              <X style={{ width: 9, height: 9, color: '#444' }} />
            </button>
          </div>
        ) : selectedItem ? (
          <div className="flex items-center gap-2 shrink-0" style={{ padding: '8px 12px' }}>
            <span style={{ width: 4, height: 4, borderRadius: '50%', flexShrink: 0, background: '#22c55e', boxShadow: '0 0 6px rgba(34,197,94,0.4)' }} />
            <span style={{ fontSize: 9, fontWeight: 500, color: '#888', flex: 1 }} className="truncate">{selectedItem.model || selectedItem.label}</span>
            <span style={{ fontSize: 8, color: '#555', fontFamily: 'monospace', background: bg(0.03), border: border(0.04), borderRadius: 3, padding: '1px 5px' }}>
              {selectedItem.model || selectedItem.collection || `#${selectedItem.drawable}`}
            </span>
          </div>
        ) : (
          <div className="flex items-center shrink-0" style={{ padding: '9px 12px' }}>
            <span style={{ fontSize: 9, color: '#2a2a2a' }}>Select an item to preview</span>
          </div>
        )}
      </div>
    </>
  )
}

export default ClothingMenu
