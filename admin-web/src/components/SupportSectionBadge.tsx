import { useSupportSectionLabel } from '../lib/supportSections'

/** Small tinted badge. Events and volunteers get distinct tones so a mixed
 * list can be scanned at a glance; unsectioned stays neutral. */
export default function SupportSectionBadge({ section }: { section: string | null | undefined }) {
  const label = useSupportSectionLabel()
  const tone = section === 'events' ? 'tone-primary' : section === 'volunteers' ? 'tone-info' : ''
  return <span className={`badge ${tone}`.trim()} style={{ whiteSpace: 'nowrap' }}>{label(section)}</span>
}
