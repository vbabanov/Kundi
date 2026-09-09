package homeinsight

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresGradeSource struct {
	pool *pgxpool.Pool
}

func NewPostgresGradeSource(pool *pgxpool.Pool) *PostgresGradeSource {
	return &PostgresGradeSource{pool: pool}
}

func (source *PostgresGradeSource) GradeLevel(ctx context.Context, studentID uuid.UUID) (int, error) {
	var gradeLevel int
	err := source.pool.QueryRow(ctx, `SELECT grade_level FROM student_profiles WHERE student_id=$1`, studentID).Scan(&gradeLevel)
	return gradeLevel, err
}
