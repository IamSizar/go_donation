/**
 * Client meeting — support is split into two departments: events
 * (الفعاليات) and volunteers (المتطوعين). A ticket / support chat carries one of
 * these, or null when it was opened before the split (or by an older app
 * build) — those stay visible to every support staff member.
 *
 * Shared by the tickets page, the support chats page and the Staff page so the
 * three always name the sections the same way.
 */
import { useI18n } from './i18n'

export const SUPPORT_SECTIONS = ['events', 'volunteers'] as const
export type SupportSection = (typeof SUPPORT_SECTIONS)[number]

/** Values of the list filter: everything, one section, or the unsectioned. */
export const SUPPORT_SECTION_FILTERS = ['all', ...SUPPORT_SECTIONS, 'none'] as const

export function useSupportSectionLabel() {
  const { t } = useI18n()
  return (s: string | null | undefined) =>
    s ? t(`support_section.${s}`) : t('support_section.none')
}
