// Pins every data table's header row to the top of whatever scrolls the page,
// so the operator always knows which column they are looking at.
//
// WHY JS AND NOT `position: sticky`
// index.css (see the long note on .table-wrap) records why CSS alone cannot do
// it here: a table that scrolls sideways inside its card needs
// `overflow-x: auto`, which forces the block axis to a scroll container too,
// and a sticky header sticks to THAT box, not to the page. Page-level vertical
// scroll, a contained horizontal scroll and a CSS sticky header cannot all hold
// on one subtree.
//
// So the header follows the scroll by a transform instead. The real <th>
// cells are moved down by however far the table's top edge has scrolled above
// the scroller's top edge (clamped so the header never leaves its own table).
// They stay in the table, so column widths, the select-all checkbox, sideways
// scroll and RTL keep working with no duplicate header to keep in sync.
//
// One capture-phase scroll listener covers every scroller — the page, a
// modal body — and every table, including ones that mount later.

const SCROLLABLE = /(auto|scroll|overlay)/

/** The nearest ancestor that scrolls vertically, or null for the document. */
function scrollerOf(el: HTMLElement): HTMLElement | null {
  for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
    if (SCROLLABLE.test(getComputedStyle(p).overflowY) && p.scrollHeight > p.clientHeight) return p
  }
  return null
}

/** Moves (or resets) the header of one table. Returns nothing; reads first, writes last. */
function place(table: HTMLTableElement, scrollTop: number) {
  const head = table.tHead
  if (!head) return
  const rect = table.getBoundingClientRect()
  const headHeight = head.getBoundingClientRect().height
  // How far the table's top has scrolled past the scroller's top edge.
  const past = scrollTop - rect.top
  const max = Math.max(0, rect.height - headHeight - 1)
  const dy = past > 0 ? Math.min(past, max) : 0
  const cells = head.querySelectorAll<HTMLElement>('th')
  const value = dy > 0 ? `translateY(${Math.round(dy)}px)` : ''
  cells.forEach((th) => {
    if (th.style.transform !== value) th.style.transform = value
    th.classList.toggle('is-stuck', dy > 0)
  })
}

function update(target: EventTarget | null) {
  const root = target instanceof HTMLElement ? target : null
  const tables = Array.from(document.querySelectorAll<HTMLTableElement>('table.data-table'))
  const work = tables
    .filter((t) => !root || root.contains(t))
    .map((t) => {
      const scroller = scrollerOf(t)
      return { t, top: scroller ? scroller.getBoundingClientRect().top : 0 }
    })
  for (const { t, top } of work) place(t, top)
}

/** Installs the behaviour once for the whole app. Returns the cleanup. */
export function installStickyTableHeaders(): () => void {
  let frame = 0
  let pending: EventTarget | null = null
  const schedule = (target: EventTarget | null) => {
    // Several scrollers firing in one frame collapse into one full pass.
    pending = pending && pending !== target ? null : target
    if (frame) return
    frame = requestAnimationFrame(() => {
      frame = 0
      update(pending instanceof HTMLElement ? pending : null)
      pending = null
    })
  }
  const onScroll = (e: Event) => schedule(e.target === document ? null : e.target)
  const onChange = () => schedule(null)
  document.addEventListener('scroll', onScroll, true)
  window.addEventListener('resize', onChange)
  // Tables mount, re-render and unmount as pages change or refresh; a header
  // must not stay displaced after its rows are swapped out.
  const mo = new MutationObserver(onChange)
  mo.observe(document.body, { childList: true, subtree: true })
  return () => {
    document.removeEventListener('scroll', onScroll, true)
    window.removeEventListener('resize', onChange)
    mo.disconnect()
    if (frame) cancelAnimationFrame(frame)
  }
}
