import { describe, expect, it } from 'vitest'
import { hasValidCoords } from './cityCoords'

describe('hasValidCoords', () => {
  it('accepts real coordinates, as strings or numbers', () => {
    expect(hasValidCoords({ latitude: '36.3350000', longitude: '43.1190000' })).toBe(true)
    expect(hasValidCoords({ latitude: 36.3, longitude: 43.1 })).toBe(true)
  })
  it('rejects missing or blank coordinates', () => {
    expect(hasValidCoords({ latitude: null, longitude: '43.1' })).toBe(false)
    expect(hasValidCoords({ latitude: '36.3', longitude: undefined })).toBe(false)
    expect(hasValidCoords({ latitude: '', longitude: '  ' })).toBe(false)
  })
  it('rejects non-numeric and off-Earth values', () => {
    expect(hasValidCoords({ latitude: 'abc', longitude: '43.1' })).toBe(false)
    expect(hasValidCoords({ latitude: '500', longitude: '700' })).toBe(false)
  })
})
