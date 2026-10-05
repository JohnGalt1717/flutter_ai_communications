package com.johngalt.flutter_ai_communications

import android.media.AudioDeviceInfo

/** Capture-thread and Format-retry policy for the Android adapter. */
internal object AndroidCapturePolicy {
    /** HAL/read status that requires a verified alternative Native Format. */
    const val ERROR_UNSUPPORTED = -20

    /** AudioRecord.ERROR_DEAD_OBJECT. */
    const val ERROR_DEAD_OBJECT = -6

    const val DEFAULT_SAMPLE_RATE = 24_000

    val sampleRates: List<Int> = listOf(24_000, 48_000, 16_000, 32_000, 8_000)

    fun shouldRead(
        running: Boolean,
        generation: Int,
        threadGeneration: Int,
    ): Boolean = running && generation == threadGeneration

    fun isFatalRead(n: Int): Boolean = n == ERROR_UNSUPPORTED || n == ERROR_DEAD_OBJECT

    fun nextSampleRate(
        requested: Int,
        attempted: Set<Int>,
    ): Int? {
        val ordered = listOf(requested) + sampleRates.filter { it != requested }
        return ordered.firstOrNull { it !in attempted }
    }

    fun requestedSampleRate(raw: Any?, defaultRate: Int = DEFAULT_SAMPLE_RATE): Int {
        val map = raw as? Map<*, *> ?: return defaultRate
        val rate = (map["sampleRate"] as? Number)?.toInt() ?: return defaultRate
        return if (rate > 0) rate else defaultRate
    }

    fun formatMap(sampleRate: Int): Map<String, Any> =
        mapOf(
            "encoding" to "pcm16le",
            "sampleRate" to sampleRate,
            "channels" to 1,
        )

    fun failureMap(
        sampleRate: Int,
        reason: String = "unsupported",
    ): Map<String, Any> = formatMap(sampleRate) + mapOf("reason" to reason)

    fun failures(
        attempted: Collection<Int>,
        accepted: Int,
    ): List<Map<String, Any>> =
        attempted.filter { it != accepted }.map { failureMap(it) }

    fun presentId(id: String?): String? = id?.takeIf { it.isNotEmpty() }

    fun wantsCapture(captureId: String?, renderId: String?): Boolean {
        val capture = presentId(captureId)
        val render = presentId(renderId)
        return capture != null || render == null
    }

    fun wantsPlayback(captureId: String?, renderId: String?): Boolean {
        val capture = presentId(captureId)
        val render = presentId(renderId)
        return render != null || capture == null
    }

    fun isBuiltinCapture(selectedId: String?): Boolean =
        selectedId == "handset-in" || selectedId == "speaker-in"

    fun shouldPinPreferredCapture(selectedId: String?): Boolean =
        selectedId != null && !isBuiltinCapture(selectedId)

    fun isSpeakerRender(selectedId: String?): Boolean =
        selectedId == "speaker-out" || selectedId == "speakerphone-out"

    /** Tablets have a speaker and a mic, not an earpiece. */
    fun shouldAdvertiseHandset(hasEarpiece: Boolean): Boolean = hasEarpiece

    /** Fieldist [isSelectableInput]: builtin mic plus real external capture ports. */
    fun isSelectableInput(type: Int): Boolean =
        when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BUS,
            -> true
            else -> false
        }

    /** Fieldist [isSelectableOutput]: builtin speaker/earpiece plus real external render ports. */
    fun isSelectableOutput(type: Int): Boolean =
        when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_BUS,
            -> true
            else -> false
        }

    /** Covered by the synthetic handset and speakerphone rows. */
    fun isSyntheticType(type: Int): Boolean =
        when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC,
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
            -> true
            else -> false
        }

    fun isBluetoothVoiceType(type: Int): Boolean =
        type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            type == AudioDeviceInfo.TYPE_BLE_HEADSET

    fun isBluetoothMediaTwinType(type: Int): Boolean =
        type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            type == AudioDeviceInfo.TYPE_BLE_SPEAKER

    fun keepBluetoothOutput(
        type: Int,
        collapseKey: String,
        voiceKeys: Set<String>,
    ): Boolean = !(isBluetoothMediaTwinType(type) && collapseKey in voiceKeys)

    /**
     * Phone-as-USB-gadget rows use the device model as [productName]. A real
     * USB headset keeps its own product name.
     */
    fun isSelfNamedUsb(
        type: Int,
        productName: String?,
        model: String,
    ): Boolean {
        if (type != AudioDeviceInfo.TYPE_USB_DEVICE &&
            type != AudioDeviceInfo.TYPE_USB_HEADSET
        ) {
            return false
        }
        val name = productName?.trim().orEmpty()
        val phone = model.trim()
        if (name.isEmpty() || phone.isEmpty()) {
            return false
        }
        return name.equals(phone, ignoreCase = true) ||
            name.replace(" ", "").equals(phone.replace("-", ""), ignoreCase = true)
    }

    /**
     * Synthetic pair that carries [osDefault] when [communicationType] is the
     * builtin speaker, earpiece, or unset. Headset/car types leave the flag
     * on the physical catalog row instead.
     */
    fun syntheticOsDefault(communicationType: Int?): String? {
        if (communicationType != null &&
            !isSyntheticType(communicationType) &&
            (isSelectableInput(communicationType) || isSelectableOutput(communicationType))
        ) {
            return null
        }
        return "speakerphone"
    }

    fun planApplyRoute(selectedRenderId: String?): RouteApplyPlan {
        val speaker = isSpeakerRender(selectedRenderId)
        return RouteApplyPlan(
            speakerphoneOn = speaker,
            clearCommunicationDevice = !speaker,
            preferEarpiece = selectedRenderId == "handset-out",
        )
    }

    fun observedId(
        selectedId: String?,
        physicalMatchesSelected: Boolean,
        physicalCatalogId: String?,
    ): String? = if (physicalMatchesSelected) selectedId else physicalCatalogId ?: selectedId

    fun observedRenderId(
        selectedId: String?,
        speakerphoneOn: Boolean,
        physicalMatchesSelected: Boolean,
        physicalCatalogId: String?,
    ): String? {
        if (speakerphoneOn && !isSpeakerRender(selectedId)) {
            return "speaker-out"
        }
        return observedId(selectedId, physicalMatchesSelected, physicalCatalogId)
    }
}

/** How to leave or enter speakerphone without leaving a sticky OS route. */
internal data class RouteApplyPlan(
    val speakerphoneOn: Boolean,
    val clearCommunicationDevice: Boolean,
    val preferEarpiece: Boolean,
)
