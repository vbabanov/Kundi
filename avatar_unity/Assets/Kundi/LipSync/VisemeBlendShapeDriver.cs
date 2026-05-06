using Kundi.Bridge;
using UnityEngine;

namespace Kundi.LipSync
{
    public sealed class VisemeBlendShapeDriver : MonoBehaviour
    {
        [SerializeField] private SkinnedMeshRenderer faceRenderer;

        private VisemePayload[] timeline = System.Array.Empty<VisemePayload>();

        public void Load(VisemePayload[] visemes)
        {
            timeline = visemes ?? System.Array.Empty<VisemePayload>();
        }

        public void ResetDriver()
        {
            timeline = System.Array.Empty<VisemePayload>();
            if (faceRenderer == null)
            {
                return;
            }

            for (var i = 0; i < faceRenderer.sharedMesh.blendShapeCount; i++)
            {
                faceRenderer.SetBlendShapeWeight(i, 0f);
            }
        }
    }
}
