import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = "https://storage.googleapis.com/download.flutter.io")
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)
subprojects {
    val newSubprojectBuildDir: Directory = rootProject.layout.buildDirectory.dir(project.name).get()
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        if (project.name == "in_app_update") {
            project.plugins.apply("kotlin-android")
        }
        extensions.configure<LibraryExtension> {
            lint {
                disable += setOf("EasterEgg", "StopShip")
            }
            if (project.name == "in_app_update") {
                namespace = "de.ffuf.in_app_update"
            }
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        project.afterEvaluate {
            extensions.configure<LibraryExtension> {
                if (project.name != "in_app_update") {
                    val hasNamespace = namespace?.isNotEmpty() == true
                    if (!hasNamespace) {
                        namespace = "com.preconnect.${project.name.replace('-', '_')}"
                    }
                }
            }
        }
    }
}

subprojects {
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions.freeCompilerArgs.add("-Xjsr305=strict")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
