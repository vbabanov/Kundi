package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/kundi/kundi/backend/internal/app"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	deps, err := app.New(ctx, "worker-whatsapp")
	if err != nil {
		panic(err)
	}
	defer deps.Close()

	handlers := map[jobs.JobType]jobs.Handler{
		jobs.JobDispatchWhatsApp: func(ctx context.Context, job jobs.Job) error {
			return deps.WhatsAppDispatch.HandleJob(ctx, job)
		},
	}

	deps.Logger.Info("worker-whatsapp started")
	_ = deps.JobsService.RunLoop(ctx, "worker-whatsapp", deps.Config.Jobs.LeaseDuration, deps.Config.Jobs.PollInterval, handlers)
}
