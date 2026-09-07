package com.kundi.kundi_mobile.avatar

import kotlin.math.abs

/**
 * Composes expression, mouth and blink as independent facial channels.
 * Expression changes cross-fade; viseme updates can never erase expression.
 */
internal class KundiAvatarFaceState(
    private val neutralBlendShape: String,
    private val blinkBlendShape: String,
    private val transitionDurationNanos: Long = 240_000_000L,
) {
    private var currentExpression = mapOf(neutralBlendShape to 1f)
    private var transitionFrom = currentExpression
    private var transitionTarget = currentExpression
    private var transitionStartedNanos = 0L
    private var mouthBlendShape: String? = null
    private var mouthWeight = 0f
    private var blinkWeight = 0f

    var transitionPending: Boolean = false
        private set

    init {
        require(neutralBlendShape.isNotBlank()) { "Neutral blend shape is required" }
        require(blinkBlendShape.isNotBlank()) { "Blink blend shape is required" }
        require(transitionDurationNanos > 0L) { "Face transition duration must be positive" }
    }

    fun setEmotion(
        blendShape: String,
        intensity: Float,
        nowNanos: Long,
    ) {
        require(blendShape.isNotBlank()) { "Emotion blend shape is required" }
        require(intensity.isFinite() && intensity in 0f..1f) {
            "Emotion intensity must be between 0 and 1"
        }
        val from = expressionAt(nowNanos)
        val target =
            if (intensity == 0f) {
                emptyMap()
            } else {
                mapOf(blendShape to intensity)
            }
        transitionFrom = from
        transitionTarget = target
        transitionStartedNanos = nowNanos
        transitionPending = !sameWeights(from, target)
        if (!transitionPending) currentExpression = target
    }

    fun setViseme(
        blendShape: String,
        weight: Float,
    ) {
        require(blendShape.isNotBlank()) { "Viseme blend shape is required" }
        require(weight.isFinite() && weight in 0f..1f) {
            "Viseme weight must be between 0 and 1"
        }
        mouthBlendShape = blendShape
        mouthWeight = weight
    }

    fun clearViseme() {
        mouthBlendShape = null
        mouthWeight = 0f
    }

    fun setBlink(weight: Float) {
        require(weight.isFinite() && weight in 0f..1f) {
            "Blink weight must be between 0 and 1"
        }
        blinkWeight = weight
    }

    fun reset() {
        currentExpression = mapOf(neutralBlendShape to 1f)
        transitionFrom = currentExpression
        transitionTarget = currentExpression
        transitionStartedNanos = 0L
        transitionPending = false
        clearViseme()
        blinkWeight = 0f
    }

    fun snapshot(nowNanos: Long): Map<String, Float> =
        buildMap {
            putAll(expressionAt(nowNanos))
            mouthBlendShape?.let { shape ->
                if (mouthWeight > 0f) put(shape, mouthWeight)
            }
            if (blinkWeight > 0f) put(blinkBlendShape, blinkWeight)
        }

    private fun expressionAt(nowNanos: Long): Map<String, Float> {
        if (!transitionPending) return currentExpression
        val elapsed = (nowNanos - transitionStartedNanos).coerceAtLeast(0L)
        val progress = (elapsed.toDouble() / transitionDurationNanos).toFloat().coerceIn(0f, 1f)
        val keys = transitionFrom.keys + transitionTarget.keys
        val interpolated =
            buildMap {
                keys.forEach { key ->
                    val from = transitionFrom[key] ?: 0f
                    val target = transitionTarget[key] ?: 0f
                    val value = from + ((target - from) * progress)
                    if (value > weightEpsilon) put(key, value)
                }
            }
        if (progress >= 1f) {
            currentExpression = transitionTarget
            transitionPending = false
            return currentExpression
        }
        currentExpression = interpolated
        return interpolated
    }

    private fun sameWeights(
        first: Map<String, Float>,
        second: Map<String, Float>,
    ): Boolean {
        val keys = first.keys + second.keys
        return keys.all { key -> abs((first[key] ?: 0f) - (second[key] ?: 0f)) <= weightEpsilon }
    }

    private companion object {
        const val weightEpsilon = 0.0001f
    }
}
