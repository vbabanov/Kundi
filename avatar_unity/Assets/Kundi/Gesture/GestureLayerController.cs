using UnityEngine;

namespace Kundi.Gesture
{
    public sealed class GestureLayerController : MonoBehaviour
    {
        [SerializeField] private Animator animator;

        private static readonly int GestureHash = Animator.StringToHash("Gesture");

        public void PlayGesture(string gesture)
        {
            animator.SetTrigger(string.IsNullOrWhiteSpace(gesture) ? "gesture_default" : gesture.Trim().ToLowerInvariant());
            animator.SetInteger(GestureHash, GestureToInt(gesture));
        }

        private static int GestureToInt(string gesture)
        {
            if (string.IsNullOrWhiteSpace(gesture))
            {
                return 0;
            }

            switch (gesture.Trim().ToLowerInvariant())
            {
                case "explain":
                    return 1;
                case "open_hand":
                    return 2;
                case "celebrate":
                    return 3;
                default:
                    return 0;
            }
        }
    }
}
