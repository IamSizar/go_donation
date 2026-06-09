// Per-skill icon + per-category accent color sidecar to skillCatalogue.ts.
// Kept separate so the catalogue stays pure data (importable from
// non-React contexts) while the SPA still gets polished chip rendering.
//
// Mirrors the Flutter side's lookup tables in
// humanitarian/lib/modules/support/widgets/skill_chip_picker.dart.

import type { SkillCategoryKey } from './skillCatalogue'

// Material-style emoji-ish glyphs — we don't pull a Material icon font
// into the SPA, so a single emoji per skill is the cheapest way to
// give each chip a visual signature.
export const SKILL_ICON: Record<string, string> = {
  // transport
  driver_car: '🚗', driver_truck: '🚚', motorcycle: '🏍',
  // trades
  electrician: '⚡', plumber: '🔧', carpenter: '🪚', mason: '🧱', mechanic: '🔩',
  // medical
  first_aid: '🩹', nurse: '💊', doctor: '🩺', mental_health: '🧠', eldercare: '👵',
  // service
  cook: '🍳', cleaner: '🧹', tailor: '🪡',
  // office / digital
  designer: '🎨', photographer: '📷', videographer: '🎥', social_media: '📱',
  it_support: '💻', data_entry: '⌨️',
  // teaching / language
  teacher: '🎓', translator_ar: '🌐', translator_en: '🌐', counselor: '💬',
  // field work
  distribution: '📦', survey: '📋', logistics: '🗺', warehouse: '🏬',
}

// Category accent color (hex). Same palette as the Flutter side, tuned
// down a touch for the admin's lighter background.
export const CATEGORY_COLOR: Record<SkillCategoryKey, string> = {
  transport: '#4F46E5',
  trades:    '#EA580C',
  medical:   '#DC2626',
  service:   '#0D9488',
  office:    '#7C3AED',
  teaching:  '#16A34A',
  field:     '#92400E',
}

// Reverse lookup: which category a skill belongs to. Used by the chip
// renderer to color a key without taking the category as a prop.
import { SKILL_CATEGORIES } from './skillCatalogue'
const _skillToCategory: Record<string, SkillCategoryKey> = {}
for (const cat of SKILL_CATEGORIES) {
  for (const s of cat.skills) _skillToCategory[s.key] = cat.key
}

/** Accent hex for any catalogue skill key. Falls back to neutral gray. */
export function colorForSkill(key: string): string {
  const cat = _skillToCategory[key]
  return cat ? CATEGORY_COLOR[cat] : '#6B7280'
}
