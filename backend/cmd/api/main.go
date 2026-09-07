package main

import (
	"context"
	"errors"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kundi/kundi/backend/internal/app"
	"github.com/kundi/kundi/backend/internal/transport/http/v1"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	deps, err := app.New(ctx, "api")
	if err != nil {
		panic(err)
	}
	defer deps.Close()

	router := v1.NewRouter(deps)
	var metricsListener net.Listener
	var metricsServer *http.Server
	if deps.Observe.MetricsHandler != nil {
		metricsListener, err = net.Listen("tcp", deps.Config.Observability.MetricsListenAddr)
		if err != nil {
			panic(err)
		}
		metricsMux := http.NewServeMux()
		metricsMux.Handle("/metrics", deps.Observe.MetricsHandler)
		metricsMux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("ok\n"))
		})
		metricsServer = &http.Server{
			Handler:      metricsMux,
			ReadTimeout:  5 * time.Second,
			WriteTimeout: 10 * time.Second,
			IdleTimeout:  30 * time.Second,
		}
		go func() {
			deps.Logger.Info("metrics server listening", "addr", deps.Config.Observability.MetricsListenAddr)
			if serveErr := metricsServer.Serve(metricsListener); serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
				deps.Logger.Error("metrics server stopped with error", "err", serveErr)
				stop()
			}
		}()
	}
	srv := &http.Server{
		Addr:         ":" + deps.Config.App.Port,
		Handler:      router,
		ReadTimeout:  deps.Config.App.ReadTimeout,
		WriteTimeout: deps.Config.App.WriteTimeout,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		deps.Logger.Info("api server listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			deps.Logger.Error("api server stopped with error", "err", err)
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
	if metricsServer != nil {
		_ = metricsServer.Shutdown(shutdownCtx)
	}
}
