using System;
using UnityEngine;

namespace Kundi.Runtime
{
    public sealed class AvatarRuntimeController : MonoBehaviour
    {
        [SerializeField] private Animator animator;
        [SerializeField] private Playback.AudioPlaybackController audioPlayback;
        [SerializeField] private LipSync.VisemeBlendShapeDriver visemeDriver;
        [SerializeField] private Emotion.EmotionLayerController emotionLayer;
        [SerializeField] private Gesture.GestureLayerController gestureLayer;

        public event Action<string, string> AvatarEvent;

        private bool initialized;
        private static readonly int IsVisible = Animator.StringToHash("IsVisible");
        private static readonly int IsListening = Animator.StringToHash("IsListening");
        private static readonly int IsThinking = Animator.StringToHash("IsThinking");
        private static readonly int TriggerSpeak = Animator.StringToHash("Speak");
        private static readonly int TriggerInterrupt = Animator.StringToHash("Interrupt");
        private static readonly int TriggerResetIdle = Animator.StringToHash("ResetIdle");

        public void InitializeAvatar()
        {
            if (initialized)
            {
                return;
            }

            initialized = true;
            animator.Rebind();
            animator.Update(0f);
            AvatarEvent?.Invoke("avatarReady", "{}");
        }

        public void ShowAvatar()
        {
            EnsureInitialized();
            animator.SetBool(IsVisible, true);
        }

        public void HideAvatar()
        {
            EnsureInitialized();
            animator.SetBool(IsVisible, false);
            Interrupt();
        }

        public void StartListening()
        {
            EnsureInitialized();
            animator.SetBool(IsThinking, false);
            animator.SetBool(IsListening, true);
        }

        public void StartThinking()
        {
            EnsureInitialized();
            animator.SetBool(IsListening, false);
            animator.SetBool(IsThinking, true);
        }

        public void Speak(Bridge.AvatarSpeakPayload payload)
        {
            EnsureInitialized();
            animator.SetBool(IsListening, false);
            animator.SetBool(IsThinking, false);
            animator.SetTrigger(TriggerSpeak);

            emotionLayer.SetEmotion(payload.Emotion);
            gestureLayer.PlayGesture(payload.PrimaryGesture);
            visemeDriver.Load(payload.Visemes);

            AvatarEvent?.Invoke("playbackStarted", "{}");
            audioPlayback.Play(payload.AudioUrl, OnPlaybackCompleted);
        }

        public void Interrupt()
        {
            EnsureInitialized();
            audioPlayback.Stop();
            visemeDriver.ResetDriver();
            animator.SetTrigger(TriggerInterrupt);
            AvatarEvent?.Invoke("interrupted", "{}");
        }

        public void SetEmotion(string emotion)
        {
            EnsureInitialized();
            emotionLayer.SetEmotion(emotion);
        }

        public void PlayGesture(string gesture)
        {
            EnsureInitialized();
            gestureLayer.PlayGesture(gesture);
        }

        public void ResetToIdle()
        {
            EnsureInitialized();
            animator.SetBool(IsListening, false);
            animator.SetBool(IsThinking, false);
            animator.SetTrigger(TriggerResetIdle);
            visemeDriver.ResetDriver();
        }

        private void OnPlaybackCompleted()
        {
            visemeDriver.ResetDriver();
            AvatarEvent?.Invoke("playbackCompleted", "{}");
        }

        private void EnsureInitialized()
        {
            if (initialized)
            {
                return;
            }

            throw new InvalidOperationException("Avatar runtime must be initialized first.");
        }
    }
}
