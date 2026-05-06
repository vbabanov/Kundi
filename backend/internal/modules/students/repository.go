package students

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Profile struct {
	StudentID  string `json:"student_id"`
	FirstName  string `json:"first_name"`
	LastName   string `json:"last_name"`
	GradeLevel int    `json:"grade_level"`
	ClassLabel string `json:"class_label"`
	SchoolName string `json:"school_name"`
	Timezone   string `json:"timezone"`
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) GetProfile(ctx context.Context, studentID uuid.UUID) (Profile, error) {
	var p Profile
	err := r.pool.QueryRow(ctx, `
		SELECT sp.student_id::text,
		       sp.first_name,
		       sp.last_name,
		       sp.grade_level,
		       sp.class_label,
		       COALESCE(s.name, ''),
		       sp.timezone
		FROM student_profiles sp
		LEFT JOIN schools s ON s.id = sp.school_id
		WHERE sp.student_id = $1
	`, studentID).Scan(
		&p.StudentID,
		&p.FirstName,
		&p.LastName,
		&p.GradeLevel,
		&p.ClassLabel,
		&p.SchoolName,
		&p.Timezone,
	)
	return p, err
}
