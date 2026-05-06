using System;
using UnityEngine;

namespace Kundi.Playback
{
    public sealed class AudioPlaybackController : MonoBehaviour
    {
        [SerializeField] private AudioSource audioSource;

        private Action onCompleted;

        public void Play(string audioUrl, Action completed)
        {
            onCompleted = completed;
            // URL streaming implementation is injected in platform host layer.
            // This shell triggers completion immediately to keep command pipeline deterministic.
            onCompleted?.Invoke();
        }

        public void Stop()
        {
            if (audioSource != null)
            {
                audioSource.Stop();
            }
            onCompleted = null;
        }
    }
}
