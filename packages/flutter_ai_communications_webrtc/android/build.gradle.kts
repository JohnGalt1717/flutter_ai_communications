import java.io.File
import java.util.Properties

plugins {
    id("com.android.library")
}

group = "com.johngalt.flutter_ai_communications_webrtc"
version = "1.0-SNAPSHOT"

android {
    namespace = "com.johngalt.flutter_ai_communications_webrtc"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets.named("main") {
        java.directories.add("src/main/kotlin")
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

fun propertyFile(name: String): File? {
    val local = rootProject.file("local.properties")
    if (!local.exists()) {
        return null
    }
    val properties = Properties()
    local.inputStream().use { stream -> properties.load(stream) }
    return properties.getProperty(name)?.let(::File)
}

val flutterSdk: File =
    propertyFile("flutter.sdk")
        ?: System.getenv("FLUTTER_ROOT")?.let(::File)
        ?: File(System.getProperty("user.home"), "flutter")

val flutterJar = File(flutterSdk, "bin/cache/artifacts/engine/android-x64/flutter.jar")

// The Flutter Gradle plugin adds :flutter_webrtc and
// :flutter_ai_communications_android from pubspec. flutter_webrtc keeps the
// WebRTC SDK as its own implementation dependency, so compile against the
// same version here; the app ships flutter_webrtc's copy.
dependencies {
    if (flutterJar.exists()) {
        compileOnly(files(flutterJar))
    }
    compileOnly("io.github.webrtc-sdk:android:150.7871.01")
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.3.20")
}
