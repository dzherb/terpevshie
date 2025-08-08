package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/fsnotify/fsnotify"
)

const (
	renderCmd            = "minijinja-cli"
	notFoundTemplatePath = "404.jinja2"
)

var (
	templateDir string
	clients     = make(map[*sseClient]struct{})
	clientsMu   sync.Mutex
)

type sseClient struct {
	ch     chan string
	cancel context.CancelFunc
}

type Server struct {
	srv *http.Server
}

func NewServer(port int) *Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/__livereload", sseHandler)
	mux.HandleFunc("/", pagesHandler)

	return &Server{
		srv: &http.Server{
			Addr:    fmt.Sprintf(":%d", port),
			Handler: mux,
		},
	}
}

func (s *Server) ListenAndServe(ctx context.Context) {
	go func() {
		log.Printf("🌐 Server running at http://localhost%s/", s.srv.Addr)
		if err := s.srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP error: %v", err)
		}
	}()

	<-ctx.Done()
	s.shutdown()
}

func (s *Server) shutdown() {
	// Force-close all SSE clients
	clientsMu.Lock()
	for client := range clients {
		client.cancel()
	}

	clientsMu.Unlock()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := s.srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Shutdown error: %v", err)
	}

	log.Println("✅ Server stopped")
}

const liveReloadJS = `
const es = new EventSource("/__livereload");
es.onmessage = () => location.reload();
console.log("[LiveReload] connected...");`

func pagesHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/__livereload.js" {
		w.Header().Set("Content-Type", "application/javascript")
		w.Write([]byte(liveReloadJS))
		return
	}

	path := filepath.Join(
		templateDir,
		strings.TrimPrefix(r.URL.Path, "/"),
	)

	render := true

	if strings.HasSuffix(r.URL.Path, "/") {
		path = filepath.Join(path, "index.jinja2")
	} else if strings.HasSuffix(path, ".html") {
		path = strings.TrimSuffix(path, ".html") + ".jinja2"
	} else {
		render = false
	}

	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		path = filepath.Join(templateDir, notFoundTemplatePath)
		render = true
	}

	if render == false {
		http.FileServer(http.Dir(templateDir)).ServeHTTP(w, r)
		return
	}

	html, err := renderTemplate(path)
	if err != nil {
		http.Error(w, "Render error", http.StatusInternalServerError)
		log.Println("Render error:", err)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	_, err = w.Write(html)
	if err != nil {
		log.Println("Write error:", err)
	}
}

func renderTemplate(path string) ([]byte, error) {
	cmd := exec.Command(renderCmd, path)

	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	html := string(out)
	if strings.Contains(html, "</body>") {
		html = strings.Replace(html, "</body>",
			`<script src="/__livereload.js"></script></body>`, 1)
	}

	log.Println("Rendered", path)

	return []byte(html), nil
}

func sseHandler(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	ctx, cancel := context.WithCancel(r.Context())
	client := &sseClient{ch: make(chan string, 1), cancel: cancel}

	clientsMu.Lock()
	clients[client] = struct{}{}
	clientsMu.Unlock()

	defer func() {
		clientsMu.Lock()
		delete(clients, client)
		clientsMu.Unlock()
		cancel()
		close(client.ch)
	}()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	for {
		select {
		case <-ctx.Done():
			return
		case msg := <-client.ch:
			fmt.Fprintf(w, "data: %s\n\n", msg)
			flusher.Flush()
		}
	}
}

func watchFiles(ctx context.Context) {
	log.Printf("Watching %v directory", templateDir)

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Fatal("Watcher init error:", err)
	}
	defer func() {
		watcher.Close()
		log.Println("✅ Watcher stopped")
	}()

	err = watcher.Add(templateDir)
	if err != nil {
		log.Fatal("Watcher add error:", err)
	}

	for {
		select {
		case <-ctx.Done():
			return
		case ev := <-watcher.Events:
			if ev.Op&fsnotify.Write == fsnotify.Write {
				log.Println("🔄 Modified:", ev.Name)
				broadcast("reload")
			}
		case err := <-watcher.Errors:
			log.Println("Watcher error:", err)
		}
	}
}

func broadcast(msg string) {
	clientsMu.Lock()
	defer clientsMu.Unlock()
	for client := range clients {
		select {
		case client.ch <- msg:
		default:
		}
	}
}

func main() {
	flag.StringVar(&templateDir, "templateDir", ".", "Directory with Jinja2 templates")
	var port int
	flag.IntVar(&port, "port", 8000, "Port to run the dev server on")
	flag.Parse()

	srv := NewServer(port)

	// Signal handling
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	wg := &sync.WaitGroup{}
	wg.Add(2)

	// Start HTTP server
	go func() {
		defer wg.Done()
		srv.ListenAndServe(ctx)
	}()

	// Start watcher
	go func() {
		defer wg.Done()
		watchFiles(ctx)
	}()

	// Wait for interrupt
	<-ctx.Done()
	log.Println("🛑 Shutting down...")

	wg.Wait()
}
