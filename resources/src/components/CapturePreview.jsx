/**
 * CapturePreview — Tabbed capture panel
 *   Ped tab: clothing/prop category toggles (original behavior)
 *   Cars tab: expandable vehicle class accordion with per-model checkboxes + color picker
 *   Objects tab: flat model checkbox list with search
 */

import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react'
import { FixedSizeGrid as Grid } from 'react-window'
import {
  Eye, Camera, Check, Play, Search, X,
  Shirt, HardHat, Glasses, Watch, Footprints, ShoppingBag,
  Shield, Paintbrush, Ear, Gem,
  Car, Box, User, Palette, ChevronRight, ChevronDown, RotateCcw,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Switch }     from './ui/switch'
import { ScrollArea } from './ui/scroll-area'

// ── Icon maps ───────────────────────────────────────────
export const CAT_ICON_MAP = {
  'Mask': HardHat, 'Arms / Gloves': Shirt, 'Pants': Shirt,
  'Bags': ShoppingBag, 'Shoes': Footprints, 'Accessories': Gem,
  'Undershirt': Shirt, 'Body Armor': Shield, 'Decals': Paintbrush,
  'Tops': Shirt, 'Hats': HardHat, 'Glasses': Glasses,
  'Ears': Ear, 'Watches': Watch, 'Bracelets': Gem,
  'Hair': User, 'Blemishes': Paintbrush, 'Facial Hair': User,
  'Eyebrows': Eye, 'Ageing': Paintbrush, 'Makeup': Paintbrush,
  'Blush': Paintbrush, 'Complexion': Paintbrush, 'Sun Damage': Paintbrush,
  'Lipstick': Paintbrush, 'Moles & Freckles': Paintbrush,
  'Chest Hair': User, 'Body Blemishes': Paintbrush,
}
export const CAT_TYPE_ICON = {
  'component': Shirt, 'prop': HardHat, 'overlay': Paintbrush, 'vehicle': Car, 'object': Box,
}

// ── Tabs ────────────────────────────────────────────────
const TABS = [
  { id: 'ped',        label: 'Ped',        icon: User,       types: ['component', 'prop'] },
  { id: 'appearance', label: 'Appearance', icon: Paintbrush, types: ['overlay'] },
  { id: 'cars',       label: 'Cars',       icon: Car,        types: ['vehicle'] },
  { id: 'objects',    label: 'Objects',    icon: Box,        types: ['object'] },
]

// ── Vehicle Colors ──────────────────────────────────────
const VEHICLE_COLORS = [
  { id: 0,   label: 'Black',        hex: '#0d1116' },
  { id: 1,   label: 'Graphite',     hex: '#1c2024' },
  { id: 12,  label: 'Black Steel',  hex: '#333333' },
  { id: 4,   label: 'Silver',       hex: '#99a0a7' },
  { id: 6,   label: 'Stone Silver', hex: '#c8cdcf' },
  { id: 111, label: 'White',        hex: '#f0f0f0' },
  { id: 27,  label: 'Red',          hex: '#c40018' },
  { id: 28,  label: 'Torino Red',   hex: '#d0021b' },
  { id: 35,  label: 'Dark Green',   hex: '#132428' },
  { id: 49,  label: 'Green',        hex: '#418555' },
  { id: 61,  label: 'Galaxy Blue',  hex: '#2d547a' },
  { id: 64,  label: 'Blue',         hex: '#47578f' },
  { id: 88,  label: 'Yellow',       hex: '#dadf46' },
  { id: 89,  label: 'Race Yellow',  hex: '#f5890f' },
  { id: 38,  label: 'Orange',       hex: '#c85a2b' },
  { id: 120, label: 'Pink',         hex: '#df5fa3' },
  { id: 145, label: 'Chrome',       hex: '#dfe0e0' },
  { id: 131, label: 'Matte Black',  hex: '#151921' },
]

// ── Helpers ─────────────────────────────────────────────
const border = (o = 0.06) => `1px solid rgba(255,255,255,${o})`
const bg     = (o = 0.03) => `rgba(255,255,255,${o})`

// ── Checkbox ────────────────────────────────────────────
function Checkbox({ checked, onChange, size = 14 }) {
  return (
    <div
      onClick={e => { e.stopPropagation(); onChange?.(!checked) }}
      className="flex items-center justify-center cursor-pointer transition-all"
      style={{
        width: size, height: size, borderRadius: 3, flexShrink: 0,
        background: checked ? '#f5f5f5' : 'transparent',
        border: checked ? 'none' : '1px solid rgba(255,255,255,0.15)',
      }}
    >
      {checked && <Check style={{ width: size - 4, height: size - 4, color: '#111' }} strokeWidth={3} />}
    </div>
  )
}

// ── Browse Thumbnail ────────────────────────────────────
const THUMB_BASE = 'https://cfx-nui-uz_AutoShot/shots/'
const CARD_W = 84, GRID_GAP = 4

const BrowseThumb = React.memo(({ item, isSelected, onClick, ext, recaptureMode, recaptureSelected }) => {
  const [src, setSrc] = useState(null)
  const [error, setError] = useState(false)
  const texSuffix = item.texture > 0 ? `_${item.texture}` : ''
  const thumbName = item.type === 'vehicle' ? `vehicles/${item.model || item.id}.${ext}`
    : item.type === 'object' ? `objects/${item.model || item.id}.${ext}`
    : item.type === 'overlay' ? `${item.gender}/overlay_${item.id}/${item.drawable}.${ext}`
    : item.type === 'prop' ? `${item.gender}/prop_${item.id}/${item.drawable}${texSuffix}.${ext}`
    : `${item.gender}/${item.id}/${item.drawable}${texSuffix}.${ext}`
  const displayLabel = item.model || `#${item.drawable}`

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
      style={{ borderRadius: 6, width: '100%', height: '100%', background: active ? `${accent}06` : 'rgba(255,255,255,0.012)', border: `1px solid ${active ? `${accent}30` : 'rgba(255,255,255,0.04)'}`, display: 'flex', flexDirection: 'column' }}
      onClick={() => onClick(item)}>
      <div style={{ position: 'relative', flex: '1 1 0', minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', background: 'rgba(0,0,0,0.15)' }}>
        {!src && !error && <div style={{ position: 'absolute', inset: 0 }} className="skeleton" />}
        {error && <span style={{ fontSize: 7, color: '#333' }}>{displayLabel}</span>}
        {src && <img src={src} alt="" draggable={false} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'contain', padding: 3 }} />}
        {recaptureSelected && <div style={{ position: 'absolute', top: 2, right: 2, width: 12, height: 12, borderRadius: '50%', background: '#fb923c', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><RotateCcw style={{ width: 6, height: 6, color: '#000' }} strokeWidth={3} /></div>}
        {!recaptureMode && isSelected && <div style={{ position: 'absolute', top: 2, right: 2, width: 12, height: 12, borderRadius: '50%', background: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check style={{ width: 6, height: 6, color: '#000' }} strokeWidth={3} /></div>}
      </div>
      <div style={{ height: 14, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', borderTop: '1px solid rgba(255,255,255,0.02)', background: 'rgba(0,0,0,0.2)' }}>
        <span style={{ fontSize: item.model ? 6 : 7, fontWeight: active ? 700 : 500, color: active ? '#ccc' : '#444' }} className="truncate">{displayLabel}</span>
      </div>
    </div>
  )
})

function BrowseCell({ columnIndex, rowIndex, style, data }) {
  const { items, selectedItem, onSelect, ext, recaptureMode, recaptureSet, toggleRecapture, COLS } = data
  const idx = rowIndex * COLS + columnIndex
  if (idx >= items.length) return null
  const item = items[idx]
  const sel = !recaptureMode && selectedItem && selectedItem.type === item.type && selectedItem.id === item.id && selectedItem.drawable === item.drawable && selectedItem.texture === item.texture
  return (
    <div style={{ ...style, left: +style.left + GRID_GAP, top: +style.top + GRID_GAP, width: +style.width - GRID_GAP, height: +style.height - GRID_GAP }}>
      <BrowseThumb item={item} isSelected={sel} ext={ext}
        onClick={recaptureMode ? toggleRecapture : onSelect}
        recaptureMode={recaptureMode} recaptureSelected={recaptureMode && recaptureSet?.has(`${item.type}-${item.id}-${item.drawable}-${item.texture}`)} />
    </div>
  )
}

// ════════════════════════════════════════════════════════
// CapturePreview
// ════════════════════════════════════════════════════════
export function CapturePreview({
  categories = [],
  mode = 'capture',  // 'capture' | 'browse'
  onStart, onCancel, onActiveChange, onSaveAngle, onColorChange,
  gender = 'male', onGenderChange,
  // browse mode props
  browseItems, browseSelectedItem, onBrowseSelect, browseImgExt,
  browseSearch, onBrowseSearchChange, onRecapture,
}) {
  // ── Ped tab state ─────────────────────────────────
  const [activeKey, setActiveKey]       = useState(categories[0]?.key ?? null)
  const [selected, setSelected]         = useState(() => new Set())
  const [savedCameras, setSavedCameras] = useState(() => new Set())
  const [bothGenders, setBothGenders]   = useState(false)
  const [switchingGender, setSwitchingGender] = useState(false)

  // Mirrors AngleKey in client.lua: ped framings are saved per gender
  const camKey = useCallback((cam) => (cam === 'vehicle' || cam === 'object') ? cam : `${gender}:${cam}`, [gender])

  const [pedSearch, setPedSearch]                   = useState('')
  const [expandedPedGroups, setExpandedPedGroups]   = useState(() => new Set(['components', 'props']))

  // ── Appearance tab state ──────────────────────────
  const [appearanceSearch, setAppearanceSearch] = useState('')

  // ── Cars tab state ────────────────────────────────
  const [expandedClasses, setExpandedClasses] = useState(() => new Set())
  const [selectedModels, setSelectedModels]   = useState(() => new Set())
  const [vehicleSearch, setVehicleSearch]     = useState('')
  const [colorTarget, setColorTarget]         = useState(null)
  const [vehicleColors, setVehicleColors]     = useState({ primary: 0, secondary: 0 })

  // ── Objects tab state ─────────────────────────────
  const [selectedObjects, setSelectedObjects] = useState(() => new Set())
  const [objectSearch, setObjectSearch]       = useState('')

  // ── Browse mode state ──────────────────────────────
  const [recaptureMode, setRecaptureMode] = useState(false)
  const [recaptureSet, setRecaptureSet]   = useState(new Set())
  const gridRef = useRef(null)
  const [gridSize, setGridSize] = useState({ width: 0, height: 0 })

  // ESC to close (browse mode)
  useEffect(() => {
    if (mode !== 'browse') return
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); onCancel?.() } }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [mode, onCancel])

  // Grid measurement
  useEffect(() => {
    if (mode !== 'browse') return
    const measure = () => { if (gridRef.current) { const r = gridRef.current.getBoundingClientRect(); setGridSize({ width: r.width, height: r.height }) } }
    measure(); const t = setTimeout(measure, 50); window.addEventListener('resize', measure)
    return () => { window.removeEventListener('resize', measure); clearTimeout(t) }
  }, [mode, browseItems])

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

  const COLS = Math.max(1, Math.floor(((gridSize.width || 300) - GRID_GAP) / (CARD_W + GRID_GAP)))
  const ROWS = Math.ceil((browseItems?.length || 0) / COLS)
  const ROW_H = CARD_W + GRID_GAP + 14

  const gridData = useMemo(() => ({
    items: browseItems || [], selectedItem: browseSelectedItem, onSelect: onBrowseSelect, ext: browseImgExt || 'png',
    recaptureMode, recaptureSet, toggleRecapture: toggleRecaptureItem, COLS,
  }), [browseItems, browseSelectedItem, onBrowseSelect, browseImgExt, recaptureMode, recaptureSet, toggleRecaptureItem, COLS])

  // ── Tab state ─────────────────────────────────────
  const [activeTab, setActiveTab] = useState('ped')

  // ── Derived data ──────────────────────────────────
  const pedCategories = useMemo(() => categories.filter(c => c.type === 'component' || c.type === 'prop'), [categories])
  const overlayCategories = useMemo(() => categories.filter(c => c.type === 'overlay'), [categories])
  const vehicleClasses = useMemo(() => categories.filter(c => c.type === 'vehicle' && c.models), [categories])
  const objectCategories = useMemo(() => categories.filter(c => c.type === 'object'), [categories])

  // All vehicle models flat
  const allVehicleModels = useMemo(() => {
    const all = []
    vehicleClasses.forEach(vc => { vc.models?.forEach(m => all.push({ model: m, className: vc.label })) })
    return all
  }, [vehicleClasses])

  // Filtered vehicles by search
  const filteredVehicleClasses = useMemo(() => {
    if (!vehicleSearch.trim()) return vehicleClasses
    const q = vehicleSearch.trim().toLowerCase()
    return vehicleClasses.map(vc => ({
      ...vc,
      models: vc.models.filter(m => m.toLowerCase().includes(q)),
    })).filter(vc => vc.models.length > 0)
  }, [vehicleClasses, vehicleSearch])

  // Filtered objects by search
  const filteredObjects = useMemo(() => {
    if (!objectSearch.trim()) return objectCategories
    const q = objectSearch.trim().toLowerCase()
    return objectCategories.filter(c => c.id.toLowerCase().includes(q) || c.label.toLowerCase().includes(q))
  }, [objectCategories, objectSearch])

  // Counts
  const pedSelectedCount = useMemo(() => pedCategories.filter(c => selected.has(c.key)).length, [pedCategories, selected])
  const overlaySelectedCount = useMemo(() => overlayCategories.filter(c => selected.has(c.key)).length, [overlayCategories, selected])
  const vehicleSelectedCount = selectedModels.size
  const objectSelectedCount = selectedObjects.size
  const totalSelected = pedSelectedCount + overlaySelectedCount + vehicleSelectedCount + objectSelectedCount

  const tabCounts = useMemo(() => ({
    ped: pedSelectedCount,
    appearance: overlaySelectedCount,
    cars: vehicleSelectedCount,
    objects: objectSelectedCount,
  }), [pedSelectedCount, overlaySelectedCount, vehicleSelectedCount, objectSelectedCount])

  // ── Ped handlers ──────────────────────────────────
  const handlePedToggle = useCallback((key) => {
    setSelected(prev => { const n = new Set(prev); n.has(key) ? n.delete(key) : n.add(key); return n })
  }, [])

  const handleRowClick = useCallback((cat) => {
    setActiveKey(cat.key)
    onActiveChange?.(cat)
  }, [onActiveChange])

  const handleSaveAngle = useCallback(() => {
    const activeCat = categories.find(c => c.key === activeKey)
    if (!activeCat?.camera) return
    onSaveAngle?.(activeCat.camera)
    setSavedCameras(prev => { const n = new Set(prev); n.add(camKey(activeCat.camera)); return n })
  }, [activeKey, categories, onSaveAngle, camKey])

  // Per-row camera icon. The orbit only shows the active row's preset, so
  // saving from any other row would file that framing under the wrong camera:
  // first click selects the row, the next one saves.
  const handleRowSave = useCallback((cat) => {
    if (cat.key !== activeKey) { handleRowClick(cat); return }
    onSaveAngle?.(cat.camera)
    setSavedCameras(prev => { const n = new Set(prev); n.add(camKey(cat.camera)); return n })
  }, [activeKey, handleRowClick, onSaveAngle, camKey])

  const handleGenderClick = useCallback(async (g) => {
    if (g === gender || switchingGender) return
    setSwitchingGender(true)
    try {
      await onGenderChange?.(g)
      // The new ped comes in bare; re-apply the active ped/overlay category
      const activeCat = categories.find(c => c.key === activeKey)
      if (activeCat && ['component', 'prop', 'overlay'].includes(activeCat.type)) onActiveChange?.(activeCat)
    } finally {
      setSwitchingGender(false)
    }
  }, [gender, switchingGender, onGenderChange, categories, activeKey, onActiveChange])

  const pedSelectAll  = useCallback(() => setSelected(prev => { const n = new Set(prev); pedCategories.forEach(c => n.add(c.key)); return n }), [pedCategories])
  const pedSelectNone = useCallback(() => setSelected(prev => { const n = new Set(prev); pedCategories.forEach(c => n.delete(c.key)); return n }), [pedCategories])

  const overlaySelectAll  = useCallback(() => setSelected(prev => { const n = new Set(prev); overlayCategories.forEach(c => n.add(c.key)); return n }), [overlayCategories])
  const overlaySelectNone = useCallback(() => setSelected(prev => { const n = new Set(prev); overlayCategories.forEach(c => n.delete(c.key)); return n }), [overlayCategories])

  const togglePedGroup = useCallback((key) => {
    setExpandedPedGroups(prev => { const n = new Set(prev); n.has(key) ? n.delete(key) : n.add(key); return n })
  }, [])

  // ── Vehicle handlers ──────────────────────────────
  const toggleClass = useCallback((cls) => {
    setExpandedClasses(prev => { const n = new Set(prev); n.has(cls) ? n.delete(cls) : n.add(cls); return n })
  }, [])

  const toggleModel = useCallback((model) => {
    setSelectedModels(prev => { const n = new Set(prev); n.has(model) ? n.delete(model) : n.add(model); return n })
  }, [])

  const toggleAllInClass = useCallback((models, selectAll) => {
    setSelectedModels(prev => {
      const n = new Set(prev)
      models.forEach(m => selectAll ? n.add(m) : n.delete(m))
      return n
    })
  }, [])

  const vehicleSelectAll  = useCallback(() => setSelectedModels(new Set(allVehicleModels.map(v => v.model))), [allVehicleModels])
  const vehicleSelectNone = useCallback(() => setSelectedModels(new Set()), [])

  const handleColorSelect = useCallback((colorId) => {
    if (!colorTarget) return
    const next = { ...vehicleColors, [colorTarget]: colorId }
    setVehicleColors(next)
    onColorChange?.(next)
    setColorTarget(null)
  }, [colorTarget, vehicleColors, onColorChange])

  // ── Object handlers ───────────────────────────────
  const toggleObject = useCallback((id) => {
    setSelectedObjects(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n })
  }, [])

  const objectSelectAll  = useCallback(() => setSelectedObjects(new Set(objectCategories.map(c => c.id))), [objectCategories])
  const objectSelectNone = useCallback(() => setSelectedObjects(new Set()), [])

  // ── Camera save for vehicle/object ─────────────────
  const handleSaveEntityAngle = useCallback(() => {
    const cam = activeTab === 'cars' ? 'vehicle' : 'object'
    onSaveAngle?.(cam)
    setSavedCameras(prev => { const n = new Set(prev); n.add(cam); return n })
  }, [activeTab, onSaveAngle])

  // ── Tab change ────────────────────────────────────
  const handleTabChange = useCallback((tabId) => {
    setActiveTab(tabId)
    setColorTarget(null)
  }, [])

  // ── Start ─────────────────────────────────────────
  const handleStart = useCallback(() => {
    if (totalSelected === 0) return
    const chosen = []
    // Ped categories
    pedCategories.filter(c => selected.has(c.key)).forEach(c => chosen.push(c))
    // Overlay categories
    overlayCategories.filter(c => selected.has(c.key)).forEach(c => chosen.push(c))
    // Vehicle models
    if (selectedModels.size > 0) chosen.push({ type: 'vehicle', id: '__models__', models: Array.from(selectedModels) })
    // Object models
    if (selectedObjects.size > 0) chosen.push({ type: 'object', id: '__models__', models: Array.from(selectedObjects) })
    onStart?.(chosen, { bothGenders: bothGenders && pedSelectedCount + overlaySelectedCount > 0 })
  }, [pedCategories, overlayCategories, selected, selectedModels, selectedObjects, totalSelected, onStart, bothGenders, pedSelectedCount, overlaySelectedCount])

  const isBrowse = mode === 'browse'

  // ════════════════════════════════════════════════════
  // RENDER
  // ════════════════════════════════════════════════════
  return (
    <div className="glass rounded-xl overflow-hidden animate-enter flex flex-col"
      style={{ width: isBrowse ? 290 : 380, height: isBrowse ? '100%' : 'auto', border: border(), boxShadow: '0 8px 40px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.02)' }}>

      <div className={isBrowse ? 'flex-1 flex flex-col overflow-hidden' : 'm-3 rounded-lg overflow-hidden'} style={isBrowse ? {} : { border: border(0.04), background: bg(0.01) }}>

        {/* Header */}
        <div style={{ padding: '14px 20px 8px' }}>
          <div className="flex items-center justify-between">
            <div>
              <h3 style={{ fontSize: 16, fontWeight: 700, color: '#eee', letterSpacing: '-0.02em' }}>
                {isBrowse ? 'AutoShot' : 'Capture Preview'}
              </h3>
              <p style={{ fontSize: 9, color: '#555', marginTop: 1 }}>
                {isBrowse ? 'Studio Catalog' : 'Drag to rotate · Scroll to zoom'}
              </p>
            </div>
            {isBrowse && (
              <button onClick={onCancel} className="flex items-center justify-center cursor-pointer hover:bg-white/[0.04]"
                style={{ width: 22, height: 22, borderRadius: 5, border: 'none', background: 'transparent', color: '#555' }}>
                <X style={{ width: 10, height: 10 }} />
              </button>
            )}
            {!isBrowse && onGenderChange && (
              <div className="flex gap-0.5" style={{ background: bg(0.02), borderRadius: 6, padding: 2, border: border(0.04), opacity: switchingGender ? 0.5 : 1 }}>
                {[['male', 'Male'], ['female', 'Female']].map(([g, label]) => {
                  const isActive = gender === g
                  return (
                    <button key={g} onClick={() => handleGenderClick(g)} disabled={switchingGender}
                      style={{
                        height: 22, padding: '0 9px', borderRadius: 4, border: 'none',
                        cursor: switchingGender ? 'wait' : 'pointer',
                        fontSize: 10, fontWeight: isActive ? 700 : 500,
                        background: isActive ? 'rgba(255,255,255,0.08)' : 'transparent',
                        color: isActive ? '#eee' : '#555',
                      }}>
                      {label}
                    </button>
                  )
                })}
              </div>
            )}
          </div>
        </div>

        {/* Tab bar */}
        <div style={{ padding: '0 20px 8px' }}>
          <div className="flex gap-1" style={{ background: bg(0.02), borderRadius: 7, padding: 3, border: border(0.04) }}>
            {TABS.map(tab => {
              const isActive = activeTab === tab.id
              const count = tabCounts[tab.id] || 0
              const TabIcon = tab.icon
              const hasItems = tab.id === 'ped' ? pedCategories.length > 0
                : tab.id === 'appearance' ? overlayCategories.length > 0
                : tab.id === 'cars' ? vehicleClasses.length > 0
                : objectCategories.length > 0
              if (!hasItems) return null
              return (
                <button key={tab.id} onClick={() => handleTabChange(tab.id)}
                  className="flex items-center justify-center gap-1 flex-1 transition-all"
                  style={{
                    height: 26, borderRadius: 5, border: 'none', cursor: 'pointer',
                    fontSize: 10, fontWeight: isActive ? 700 : 500,
                    background: isActive ? 'rgba(255,255,255,0.08)' : 'transparent',
                    color: isActive ? '#eee' : '#555',
                    boxShadow: isActive ? '0 1px 4px rgba(0,0,0,0.3)' : 'none',
                    minWidth: 0, overflow: 'hidden',
                  }}>
                  <TabIcon style={{ width: 10, height: 10, flexShrink: 0 }} />
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{tab.label}</span>
                  {count > 0 && (
                    <span style={{
                      fontSize: 8, fontWeight: 700, color: isActive ? '#fff' : '#888',
                      background: isActive ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.04)',
                      borderRadius: 3, padding: '0 4px', minWidth: 14, textAlign: 'center', flexShrink: 0,
                    }}>{count}</span>
                  )}
                </button>
              )
            })}
          </div>
        </div>

        <div style={{ height: 1, background: 'rgba(255,255,255,0.04)' }} />

        {/* ═══ PED TAB ═══ */}
        {activeTab === 'ped' && (() => {
          const compCats = pedCategories.filter(c => c.type === 'component')
          const propCats = pedCategories.filter(c => c.type === 'prop')
          const pedGroups = [
            { key: 'components', label: 'Clothing',    icon: Shirt, cats: compCats },
            { key: 'props',      label: 'Accessories', icon: Gem,   cats: propCats },
          ].filter(g => g.cats.length > 0)

          return (
            <>
              {/* Search */}
              <div style={{ padding: '8px 20px 6px' }}>
                <div className="flex items-center gap-2" style={{ height: 28, borderRadius: 6, padding: '0 8px', background: bg(0.015), border: border(0.04) }}>
                  <Search style={{ width: 10, height: 10, color: '#444', flexShrink: 0 }} />
                  <input value={pedSearch} onChange={e => setPedSearch(e.target.value)}
                    placeholder="Search categories..." style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 10, color: '#ccc', caretColor: '#888' }} />
                  {pedSearch && (
                    <button onClick={() => setPedSearch('')} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
                      <X style={{ width: 9, height: 9, color: '#555' }} />
                    </button>
                  )}
                </div>
              </div>

              <div style={{ height: 1, background: 'rgba(255,255,255,0.04)' }} />

              {/* Count + All/None */}
              <div className="flex items-center justify-between" style={{ padding: '6px 20px 4px' }}>
                <span style={{ fontSize: 10, color: '#555' }}>
                  <span style={{ color: '#999', fontWeight: 600 }}>{pedSelectedCount}</span> / {pedCategories.length} categories
                </span>
                <div className="flex items-center gap-1.5">
                  <button onClick={pedSelectAll} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>All</button>
                  <span style={{ fontSize: 10, color: '#333' }}>·</span>
                  <button onClick={pedSelectNone} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>None</button>
                </div>
              </div>

              {/* Grouped accordion */}
              <div className={isBrowse ? 'flex-1 overflow-hidden' : ''} style={{ padding: '2px 20px 10px' }}>
                <ScrollArea style={{ height: isBrowse ? '100%' : 240 }}>
                  <div className="flex flex-col gap-0.5">
                    {pedGroups.map(group => {
                      const isExpanded = expandedPedGroups.has(group.key) || pedSearch.trim().length > 0
                      const filteredCats = pedSearch.trim()
                        ? group.cats.filter(c => c.label.toLowerCase().includes(pedSearch.trim().toLowerCase()))
                        : group.cats
                      if (filteredCats.length === 0) return null
                      const selCount = filteredCats.filter(c => selected.has(c.key)).length
                      const allSel = selCount === filteredCats.length
                      const GroupIcon = group.icon

                      return (
                        <div key={group.key}>
                          {/* Group header */}
                          <div onClick={() => togglePedGroup(group.key)}
                            className="flex items-center gap-1.5 cursor-pointer select-none transition-all"
                            style={{
                              height: 26, padding: '0 6px', borderRadius: 5,
                              background: isExpanded ? bg(0.03) : 'transparent',
                              border: isExpanded ? border(0.06) : '1px solid transparent',
                              opacity: selCount > 0 ? 1 : 0.6,
                            }}>
                            {isExpanded
                              ? <ChevronDown style={{ width: 10, height: 10, color: '#666', flexShrink: 0 }} />
                              : <ChevronRight style={{ width: 10, height: 10, color: '#444', flexShrink: 0 }} />
                            }
                            <GroupIcon style={{ width: 9, height: 9, color: selCount > 0 ? '#888' : '#444', flexShrink: 0 }} />
                            <span className="flex-1 truncate" style={{ fontSize: 10, fontWeight: 600, color: '#ddd' }}>{group.label}</span>
                            <span style={{ fontSize: 8, color: selCount > 0 ? '#999' : '#444', fontVariantNumeric: 'tabular-nums' }}>
                              {selCount}/{filteredCats.length}
                            </span>
                            <Checkbox checked={allSel} onChange={(v) => {
                              setSelected(prev => {
                                const n = new Set(prev)
                                filteredCats.forEach(c => v ? n.add(c.key) : n.delete(c.key))
                                return n
                              })
                            }} size={13} />
                          </div>

                          {/* Expanded items */}
                          {isExpanded && (
                            <div style={{ paddingLeft: 14, borderLeft: '1px solid rgba(255,255,255,0.04)', marginLeft: 10, marginTop: 1, marginBottom: 2 }}>
                              {filteredCats.map(cat => {
                                const isOn = selected.has(cat.key)
                                const isSaved = savedCameras.has(camKey(cat.camera))
                                const isActive = activeKey === cat.key
                                const CatIcon = CAT_ICON_MAP[cat.label] ?? Shirt
                                return (
                                  <div key={cat.key}
                                    onClick={() => {
                                      handleRowClick(cat)
                                    }}
                                    className="flex items-center gap-2 cursor-pointer select-none transition-all hover:opacity-100"
                                    style={{ height: 24, padding: '0 6px', borderRadius: 4, opacity: isOn ? 1 : 0.5,
                                      background: isActive ? bg(0.04) : 'transparent',
                                      border: isActive ? border(0.08) : '1px solid transparent',
                                    }}>
                                    <Checkbox checked={isOn} onChange={() => handlePedToggle(cat.key)} size={12} />
                                    <CatIcon style={{ width: 9, height: 9, color: '#666', flexShrink: 0 }} />
                                    <span className="flex-1 truncate" style={{ fontSize: 9, fontWeight: 500, color: '#ccc' }}>{cat.label}</span>
                                    {isSaved && <Check style={{ width: 8, height: 8, color: '#22c55e', flexShrink: 0 }} />}
                                    <div onClick={e => { e.stopPropagation(); handleRowSave(cat) }}
                                      title={isActive ? 'Save camera angle' : 'Select to adjust the camera, click again to save'}
                                      className="flex items-center justify-center hover:bg-white/[0.06]"
                                      style={{ width: 16, height: 16, borderRadius: 3, cursor: 'pointer', flexShrink: 0 }}>
                                      <Camera style={{ width: 8, height: 8, color: isSaved ? '#22c55e' : '#666' }} />
                                    </div>
                                  </div>
                                )
                              })}
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </ScrollArea>
              </div>
            </>
          )
        })()}

        {/* ═══ APPEARANCE TAB ═══ */}
        {activeTab === 'appearance' && (() => {
          const filteredOverlays = appearanceSearch.trim()
            ? overlayCategories.filter(c => c.label.toLowerCase().includes(appearanceSearch.trim().toLowerCase()))
            : overlayCategories

          return (
            <>
              {/* Search */}
              <div style={{ padding: '8px 20px 6px' }}>
                <div className="flex items-center gap-2" style={{ height: 28, borderRadius: 6, padding: '0 8px', background: bg(0.015), border: border(0.04) }}>
                  <Search style={{ width: 10, height: 10, color: '#444', flexShrink: 0 }} />
                  <input value={appearanceSearch} onChange={e => setAppearanceSearch(e.target.value)}
                    placeholder="Search overlays..." style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 10, color: '#ccc', caretColor: '#888' }} />
                  {appearanceSearch && (
                    <button onClick={() => setAppearanceSearch('')} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
                      <X style={{ width: 9, height: 9, color: '#555' }} />
                    </button>
                  )}
                </div>
              </div>

              <div style={{ height: 1, background: 'rgba(255,255,255,0.04)' }} />

              {/* Count + All/None */}
              <div className="flex items-center justify-between" style={{ padding: '6px 20px 4px' }}>
                <span style={{ fontSize: 10, color: '#555' }}>
                  <span style={{ color: '#999', fontWeight: 600 }}>{overlaySelectedCount}</span> / {overlayCategories.length} categories
                </span>
                <div className="flex items-center gap-1.5">
                  <button onClick={overlaySelectAll} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>All</button>
                  <span style={{ fontSize: 10, color: '#333' }}>·</span>
                  <button onClick={overlaySelectNone} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>None</button>
                </div>
              </div>

              {/* Category list */}
              <div className={isBrowse ? 'flex-1 overflow-hidden' : ''} style={{ padding: '2px 20px 10px' }}>
                <ScrollArea style={{ height: isBrowse ? '100%' : 240 }}>
                  <div className="flex flex-col gap-0.5">
                    {filteredOverlays.map(cat => {
                      const isOn = selected.has(cat.key)
                      const isSaved = savedCameras.has(camKey(cat.camera))
                      const CatIcon = CAT_ICON_MAP[cat.label] ?? Paintbrush
                      return (
                        <div key={cat.key}
                          onClick={() => handleRowClick(cat)}
                          className="flex items-center gap-2 cursor-pointer select-none transition-all hover:opacity-100"
                          style={{ height: 28, padding: '0 8px', borderRadius: 5, opacity: isOn ? 1 : 0.5,
                            background: activeKey === cat.key ? bg(0.04) : 'transparent',
                            border: activeKey === cat.key ? border(0.08) : '1px solid transparent',
                          }}>
                          <Checkbox checked={isOn} onChange={() => handlePedToggle(cat.key)} size={13} />
                          <CatIcon style={{ width: 10, height: 10, color: '#666', flexShrink: 0 }} />
                          <span className="flex-1 truncate" style={{ fontSize: 10, fontWeight: 500, color: '#ccc' }}>{cat.label}</span>
                          {isSaved && <Camera style={{ width: 8, height: 8, color: '#22c55e', flexShrink: 0 }} />}
                          {!isBrowse && (
                            <span style={{ fontSize: 8, color: '#444', fontVariantNumeric: 'tabular-nums' }}>
                              ID {cat.id}
                            </span>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </ScrollArea>
              </div>

              {/* Save angle button */}
              {!isBrowse && (
                <div style={{ padding: '6px 20px 10px' }}>
                  <button onClick={handleSaveAngle}
                    className="flex items-center justify-center gap-1.5 w-full"
                    style={{ height: 28, borderRadius: 6, fontSize: 10, fontWeight: 600, color: '#888', background: bg(0.02), border: border(0.06), cursor: 'pointer' }}>
                    <Camera style={{ width: 9, height: 9 }} />
                    Save Camera Angle
                  </button>
                </div>
              )}
            </>
          )
        })()}

        {/* ═══ CARS TAB ═══ */}
        {activeTab === 'cars' && (
          <>
            {/* Search */}
            <div style={{ padding: '8px 20px 6px' }}>
              <div className="flex items-center gap-2" style={{ height: 28, borderRadius: 6, padding: '0 8px', background: bg(0.015), border: border(0.04) }}>
                <Search style={{ width: 10, height: 10, color: '#444', flexShrink: 0 }} />
                <input value={vehicleSearch} onChange={e => setVehicleSearch(e.target.value)}
                  placeholder="Search vehicles..." style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 10, color: '#ccc', caretColor: '#888' }} />
                {vehicleSearch && (
                  <button onClick={() => setVehicleSearch('')} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
                    <X style={{ width: 9, height: 9, color: '#555' }} />
                  </button>
                )}
              </div>
            </div>

            {/* Color picker */}
            <div style={{ padding: '4px 20px 6px' }}>
              <div className="flex items-center gap-2" style={{ marginBottom: colorTarget ? 6 : 0 }}>
                <Palette style={{ width: 10, height: 10, color: '#555' }} />
                <span style={{ fontSize: 8, color: '#555', fontWeight: 600, flex: 1 }}>COLOR</span>
                {['primary', 'secondary'].map(t => (
                  <button key={t} onClick={() => setColorTarget(colorTarget === t ? null : t)}
                    title={t === 'primary' ? 'Primary Color' : 'Secondary Color'}
                    className="flex items-center justify-center transition-all"
                    style={{ width: 20, height: 20, borderRadius: 4, cursor: 'pointer', flexShrink: 0,
                      background: colorTarget === t ? bg(0.08) : 'transparent',
                      border: `1px solid ${colorTarget === t ? 'rgba(255,255,255,0.15)' : 'rgba(255,255,255,0.04)'}` }}>
                    <span style={{ width: 10, height: 10, borderRadius: 3, background: VEHICLE_COLORS.find(c => c.id === vehicleColors[t])?.hex || '#0d1116', border: '1px solid rgba(255,255,255,0.2)' }} />
                  </button>
                ))}
              </div>
              {colorTarget && (
                <div className="flex flex-wrap gap-1" style={{ paddingBottom: 2 }}>
                  {VEHICLE_COLORS.map((c, i) => {
                    const sel = vehicleColors[colorTarget] === c.id
                    return <button key={`${c.id}-${i}`} onClick={() => handleColorSelect(c.id)} title={c.label}
                      style={{ width: 18, height: 18, borderRadius: 4, cursor: 'pointer', background: c.hex, border: sel ? '2px solid #fff' : '1px solid rgba(255,255,255,0.12)', boxShadow: sel ? '0 0 6px rgba(255,255,255,0.3)' : 'none' }} />
                  })}
                </div>
              )}
            </div>

            <div style={{ height: 1, background: 'rgba(255,255,255,0.04)' }} />

            {/* All/None + count + camera save */}
            <div className="flex items-center justify-between" style={{ padding: '6px 20px 4px' }}>
              <span style={{ fontSize: 10, color: '#555' }}>
                <span style={{ color: '#999', fontWeight: 600 }}>{vehicleSelectedCount}</span> / {allVehicleModels.length} vehicles
              </span>
              <div className="flex items-center gap-1.5">
                <div onClick={handleSaveEntityAngle} title="Save camera angle for all vehicles"
                  className="flex items-center justify-center cursor-pointer hover:bg-white/[0.06]"
                  style={{ width: 20, height: 20, borderRadius: 4, flexShrink: 0 }}>
                  <Camera style={{ width: 10, height: 10, color: savedCameras.has('vehicle') ? '#22c55e' : '#666' }} />
                </div>
                <span style={{ fontSize: 10, color: '#333' }}>|</span>
                <button onClick={vehicleSelectAll} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>All</button>
                <span style={{ fontSize: 10, color: '#333' }}>·</span>
                <button onClick={vehicleSelectNone} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>None</button>
              </div>
            </div>

            {/* Class accordion */}
            <div className={isBrowse ? 'flex-1 overflow-hidden' : ''} style={{ padding: '2px 20px 10px' }}>
              <ScrollArea style={{ height: isBrowse ? '100%' : 240 }}>
                <div className="flex flex-col gap-0.5">
                  {filteredVehicleClasses.map(vc => {
                    const isExpanded = expandedClasses.has(vc.label) || vehicleSearch.trim().length > 0
                    const classModels = vc.models || []
                    const selCount = classModels.filter(m => selectedModels.has(m)).length
                    const allSel = selCount === classModels.length && classModels.length > 0
                    const someSel = selCount > 0

                    return (
                      <div key={vc.key}>
                        {/* Class header */}
                        <div onClick={() => toggleClass(vc.label)}
                          className="flex items-center gap-1.5 cursor-pointer select-none transition-all"
                          style={{
                            height: 26, padding: '0 6px', borderRadius: 5,
                            background: isExpanded ? bg(0.03) : 'transparent',
                            border: isExpanded ? border(0.06) : '1px solid transparent',
                            opacity: someSel ? 1 : 0.6,
                          }}>
                          {isExpanded
                            ? <ChevronDown style={{ width: 10, height: 10, color: '#666', flexShrink: 0 }} />
                            : <ChevronRight style={{ width: 10, height: 10, color: '#444', flexShrink: 0 }} />
                          }
                          <Car style={{ width: 9, height: 9, color: someSel ? '#888' : '#444', flexShrink: 0 }} />
                          <span className="flex-1 truncate" style={{ fontSize: 10, fontWeight: 600, color: '#ddd' }}>{vc.label}</span>
                          <span style={{ fontSize: 8, color: someSel ? '#999' : '#444', fontVariantNumeric: 'tabular-nums' }}>
                            {selCount}/{classModels.length}
                          </span>
                          <Checkbox checked={allSel} onChange={(v) => toggleAllInClass(classModels, v)} size={13} />
                        </div>

                        {/* Expanded models */}
                        {isExpanded && (
                          <div style={{ paddingLeft: 14, borderLeft: '1px solid rgba(255,255,255,0.04)', marginLeft: 10, marginTop: 1, marginBottom: 2 }}>
                            {classModels.map(model => (
                              <div key={model}
                                onClick={() => {
                                  toggleModel(model)
                                  onActiveChange?.({ type: 'vehicle', id: vc.label, camera: 'vehicle', firstModel: model })
                                }}
                                className="flex items-center gap-2 cursor-pointer select-none transition-all hover:opacity-100"
                                style={{ height: 22, padding: '0 6px', borderRadius: 4, opacity: selectedModels.has(model) ? 1 : 0.5 }}>
                                <Checkbox checked={selectedModels.has(model)} onChange={() => toggleModel(model)} size={12} />
                                <span className="flex-1 truncate" style={{ fontSize: 9, fontWeight: 400, color: '#ccc' }}>{model}</span>
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>
              </ScrollArea>
            </div>
          </>
        )}

        {/* ═══ OBJECTS TAB ═══ */}
        {activeTab === 'objects' && (
          <>
            {/* Search */}
            <div style={{ padding: '8px 20px 6px' }}>
              <div className="flex items-center gap-2" style={{ height: 28, borderRadius: 6, padding: '0 8px', background: bg(0.015), border: border(0.04) }}>
                <Search style={{ width: 10, height: 10, color: '#444', flexShrink: 0 }} />
                <input value={objectSearch} onChange={e => setObjectSearch(e.target.value)}
                  placeholder="Search objects..." style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 10, color: '#ccc', caretColor: '#888' }} />
                {objectSearch && (
                  <button onClick={() => setObjectSearch('')} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
                    <X style={{ width: 9, height: 9, color: '#555' }} />
                  </button>
                )}
              </div>
            </div>

            <div style={{ height: 1, background: 'rgba(255,255,255,0.04)' }} />

            <div className="flex items-center justify-between" style={{ padding: '6px 20px 4px' }}>
              <span style={{ fontSize: 10, color: '#555' }}>
                <span style={{ color: '#999', fontWeight: 600 }}>{objectSelectedCount}</span> / {objectCategories.length} objects
              </span>
              <div className="flex items-center gap-1.5">
                <div onClick={handleSaveEntityAngle} title="Save camera angle for all objects"
                  className="flex items-center justify-center cursor-pointer hover:bg-white/[0.06]"
                  style={{ width: 20, height: 20, borderRadius: 4, flexShrink: 0 }}>
                  <Camera style={{ width: 10, height: 10, color: savedCameras.has('object') ? '#22c55e' : '#666' }} />
                </div>
                <span style={{ fontSize: 10, color: '#333' }}>|</span>
                <button onClick={objectSelectAll} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>All</button>
                <span style={{ fontSize: 10, color: '#333' }}>·</span>
                <button onClick={objectSelectNone} style={{ fontSize: 10, color: '#666', background: 'none', border: 'none', cursor: 'pointer' }}>None</button>
              </div>
            </div>

            <div className={isBrowse ? 'flex-1 overflow-hidden' : ''} style={{ padding: '2px 20px 10px' }}>
              <ScrollArea style={{ height: isBrowse ? '100%' : Math.min(filteredObjects.length * 24, 240) }}>
                <div className="flex flex-col gap-0.5">
                  {filteredObjects.map(obj => (
                    <div key={obj.key || obj.id}
                      onClick={() => {
                        toggleObject(obj.id)
                        onActiveChange?.({ type: 'object', id: obj.id, camera: 'object' })
                      }}
                      className="flex items-center gap-2 cursor-pointer select-none transition-all hover:opacity-100"
                      style={{ height: 24, padding: '0 6px', borderRadius: 4, opacity: selectedObjects.has(obj.id) ? 1 : 0.5 }}>
                      <Checkbox checked={selectedObjects.has(obj.id)} onChange={() => toggleObject(obj.id)} size={12} />
                      <Box style={{ width: 9, height: 9, color: '#555', flexShrink: 0 }} />
                      <span className="flex-1 truncate" style={{ fontSize: 9, fontWeight: 500, color: '#ccc' }}>{obj.label}</span>
                      <span style={{ fontSize: 7, color: '#444' }}>{obj.id}</span>
                    </div>
                  ))}
                </div>
              </ScrollArea>
            </div>
          </>
        )}

        {/* ═══ FOOTER ═══ */}
        <div style={{ height: 1, background: 'rgba(255,255,255,0.04)' }} />
        {!isBrowse && onGenderChange && pedSelectedCount + overlaySelectedCount > 0 && (
          <div className="flex items-center justify-between" style={{ padding: '10px 20px 0' }}>
            <div>
              <div style={{ fontSize: 10, fontWeight: 600, color: '#bbb' }}>Capture both genders</div>
              <div style={{ fontSize: 8, color: '#555', marginTop: 1 }}>
                {gender === 'male' ? 'Male' : 'Female'} first, then {gender === 'male' ? 'female' : 'male'} with the same categories
              </div>
            </div>
            <Switch size="sm" checked={bothGenders} onCheckedChange={setBothGenders} />
          </div>
        )}
        {!isBrowse ? (
          <div className="flex items-center justify-between" style={{ padding: '12px 20px 14px' }}>
            <button onClick={onCancel} className="transition-colors hover:bg-white/[0.03]"
              style={{ width: 64, height: 28, fontSize: 10, fontWeight: 500, color: '#666', background: 'transparent', border: border(), borderRadius: 5, cursor: 'pointer' }}>
              Cancel
            </button>
            {totalSelected > 0 && <span style={{ fontSize: 10, color: '#555' }}>{totalSelected} item{totalSelected !== 1 ? 's' : ''}</span>}
            <button onClick={handleStart} disabled={totalSelected === 0} className="transition-all"
              style={{ width: 64, height: 28, fontSize: 10, fontWeight: 700, background: totalSelected > 0 ? '#f5f5f5' : '#1a1a1a', color: totalSelected > 0 ? '#111' : '#444', border: `1px solid ${totalSelected > 0 ? 'rgba(255,255,255,0.1)' : 'rgba(255,255,255,0.04)'}`, borderRadius: 5, cursor: totalSelected > 0 ? 'pointer' : 'not-allowed', boxShadow: totalSelected > 0 ? '0 1px 8px rgba(255,255,255,0.08)' : 'none' }}>
              Start
            </button>
          </div>
        ) : null}
      </div>
    </div>
  )
}

export default CapturePreview
