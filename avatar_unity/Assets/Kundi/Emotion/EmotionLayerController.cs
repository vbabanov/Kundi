using UnityEngine;

namespace Kundi.Emotion
{
    public sealed class EmotionLayerController : MonoBehaviour
    {
        [SerializeField] private Animator animator;

        private static readonly int EmotionHash = Animator.StringToHash("Emotion");

        public void SetEmotion(string emotion)
        {
            var normalized = string.IsNullOrWhiteSpace(emotion) ? "neutral" : emotion.ToLowerInvariant();
            animator.SetInteger(EmotionHash, EmotionToInt(normalized));
        }

        private static int EmotionToInt(string emotion)
        {
            switch (emotion)
            {
                case "joy":
                case "happy":
                    return 1;
                case "think":
                case "thinking":
                    return 2;
                case "sad":
                    return 3;
                default:
                    return 0;
            }
        }
    }
}
