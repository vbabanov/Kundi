package contracts

// Canonical top-level DTO contracts used by transport and clients.

type LoginRequest struct {
	Source   string `json:"source"`
	Login    string `json:"login"`
	Password string `json:"password"`
}

type LoginResponse struct {
	StudentID    string `json:"student_id"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresAt    string `json:"expires_at"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type SendHomeworkDigestRequest struct {
	Date string `json:"date"`
	Mode string `json:"mode"`
}

type SendHomeworkPhotoRequest struct {
	HomeworkID   string   `json:"homework_id"`
	FileName     string   `json:"file_name"`
	FileBase64   string   `json:"file_base64"`
	Caption      string   `json:"caption"`
	ParentPhones []string `json:"parent_phones"`
}

type UpdateLocalAppProfileRequest struct {
	Shift        *int   `json:"shift"`
	ParentPhone1 string `json:"parent_phone_1"`
	ParentPhone2 string `json:"parent_phone_2"`
}
