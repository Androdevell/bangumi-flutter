import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file(
    providers.gradleProperty("bangumi.signingProperties").orElse("key.properties").get(),
)
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

val signingFields = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val releaseSigningReady = keystorePropertiesFile.exists() &&
    signingFields.all { !keystoreProperties.getProperty(it).isNullOrBlank() }

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release", ignoreCase = true) }) {
        if (!releaseSigningReady) {
            throw GradleException("Release 构建必须提供完整的 key.properties，拒绝使用 debug 签名")
        }
        if (!file(keystoreProperties.getProperty("storeFile")).isFile) {
            throw GradleException("Release 签名文件不存在，请检查 key.properties 的 storeFile")
        }
        if (flutter.versionCode <= 2006) {
            throw GradleException("Release versionCode 必须高于已发布的 1.1.4（2006），避免降级安装")
        }
        val defines = providers.gradleProperty("dart-defines").orNull.orEmpty()
            .split(',').mapNotNull { encoded ->
                runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }.getOrNull()
            }.associate { decoded -> decoded.substringBefore('=') to decoded.substringAfter('=', "") }
        if (defines["BGM_OAUTH_APP_ID"].isNullOrBlank() ||
            defines["BGM_OAUTH_APP_SECRET"].isNullOrBlank()) {
            throw GradleException("Release 必须包含完整 OAuth 构建配置，拒绝生成不可登录的正式包")
        }
    }
}

android {
    namespace = "com.bgm.irena"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.bgm.irena"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            ndk {
                abiFilters.add("arm64-v8a")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.conscrypt:conscrypt-android:2.6.3")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
