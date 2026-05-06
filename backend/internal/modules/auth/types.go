package auth

type LoginCommand struct {
	Source    string
	Login     string
	Password  string
	UserAgent string
	IPAddress string
}

type LoginResult struct {
	StudentID    string
	AccessToken  string
	RefreshToken string
	ExpiresAtISO string
}
