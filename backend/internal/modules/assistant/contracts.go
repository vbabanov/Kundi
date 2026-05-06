package assistant

type Mode string

const (
	ModeTutor       Mode = "tutor"
	ModeGeneralChat Mode = "general_chat"
)

type MessageCommand struct {
	StudentID  string       `json:"student_id"`
	Mode       Mode         `json:"mode"`
	GradeLevel int          `json:"grade_level"`
	Text       string       `json:"text"`
	History    []ChatRecord `json:"history"`
}

type ChatRecord struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

type PedagogyFlags struct {
	NeedsScaffold      bool `json:"needs_scaffold"`
	ContainsHint       bool `json:"contains_hint"`
	ContainsStepPlan   bool `json:"contains_step_plan"`
	SafetyIntervention bool `json:"safety_intervention"`
}

type Viseme struct {
	OffsetMs int     `json:"offset_ms"`
	ID       string  `json:"id"`
	Weight   float64 `json:"weight"`
}

type Response struct {
	Text          string        `json:"text"`
	AudioURL      string        `json:"audioUrl"`
	AudioStatus   AudioStatus   `json:"audio_status"`
	Visemes       []Viseme      `json:"visemes"`
	AvatarEmotion string        `json:"avatar_emotion"`
	GestureTags   []string      `json:"gesture_tags"`
	Pedagogy      PedagogyFlags `json:"pedagogy_flags"`
	Behavior      BehaviorMeta  `json:"behavior"`
}

type AudioStatus string

const (
	AudioStatusReady       AudioStatus = "ready"
	AudioStatusUnavailable AudioStatus = "unavailable"
)

type BehaviorMeta struct {
	Mode         string `json:"mode"`
	GradeLevel   int    `json:"grade_level"`
	GradeBand    string `json:"grade_band"`
	PersonaTone  string `json:"persona_tone"`
	PersonaStyle string `json:"persona_style"`
}
