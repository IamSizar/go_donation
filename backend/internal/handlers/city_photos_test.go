package handlers

import (
	"reflect"
	"testing"
)

func TestCleanCityPhotosKeepsOnlyUploadedPaths(t *testing.T) {
	in := []string{
		"images/uploads/a1.jpg",
		"https://pub-x.r2.dev/uploads/b2.png",
		"data:image/png;base64,AAAA",
		"file:///etc/passwd",
		"http://evil.example/uploads/c.jpg", // not https
		"https://evil.example/photos/c.jpg", // not an uploads path
		"images/uploads/../../secret",       // traversal
		"images/uploads/x.jpg\"><script>",   // markup
		"/images/uploads/abs.jpg",           // absolute local path
		"",
		"  ",
		"images/uploads/a1.jpg", // duplicate
	}
	want := []string{"images/uploads/a1.jpg", "https://pub-x.r2.dev/uploads/b2.png"}
	if got := cleanCityPhotos(in); !reflect.DeepEqual(got, want) {
		t.Fatalf("cleanCityPhotos = %v, want %v", got, want)
	}
}

func TestCleanCityPhotosCapsTheCount(t *testing.T) {
	var in []string
	for i := 0; i < 20; i++ {
		in = append(in, "images/uploads/p"+string(rune('a'+i))+".jpg")
	}
	if got := cleanCityPhotos(in); len(got) != maxCityPhotos {
		t.Fatalf("kept %d photos, want %d", len(got), maxCityPhotos)
	}
}

func TestCleanCityPhotosNilIsEmptyNotNil(t *testing.T) {
	// The column is NOT NULL: a nil slice must still become '{}'.
	if got := cleanCityPhotos(nil); got == nil || len(got) != 0 {
		t.Fatalf("cleanCityPhotos(nil) = %#v, want empty non-nil slice", got)
	}
}
