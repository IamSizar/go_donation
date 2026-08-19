// Coordinate validation for anything that gets pinned on a map.
//
// WHY THIS EXISTS
// The City Guide map rendered as an empty grey rectangle for every user. The
// cause was one directory row carrying latitude 500, longitude 700. The app
// centred its map on the average of its pins, so that single row dragged the
// centre past the North Pole, where no map tiles exist.
//
// The app now refuses to plot impossible coordinates, which fixes what users
// see. This is the other half: the value should never have been stored. A
// latitude of 500 is not a place, and accepting it means every consumer of
// this data — the app, the dashboard, any export — has to defend itself
// separately against the same typo.
package handlers

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

// validateCoordinate checks one optional latitude/longitude pair.
//
// Coordinates travel as STRINGS through these handlers (the columns are text
// and the clients send text), so this parses before it checks. An empty pair
// is valid and means "no location" — most directory entries have none, and
// requiring one would reject them.
//
// Returns a user-facing message naming the offending field, or "" when fine.
func validateCoordinate(latRaw, lngRaw string) string {
	lat := strings.TrimSpace(latRaw)
	lng := strings.TrimSpace(lngRaw)

	// Neither given: no location, which is normal.
	if lat == "" && lng == "" {
		return ""
	}
	// One without the other cannot be plotted, and storing half a coordinate
	// hides the mistake until someone opens the map.
	if lat == "" || lng == "" {
		return "latitude and longitude must be provided together."
	}

	latVal, err := strconv.ParseFloat(lat, 64)
	if err != nil {
		return "latitude must be a number."
	}
	lngVal, err := strconv.ParseFloat(lng, 64)
	if err != nil {
		return "longitude must be a number."
	}
	if math.IsNaN(latVal) || math.IsInf(latVal, 0) ||
		math.IsNaN(lngVal) || math.IsInf(lngVal, 0) {
		return "latitude and longitude must be real numbers."
	}
	if latVal < -90 || latVal > 90 {
		return fmt.Sprintf("latitude must be between -90 and 90 (got %s).", lat)
	}
	if lngVal < -180 || lngVal > 180 {
		return fmt.Sprintf("longitude must be between -180 and 180 (got %s).", lng)
	}
	return ""
}
