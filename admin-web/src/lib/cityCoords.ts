// A City Guide place only shows on the app map when it has real coordinates:
// both present, numeric and on Earth. The missing-coordinates banner counts
// the rest, the "no coords" cell flags them and the banner's filter keeps them.
type Coords = { latitude?: string | number | null; longitude?: string | number | null }

function num(v: string | number | null | undefined): number {
  if (v === null || v === undefined || String(v).trim() === '') return NaN
  return Number(v)
}

export function hasValidCoords(e: Coords): boolean {
  const lat = num(e.latitude)
  const lng = num(e.longitude)
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
}
