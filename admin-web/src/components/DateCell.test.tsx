/**
 * DateCell.test.tsx — the one way a dashboard table prints a timestamp.
 *
 * Client item C3 asks for every table timestamp to read as DATE ON TOP, TIME
 * UNDERNEATH. The markup that does that used to be copy-pasted into nine
 * pages, so these tests pin the shared component's contract instead:
 *   - a timestamp is two stacked lines inside one <time> element, so the
 *     machine-readable value travels with the human-readable one;
 *   - a missing timestamp is the dashboard's em dash, not an empty cell;
 *   - a value the browser cannot parse is shown verbatim rather than as
 *     "Invalid Date", and carries no datetime attribute (an unparseable
 *     string is not a valid HTML datetime).
 */
import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import DateCell from './DateCell'
import { formatDateParts } from '../lib/dates'

const ISO = '2026-09-14T09:00:00Z'

describe('DateCell', () => {
  it('stacks the date over the time inside one <time> element', () => {
    // Arrange
    const { date, time } = formatDateParts(ISO)

    // Act
    const { container } = render(<DateCell value={ISO} />)

    // Assert
    const el = container.querySelector('time')
    expect(el).not.toBeNull()
    expect(el).toHaveAttribute('datetime', ISO)
    expect(el).toHaveClass('cell-stack')
    expect(screen.getByText(date)).toBeInTheDocument()
    expect(screen.getByText(time)).toBeInTheDocument()
    // Date first, time second — the whole point of the column.
    const lines = Array.from(el!.querySelectorAll('span')).map((s) => s.textContent)
    expect(lines).toEqual([date, time])
  })

  it('shows the em dash for a missing timestamp, with no <time> element', () => {
    // Act
    const { container } = render(<DateCell value={null} />)

    // Assert
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(container.querySelector('time')).toBeNull()
  })

  it('shows an unparseable value verbatim and claims no datetime attribute', () => {
    // Act
    const { container } = render(<DateCell value="not a date" />)

    // Assert
    expect(screen.getByText('not a date')).toBeInTheDocument()
    expect(container.querySelector('time')).toBeNull()
  })
})
