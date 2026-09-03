package com.kundi.kundi_mobile.avatar

internal data class KundiHomeAvatarPlacement(
    val cameraFovDegrees: Double,
    val cameraDistance: Double,
    val cameraEyeY: Double,
    val cameraTargetY: Double,
    val modelHalfExtent: Float,
    val modelOffsetX: Float,
    val modelOffsetY: Float,
    val heroRestNormalizedTime: Float,
) {
    init {
        require(cameraFovDegrees in 20.0..60.0) { "Invalid camera FOV" }
        require(cameraDistance in 1.0..8.0) { "Invalid camera distance" }
        require(cameraEyeY in -1.0..1.0) { "Invalid camera eye Y" }
        require(cameraTargetY in -1.0..1.0) { "Invalid camera target Y" }
        require(modelHalfExtent in 0.25f..2.0f) { "Invalid model half extent" }
        require(modelOffsetX in -1.0f..1.0f) { "Invalid model X offset" }
        require(modelOffsetY in -1.0f..1.0f) { "Invalid model Y offset" }
        require(heroRestNormalizedTime in 0f..1f) { "Invalid rest time" }
    }

    companion object {
        fun fromArguments(arguments: Map<*, *>?): KundiHomeAvatarPlacement {
            requireNotNull(arguments) { "avatar creation arguments are required" }
            return KundiHomeAvatarPlacement(
                cameraFovDegrees = arguments.requiredDouble("cameraFovDegrees"),
                cameraDistance = arguments.requiredDouble("cameraDistance"),
                cameraEyeY = arguments.requiredDouble("cameraEyeY"),
                cameraTargetY = arguments.requiredDouble("cameraTargetY"),
                modelHalfExtent = arguments.requiredDouble("modelHalfExtent").toFloat(),
                modelOffsetX = arguments.requiredDouble("modelOffsetX").toFloat(),
                modelOffsetY = arguments.requiredDouble("modelOffsetY").toFloat(),
                heroRestNormalizedTime =
                    arguments.requiredDouble("heroRestNormalizedTime").toFloat(),
            )
        }

        private fun Map<*, *>.requiredDouble(name: String): Double =
            (this[name] as? Number)?.toDouble()
                ?: throw IllegalArgumentException("$name is required")
    }
}
