import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = "https://storage.googleapis.com/download.flutter.io")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)
subprojects {
    val newSubprojectBuildDir: Directory =
        rootProject.layout.buildDirectory
            .dir(project.name)
            .get()
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            lint {
                checkReleaseBuilds = false
                abortOnError = false
                disable += setOf("EasterEgg", "StopShip")
            }
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        project.afterEvaluate {
            extensions.configure<LibraryExtension> {
                val hasNamespace = namespace?.isNotEmpty() == true
                if (!hasNamespace) {
                    namespace = "com.preconnect.${project.name.replace('-', '_')}"
                }
            }
        }
    }
    tasks.matching { it.name.startsWith("lintVital") }.configureEach {
        enabled = false
    }
}

subprojects {
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions.freeCompilerArgs.add("-Xjsr305=strict")
    }
}

subprojects {
    if (name == "camera_android_camerax") {
        plugins.withId("com.android.library") {
            dependencies.add(
                "implementation",
                "androidx.concurrent:concurrent-futures:1.1.0",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
