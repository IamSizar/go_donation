// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { installStickyTableHeaders } from './stickyTableHeaders'

// jsdom has no layout, so the geometry is supplied by hand: a page scroller
// whose top edge is at y=57, holding a table whose top has scrolled to y=-150
// (so its header is 207px above where it should be pinned).
function mount(tableTop: number, tableHeight = 800, headHeight = 40) {
  const scroller = document.createElement('div')
  scroller.style.overflowY = 'auto'
  Object.defineProperty(scroller, 'scrollHeight', { value: 2000 })
  Object.defineProperty(scroller, 'clientHeight', { value: 600 })
  scroller.getBoundingClientRect = () => ({ top: 57 }) as DOMRect
  const table = document.createElement('table')
  table.className = 'data-table'
  table.innerHTML = '<thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody>'
  table.getBoundingClientRect = () => ({ top: tableTop, height: tableHeight }) as DOMRect
  table.tHead!.getBoundingClientRect = () => ({ height: headHeight }) as DOMRect
  scroller.appendChild(table)
  document.body.appendChild(scroller)
  return { scroller, th: table.tHead!.querySelectorAll('th') }
}

const frame = () => new Promise((r) => requestAnimationFrame(() => r(null)))

describe('installStickyTableHeaders', () => {
  afterEach(() => {
    document.body.innerHTML = ''
  })

  it('moves the header down by how far the table has scrolled past the top edge', async () => {
    const off = installStickyTableHeaders()
    const { scroller, th } = mount(-150)
    scroller.dispatchEvent(new Event('scroll'))
    await frame()
    // 57 - (-150) = 207
    expect(th[0].style.transform).toBe('translateY(207px)')
    expect(th[1].style.transform).toBe('translateY(207px)')
    expect(th[0].classList.contains('is-stuck')).toBe(true)
    off()
  })

  it('leaves the header alone while the table top is still on screen', async () => {
    const off = installStickyTableHeaders()
    const { scroller, th } = mount(120)
    scroller.dispatchEvent(new Event('scroll'))
    await frame()
    expect(th[0].style.transform).toBe('')
    expect(th[0].classList.contains('is-stuck')).toBe(false)
    off()
  })

  it('never lets the header leave the bottom of its own table', async () => {
    const off = installStickyTableHeaders()
    const { scroller, th } = mount(-5000, 800, 40)
    scroller.dispatchEvent(new Event('scroll'))
    await frame()
    // 800 - 40 - 1
    expect(th[0].style.transform).toBe('translateY(759px)')
    off()
  })

  it('stops reacting after cleanup', async () => {
    const off = installStickyTableHeaders()
    off()
    const { scroller, th } = mount(-150)
    scroller.dispatchEvent(new Event('scroll'))
    await frame()
    expect(th[0].style.transform).toBe('')
    vi.restoreAllMocks()
  })
})
