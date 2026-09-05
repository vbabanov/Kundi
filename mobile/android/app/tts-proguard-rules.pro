# Optional Reactor context propagation and Netty BlockHound integrations.
# Neither library is installed or used by the native SpeechSynthesizer path.
# These exact missing interfaces were reported by R8 for SDK 1.51.1.
-dontwarn io.micrometer.context.ContextAccessor
-dontwarn reactor.blockhound.integration.BlockHoundIntegration
