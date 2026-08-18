package handlers

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/color"
	"testing"
)

// jpegWithOrientation builds the smallest JPEG-shaped byte string that carries
// an EXIF APP1 segment declaring the given orientation. It is not a decodable
// image — readEXIFOrientation only walks the segment headers, never the scan
// data — which keeps the fixture readable and the test's intent obvious.
func jpegWithOrientation(t *testing.T, orientation uint16, bigEndian bool) []byte {
	t.Helper()
	var order binary.ByteOrder = binary.LittleEndian
	tag := []byte{'I', 'I'}
	if bigEndian {
		order = binary.BigEndian
		tag = []byte{'M', 'M'}
	}
	tiff := new(bytes.Buffer)
	tiff.Write(tag)
	binary.Write(tiff, order, uint16(42))     // TIFF magic
	binary.Write(tiff, order, uint32(8))      // IFD0 begins immediately after
	binary.Write(tiff, order, uint16(1))      // one entry
	binary.Write(tiff, order, uint16(0x0112)) // Orientation tag
	binary.Write(tiff, order, uint16(3))      // type SHORT
	binary.Write(tiff, order, uint32(1))      // one value
	binary.Write(tiff, order, orientation)    // the value, inline
	binary.Write(tiff, order, uint16(0))      // padding of the 4-byte value field
	binary.Write(tiff, order, uint32(0))      // no next IFD

	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)
	out := new(bytes.Buffer)
	out.Write([]byte{0xFF, 0xD8})                               // SOI
	out.Write([]byte{0xFF, 0xE1})                               // APP1
	binary.Write(out, binary.BigEndian, uint16(len(payload)+2)) // segment length
	out.Write(payload)
	out.Write([]byte{0xFF, 0xD9}) // EOI
	return out.Bytes()
}

func TestReadEXIFOrientationReadsTheTag(t *testing.T) {
	for _, bigEndian := range []bool{false, true} {
		for _, want := range []int{1, 3, 6, 8} {
			got := readEXIFOrientation(bytes.NewReader(
				jpegWithOrientation(t, uint16(want), bigEndian)))
			if got != want {
				t.Errorf("bigEndian=%v orientation=%d: got %d", bigEndian, want, got)
			}
		}
	}
}

// Every malformed input must yield orientationNormal — "change nothing" — so
// that a corrupt or hostile upload can never cause a wrong rotation or a panic.
func TestReadEXIFOrientationFailsClosed(t *testing.T) {
	valid := jpegWithOrientation(t, 6, false)
	cases := map[string][]byte{
		"empty":            {},
		"not a jpeg":       []byte("GIF89a and then some"),
		"soi only":         {0xFF, 0xD8},
		"truncated APP1":   valid[:8],
		"truncated TIFF":   valid[:14],
		"desynchronised":   {0xFF, 0xD8, 0x00, 0x00, 0x00, 0x00},
		"bad byte order":   bytes.Replace(valid, []byte("Exif\x00\x00II"), []byte("Exif\x00\x00XX"), 1),
		"xmp not exif":     bytes.Replace(valid, []byte("Exif"), []byte("http"), 1),
		"out of range val": jpegWithOrientation(t, 99, false),
		"zero value":       jpegWithOrientation(t, 0, false),
	}
	for name, in := range cases {
		t.Run(name, func(t *testing.T) {
			if got := readEXIFOrientation(bytes.NewReader(in)); got != orientationNormal {
				t.Errorf("got %d, want %d (must fail closed)", got, orientationNormal)
			}
		})
	}
}

// The portrait-phone case this whole file exists for: landscape pixels plus a
// rotate-90 tag must come out as a portrait image.
func TestApplyEXIFOrientationSwapsAxesForRotations(t *testing.T) {
	src := image.NewNRGBA(image.Rect(0, 0, 1600, 1200)) // landscape, as stored
	for _, orientation := range []int{orientationRotate90, orientationRotate270,
		orientationTranspose, orientationTransverse} {
		out := applyEXIFOrientation(src, orientation).Bounds()
		if out.Dx() != 1200 || out.Dy() != 1600 {
			t.Errorf("orientation %d: got %dx%d, want 1200x1600",
				orientation, out.Dx(), out.Dy())
		}
	}
}

func TestApplyEXIFOrientationLeavesUprightImagesAlone(t *testing.T) {
	src := image.NewNRGBA(image.Rect(0, 0, 4, 2))
	for _, orientation := range []int{orientationNormal, 0, -1, 9, 999} {
		if got := applyEXIFOrientation(src, orientation); got != image.Image(src) {
			t.Errorf("orientation %d: image was modified; want the original untouched",
				orientation)
		}
	}
}

// Rotation must move pixels to the right place, not merely resize the canvas —
// a transform that only swapped the bounds would pass the dimension test above.
func TestApplyEXIFOrientationMovesPixelsCorrectly(t *testing.T) {
	// A 2x1 image: red at the left, blue at the right.
	src := image.NewNRGBA(image.Rect(0, 0, 2, 1))
	red := color.NRGBA{R: 255, A: 255}
	blue := color.NRGBA{B: 255, A: 255}
	src.Set(0, 0, red)
	src.Set(1, 0, blue)

	// Rotating 90° clockwise puts the left-hand pixel at the top.
	got := applyEXIFOrientation(src, orientationRotate90)
	if r, _, _, _ := got.At(0, 0).RGBA(); r == 0 {
		t.Error("rotate90: expected the red pixel at the top")
	}
	if _, _, b, _ := got.At(0, 1).RGBA(); b == 0 {
		t.Error("rotate90: expected the blue pixel at the bottom")
	}

	// A horizontal flip swaps them in place, without changing the shape.
	flipped := applyEXIFOrientation(src, orientationFlipH)
	if flipped.Bounds().Dx() != 2 || flipped.Bounds().Dy() != 1 {
		t.Fatalf("flipH changed the shape: %v", flipped.Bounds())
	}
	if _, _, b, _ := flipped.At(0, 0).RGBA(); b == 0 {
		t.Error("flipH: expected the blue pixel to move to the left")
	}
}
