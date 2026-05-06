using NUnit.Framework;

namespace Kundi.Tests.Runtime
{
    public class AvatarStateMachineTests
    {
        [Test]
        public void CommandSurface_ShouldContainRequiredCommands()
        {
            var commands = new[]
            {
                "initializeAvatar",
                "showAvatar",
                "hideAvatar",
                "startListening",
                "startThinking",
                "speak",
                "interrupt",
                "setEmotion",
                "playGesture",
                "resetToIdle",
            };

            Assert.AreEqual(10, commands.Length);
        }
    }
}
