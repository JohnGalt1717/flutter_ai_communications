package com.johngalt.flutter_ai_communications

/** Bluetooth alias / Class of Device used to enrich audio Endpoints. */
internal data class BluetoothIdentityRecord(
    val name: String,
    val classOfDevice: Int,
    val address: String = "",
)

/** Merge and Class-of-Device mapping for Android Bluetooth identity. */
internal object AndroidBluetoothIdentity {
    fun formFactor(classOfDevice: Int): String {
        val major = (classOfDevice shr 8) and 0x1f
        if (major != 4) {
            return "unknown"
        }
        return when ((classOfDevice shr 2) and 0x3f) {
            1, 2, 4, 6, 7 -> "headset"
            5, 10, 15 -> "speaker"
            8 -> "car"
            else -> "unknown"
        }
    }

    fun formFactorForAudioType(type: Int): String =
        when (type) {
            7, 26 -> "headset" // TYPE_BLUETOOTH_SCO, TYPE_BLE_HEADSET
            21, 22 -> "car" // TYPE_BUS, TYPE_AUX_LINE
            1 -> "handset" // TYPE_BUILTIN_EARPIECE
            else -> "unknown"
        }

    fun merge(
        name: String,
        routeClass: String,
        address: String,
        devices: List<BluetoothIdentityRecord>,
    ): Pair<List<String>, String> {
        if (devices.isEmpty() || (routeClass != "bluetooth" && routeClass != "car")) {
            return emptyList<String>() to "unknown"
        }
        val match =
            devices.firstOrNull { device ->
                namesOverlap(name, device.name) ||
                    (device.address.isNotEmpty() && address.contains(device.address, ignoreCase = true))
            } ?: return emptyList<String>() to "unknown"
        val hints = if (match.name.isNotEmpty()) listOf(match.name) else emptyList()
        return hints to formFactor(match.classOfDevice)
    }

    private fun namesOverlap(left: String, right: String): Boolean {
        val a = normalize(left)
        val b = normalize(right)
        if (a.length < 4 || b.length < 4) {
            return false
        }
        return a.contains(b) || b.contains(a)
    }

    private fun normalize(name: String): String =
        name.lowercase().replace(Regex("[^a-z0-9]+"), " ").trim()
}
