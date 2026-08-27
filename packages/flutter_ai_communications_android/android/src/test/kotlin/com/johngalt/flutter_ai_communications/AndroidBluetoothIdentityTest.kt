package com.johngalt.flutter_ai_communications

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AndroidBluetoothIdentityTest {
    @Test
    fun carClassOfDeviceIsCar() {
        assertEquals("car", AndroidBluetoothIdentity.formFactor(0x420))
    }

    @Test
    fun handsFreeClassOfDeviceIsHeadset() {
        assertEquals("headset", AndroidBluetoothIdentity.formFactor(0x408))
    }

    @Test
    fun teslaAliasFillsHintsAndCarFormFactor() {
        val (hints, formFactor) =
            AndroidBluetoothIdentity.merge(
                name = "Headphones (Tesla Model Y)",
                routeClass = "bluetooth",
                address = "",
                devices =
                    listOf(
                        BluetoothIdentityRecord(name = "Tesla Model Y", classOfDevice = 0x420),
                    ),
            )
        assertEquals(listOf("Tesla Model Y"), hints)
        assertEquals("car", formFactor)
    }

    @Test
    fun deniedBluetoothLeavesNames() {
        val (hints, formFactor) =
            AndroidBluetoothIdentity.merge(
                name = "Headphones (Tesla Model Y)",
                routeClass = "bluetooth",
                address = "",
                devices = emptyList(),
            )
        assertTrue(hints.isEmpty())
        assertEquals("unknown", formFactor)
    }

    @Test
    fun wiredEndpointsAreNotRewritten() {
        val (hints, formFactor) =
            AndroidBluetoothIdentity.merge(
                name = "USB Headset",
                routeClass = "wired",
                address = "",
                devices =
                    listOf(
                        BluetoothIdentityRecord(name = "Tesla Model Y", classOfDevice = 0x420),
                    ),
            )
        assertTrue(hints.isEmpty())
        assertEquals("unknown", formFactor)
    }
}
