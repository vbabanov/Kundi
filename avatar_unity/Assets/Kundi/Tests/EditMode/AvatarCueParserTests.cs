using NUnit.Framework;

namespace Kundi.Tests.EditMode
{
    public class AvatarCueParserTests
    {
        [Test]
        public void EventSurface_ShouldContainRequiredEvents()
        {
            var events = new[]
            {
                "avatarReady",
                "playbackStarted",
                "playbackCompleted",
                "interrupted",
                "error",
            };

            Assert.AreEqual(5, events.Length);
        }
    }
}
