package com.kundi.kundi_mobile.avatar

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

internal data class KundiCachedModel(
    val bytes: ByteArray,
    val prewarmed: Boolean,
)

internal object KundiNativeAvatarModelCache {
    private const val modelAssetPath = "kundi/kundi_home_mobile.glb"
    private val lock = Any()
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "kundi-avatar-prewarm").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var cachedBytes: ByteArray? = null
    private var generation = 0L

    fun prewarm(
        context: Context,
        completion: (Map<String, Any?>) -> Unit,
    ) {
        val startGeneration: Long
        synchronized(lock) {
            val cached = cachedBytes
            if (cached != null) {
                completion(
                    mapOf(
                        "status" to "alreadyCached",
                        "bytes" to cached.size,
                    ),
                )
                return
            }
            startGeneration = generation
        }

        executor.execute {
            runCatching {
                context.assets.open(modelAssetPath).use { it.readBytes() }
            }.onSuccess { bytes ->
                val retained =
                    synchronized(lock) {
                        if (generation == startGeneration && cachedBytes == null) {
                            cachedBytes = bytes
                            true
                        } else {
                            false
                        }
                    }
                mainHandler.post {
                    completion(
                        mapOf(
                            "status" to if (retained) "cached" else "superseded",
                            "bytes" to bytes.size,
                        ),
                    )
                }
            }.onFailure { error ->
                mainHandler.post {
                    completion(
                        mapOf(
                            "status" to "failed",
                            "message" to (error.message ?: error.javaClass.simpleName),
                        ),
                    )
                }
            }
        }
    }

    fun takeOrLoad(context: Context): KundiCachedModel {
        synchronized(lock) {
            generation++
            val cached = cachedBytes
            if (cached != null) {
                cachedBytes = null
                return KundiCachedModel(bytes = cached, prewarmed = true)
            }
        }
        val bytes = context.assets.open(modelAssetPath).use { it.readBytes() }
        return KundiCachedModel(bytes = bytes, prewarmed = false)
    }

    fun clear() {
        synchronized(lock) {
            generation++
            cachedBytes = null
        }
    }
}
