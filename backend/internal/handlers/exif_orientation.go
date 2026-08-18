// Package handlers — EXIF orientation recovery for uploaded photos.
//
// Why this file exists: Go's standard image/jpeg decodes pixels and nothing
// else. It ignores EXIF on the way in and writes none on the way out. That is
// fine for an image whose pixels are already the right way up, and silently
// destructive for one that is not.
//
// Phone cameras are the "not" case. An iPhone sensor is landscape-native, so a
// photo taken holding the phone upright is stored as landscape pixels plus an
// EXIF Orientation tag saying "rotate this 90° before showing it". Re-encoding
// with image/jpeg keeps the sideways pixels and drops the tag, which turns a
// recoverable rotation into a permanent one — every viewer downstream now
// agrees the photo really is sideways, because the only evidence to the
// contrary is gone.
//
// So we read the tag ourselves before decoding and bake the rotation into the
// pixels, which is the one representation no downstream viewer can misread.
//
// This is a deliberately small hand-rolled parser rather than a dependency: it
// reads exactly one tag from a length-prefixed structure, and every offset is
// bounds-checked against the buffer because the input is attacker-controlled.
// It is written to fail closed — any malformed, truncated, or surprising input
// yields orientationNormal, which means "change nothing".
package handlers

import (
	"encoding/binary"
	"image"
	"io"
)

// EXIF orientation values, per the TIFF/EXIF specification. Values describe
// the transform needed to display the stored pixels correctly.
const (
	orientationNormal     = 1 // no transform
	orientationFlipH      = 2 // mirrored left-to-right
	orientationRotate180  = 3 // upside down
	orientationFlipV      = 4 // mirrored top-to-bottom
	orientationTranspose  = 5 // mirrored, then rotated 90° clockwise
	orientationRotate90   = 6 // rotated 90° clockwise (the common portrait case)
	orientationTransverse = 7 // mirrored, then rotated 270° clockwise
	orientationRotate270  = 8 // rotated 270° clockwise
	exifOrientationTag    = 0x0112
	maxEXIFScanBytes      = 128 << 10 // EXIF lives near the file start; 128KB is generous
	maxIFDEntries         = 512       // sanity cap so a corrupt count can't spin us
	ifdEntrySize          = 12
)

// readEXIFOrientation returns the EXIF Orientation value (1–8) for a JPEG read
// from r, or orientationNormal when there is no EXIF, the EXIF is unreadable,
// or the value is out of range.
//
// It never returns an error: a photo whose orientation we cannot determine is
// treated exactly like a photo that needs no rotation, which is the safe
// default — we would rather leave an image untouched than rotate it wrongly.
func readEXIFOrientation(r io.Reader) int {
	buf, err := io.ReadAll(io.LimitReader(r, maxEXIFScanBytes))
	if err != nil || len(buf) < 4 {
		return orientationNormal
	}
	// A JPEG starts with SOI (0xFFD8). Anything else is not our business.
	if buf[0] != 0xFF || buf[1] != 0xD8 {
		return orientationNormal
	}
	// Walk the segment chain looking for APP1, which is where EXIF lives.
	for pos := 2; pos+4 <= len(buf); {
		if buf[pos] != 0xFF {
			return orientationNormal // desynchronised — stop rather than guess
		}
		marker := buf[pos+1]
		// SOS (0xDA) begins compressed scan data; EXIF cannot appear after it.
		if marker == 0xDA || marker == 0xD9 {
			return orientationNormal
		}
		segLen := int(binary.BigEndian.Uint16(buf[pos+2 : pos+4]))
		if segLen < 2 || pos+2+segLen > len(buf) {
			return orientationNormal // truncated segment
		}
		if marker == 0xE1 {
			payload := buf[pos+4 : pos+2+segLen]
			// APP1 is only EXIF when it carries the "Exif\0\0" signature;
			// XMP also uses APP1 and must not be parsed as TIFF.
			if len(payload) > 6 && string(payload[:4]) == "Exif" &&
				payload[4] == 0x00 && payload[5] == 0x00 {
				return orientationFromTIFF(payload[6:])
			}
		}
		pos += 2 + segLen
	}
	return orientationNormal
}

// orientationFromTIFF parses the TIFF header and IFD0 of an EXIF payload and
// returns the Orientation tag's value, or orientationNormal if absent/invalid.
//
// All offsets in TIFF are relative to the start of the TIFF header, which is
// why tiff is passed as its own slice — it makes every bounds check a simple
// comparison against len(tiff) rather than arithmetic against the outer file.
func orientationFromTIFF(tiff []byte) int {
	if len(tiff) < 8 {
		return orientationNormal
	}
	// Byte order is self-describing: "II" little-endian, "MM" big-endian.
	var order binary.ByteOrder
	switch {
	case tiff[0] == 'I' && tiff[1] == 'I':
		order = binary.LittleEndian
	case tiff[0] == 'M' && tiff[1] == 'M':
		order = binary.BigEndian
	default:
		return orientationNormal
	}
	if order.Uint16(tiff[2:4]) != 42 { // TIFF magic
		return orientationNormal
	}
	ifdOffset := int(order.Uint32(tiff[4:8]))
	if ifdOffset < 8 || ifdOffset+2 > len(tiff) {
		return orientationNormal
	}
	count := int(order.Uint16(tiff[ifdOffset : ifdOffset+2]))
	if count > maxIFDEntries {
		return orientationNormal
	}
	for i := 0; i < count; i++ {
		entry := ifdOffset + 2 + i*ifdEntrySize
		if entry+ifdEntrySize > len(tiff) {
			return orientationNormal
		}
		if order.Uint16(tiff[entry:entry+2]) != exifOrientationTag {
			continue
		}
		// Orientation is a SHORT (type 3). The value is small enough to sit
		// inline in the entry's value field rather than at an offset.
		if order.Uint16(tiff[entry+2:entry+4]) != 3 {
			return orientationNormal
		}
		value := int(order.Uint16(tiff[entry+8 : entry+10]))
		if value < orientationNormal || value > orientationRotate270 {
			return orientationNormal // out of spec — ignore
		}
		return value
	}
	return orientationNormal
}

// applyEXIFOrientation returns img transformed so its pixels are upright,
// according to an EXIF orientation value. orientationNormal (and any value we
// do not recognise) returns img unchanged and allocates nothing.
func applyEXIFOrientation(img image.Image, orientation int) image.Image {
	if orientation <= orientationNormal || orientation > orientationRotate270 {
		return img
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()

	// Orientations 5–8 exchange the axes, so the output is transposed.
	swapsAxes := orientation >= orientationTranspose
	outW, outH := w, h
	if swapsAxes {
		outW, outH = h, w
	}
	dst := image.NewNRGBA(image.Rect(0, 0, outW, outH))

	// For each destination pixel, map back to the source pixel it came from.
	// Mapping backwards (rather than forwards) guarantees every destination
	// pixel is written exactly once, with no gaps from rounding.
	for y := 0; y < outH; y++ {
		for x := 0; x < outW; x++ {
			var sx, sy int
			switch orientation {
			case orientationFlipH:
				sx, sy = w-1-x, y
			case orientationRotate180:
				sx, sy = w-1-x, h-1-y
			case orientationFlipV:
				sx, sy = x, h-1-y
			case orientationTranspose:
				sx, sy = y, x
			case orientationRotate90:
				sx, sy = y, h-1-x
			case orientationTransverse:
				sx, sy = w-1-y, h-1-x
			case orientationRotate270:
				sx, sy = w-1-y, x
			}
			dst.Set(x, y, img.At(b.Min.X+sx, b.Min.Y+sy))
		}
	}
	return dst
}
