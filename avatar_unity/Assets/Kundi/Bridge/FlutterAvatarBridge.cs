using System;
using UnityEngine;
using Kundi.Runtime;

namespace Kundi.Bridge
{
    [Serializable]
    public sealed class AvatarSpeakPayload
    {
        public string Text;
        public string AudioUrl;
        public string Emotion;
        public string PrimaryGesture;
        public VisemePayload[] Visemes;
    }

    [Serializable]
    public sealed class VisemePayload
    {
        public int OffsetMs;
        public string Id;
        public float Weight;
    }

    public sealed class FlutterAvatarBridge : MonoBehaviour
    {
        [SerializeField] private AvatarRuntimeController runtimeController;

        public void HandleCommand(string command, string payloadJson)
        {
            try
            {
                switch (command)
                {
                    case "initializeAvatar":
                        runtimeController.InitializeAvatar();
                        break;
                    case "showAvatar":
                        runtimeController.ShowAvatar();
                        break;
                    case "hideAvatar":
                        runtimeController.HideAvatar();
                        break;
                    case "startListening":
                        runtimeController.StartListening();
                        break;
                    case "startThinking":
                        runtimeController.StartThinking();
                        break;
                    case "speak":
                        var speakPayload = JsonUtility.FromJson<AvatarSpeakPayload>(payloadJson);
                        runtimeController.Speak(speakPayload ?? new AvatarSpeakPayload());
                        break;
                    case "interrupt":
                        runtimeController.Interrupt();
                        break;
                    case "setEmotion":
                        runtimeController.SetEmotion(payloadJson);
                        break;
                    case "playGesture":
                        runtimeController.PlayGesture(payloadJson);
                        break;
                    case "resetToIdle":
                        runtimeController.ResetToIdle();
                        break;
                    default:
                        EmitEvent("error", "{\"message\":\"unknown command\"}");
                        break;
                }
            }
            catch (Exception exception)
            {
                EmitEvent("error", "{\"message\":\"" + exception.Message + "\"}");
            }
        }

        private void OnEnable()
        {
            runtimeController.AvatarEvent += EmitEvent;
        }

        private void OnDisable()
        {
            runtimeController.AvatarEvent -= EmitEvent;
        }

        private void EmitEvent(string eventName, string payload)
        {
            Debug.Log($"AvatarEvent: {eventName} payload={payload}");
            // Native host bridge should forward this event to Flutter event channel.
        }
    }
}
