package main

import (
	"context"
	"errors"
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
}
