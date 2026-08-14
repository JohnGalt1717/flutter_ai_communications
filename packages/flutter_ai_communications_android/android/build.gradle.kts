import java.io.File
import java.util.Properties

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "com.johngalt.flutter_ai_communications"
version = "1.0-SNAPSHOT"

android {
    namespace = "com.johngalt.flutter_ai_communications"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets.named("main") {
        java.directories.add("src/main/kotlin")
    }
    sourceSets.named("test") {
        java.directories.add("src/test/kotlin")
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

val androidSdk: File =
    propertyFile("sdk.dir")
        ?: System.getenv("ANDROID_HOME")?.let(::File)
        ?: File(System.getProperty("user.home"), "Library/Android/sdk")

val flutterSdk: File =
    propertyFile("flutter.sdk")
        ?: System.getenv("FLUTTER_ROOT")?.let(::File)
        ?: File(System.getProperty("user.home"), "flutter")

val androidJar = File(androidSdk, "platforms/android-36/android.jar")
val flutterJar = File(flutterSdk, "bin/cache/artifacts/engine/android-x64/flutter.jar")

dependencies {
    if (androidJar.exists()) {
        compileOnly(files(androidJar))
    }
    if (flutterJar.exists()) {
        compileOnly(files(flutterJar))
    }
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.3.20")
    implementation("androidx.core:core-ktx:1.15.0")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
