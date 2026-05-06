using UnityEngine;

namespace Kundi.Timeline
{
    public sealed class AvatarTimelineCoordinator : MonoBehaviour
    {
        [SerializeField] private bool enableIdleMicroMotion = true;

        private void Update()
        {
            if (!enableIdleMicroMotion)
            {
                return;
            }

            // Placeholder for deterministic micro-motion curve execution.
        }
    }
}
