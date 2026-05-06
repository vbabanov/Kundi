package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/kundi/kundi/backend/internal/app"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
	"github.com/kundi/kundi/backend/internal/workers/jobhandlers"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	deps, err := app.New(ctx, "worker-jobs")
	if err != nil {
		panic(err)
	}
	defer deps.Close()

	handlers := jobhandlers.NewJobsWorker(
		deps.JobsService,
		deps.AnalyticsService,
		deps.AcademicService,
	).Handlers()
	handlers[jobs.JobDispatchWhatsApp] = func(ctx context.Context, job jobs.Job) error {
		return deps.WhatsAppDispatch.HandleJob(ctx, job)
	}

	deps.Logger.Info("worker-jobs started")
	_ = deps.JobsService.RunLoop(ctx, "worker-jobs", deps.Config.Jobs.LeaseDuration, deps.Config.Jobs.PollInterval, handlers)
}
