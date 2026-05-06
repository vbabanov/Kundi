#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

namespace Kundi.Editor
{
    public static class AvatarRuntimeValidator
    {
        [MenuItem("Kundi/Validate Avatar Runtime")]
        public static void Validate()
        {
            var runtimeController = Object.FindObjectOfType<Kundi.Runtime.AvatarRuntimeController>();
            if (runtimeController == null)
            {
                Debug.LogError("AvatarRuntimeController is missing in current scene.");
                return;
            }

            Debug.Log("Avatar runtime validation passed.");
        }
    }
}
#endif
