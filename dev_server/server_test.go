package main

import "testing"

func TestPagePath(t *testing.T) {
	templateDir = "../pages"

	cases := map[string]string{
		"../pages/index.jinja2":               "/",
		"../pages/concerts/index.jinja2":      "/concerts",
		"../pages/releases/word/index.jinja2": "/releases/word",
		"../pages/404.jinja2":                 "/404.html",
	}

	for path, want := range cases {
		if got := pagePath(path); got != want {
			t.Errorf("pagePath(%q) = %q, expected %q", path, got, want)
		}
	}
}
