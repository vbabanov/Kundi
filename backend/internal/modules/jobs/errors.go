package jobs

import "errors"

type PermanentError struct {
	err error
}

func (e *PermanentError) Error() string {
	if e == nil || e.err == nil {
		return "permanent job failure"
	}
	return e.err.Error()
}

func (e *PermanentError) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.err
}

func Permanent(err error) error {
	if err == nil {
		return &PermanentError{}
	}
	var permanent *PermanentError
	if errors.As(err, &permanent) {
		return err
	}
	return &PermanentError{err: err}
}

func IsPermanent(err error) bool {
	var permanent *PermanentError
	return errors.As(err, &permanent)
}
