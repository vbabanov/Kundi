package auth

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type AccountRepository interface {
	UpsertDiaryAccount(
		ctx context.Context,
		source string,
		loginFingerprint string,
		loginCipher []byte,
		passwordCipher []byte,
	) (studentID uuid.UUID, diaryAccountID uuid.UUID, err error)
}

type PostgresAccountRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresAccountRepository(pool *pgxpool.Pool) *PostgresAccountRepository {
	return &PostgresAccountRepository{pool: pool}
}

func (r *PostgresAccountRepository) UpsertDiaryAccount(
	ctx context.Context,
	source string,
	loginFingerprint string,
	loginCipher []byte,
	passwordCipher []byte,
) (uuid.UUID, uuid.UUID, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return uuid.Nil, uuid.Nil, err
	}
	defer tx.Rollback(ctx)

	var studentID uuid.UUID
	var diaryAccountID uuid.UUID
	err = tx.QueryRow(ctx, `
		SELECT id, student_id
		FROM diary_accounts
		WHERE source = $1 AND login_fingerprint = $2
	`, source, loginFingerprint).Scan(&diaryAccountID, &studentID)
	if err == nil {
		_, err = tx.Exec(ctx, `
			UPDATE diary_accounts
			SET source_login_ciphertext = $1,
				source_password_ciphertext = $2,
				last_authenticated_at = NOW(),
				updated_at = NOW()
			WHERE id = $3
		`, loginCipher, passwordCipher, diaryAccountID)
		if err != nil {
			return uuid.Nil, uuid.Nil, err
		}
	} else if err == pgx.ErrNoRows {
		if err := tx.QueryRow(ctx, `INSERT INTO students DEFAULT VALUES RETURNING id`).Scan(&studentID); err != nil {
			return uuid.Nil, uuid.Nil, err
		}
		if err := tx.QueryRow(ctx, `
			INSERT INTO diary_accounts (
				student_id,
				source,
				login_fingerprint,
				source_login_ciphertext,
				source_password_ciphertext,
				last_authenticated_at
			)
			VALUES ($1, $2, $3, $4, $5, NOW())
			RETURNING id
		`, studentID, strings.ToLower(strings.TrimSpace(source)), loginFingerprint, loginCipher, passwordCipher).Scan(&diaryAccountID); err != nil {
			return uuid.Nil, uuid.Nil, err
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO student_profiles (
				student_id,
				first_name,
				last_name,
				grade_level,
				class_label,
				locale,
				timezone,
				created_at,
				updated_at
			)
			VALUES ($1, '', '', 1, '', 'ru-KZ', 'Asia/Qyzylorda', NOW(), NOW())
			ON CONFLICT (student_id) DO NOTHING
		`, studentID)
		if err != nil {
			return uuid.Nil, uuid.Nil, err
		}
	} else {
		return uuid.Nil, uuid.Nil, err
	}

	if _, err := tx.Exec(ctx, `UPDATE students SET updated_at = $1 WHERE id = $2`, time.Now().UTC(), studentID); err != nil {
		return uuid.Nil, uuid.Nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return uuid.Nil, uuid.Nil, err
	}
	return studentID, diaryAccountID, nil
}
