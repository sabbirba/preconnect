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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            val hasNamespace = namespace?.isNotEmpty() == true
            if (!hasNamespace) {
                namespace = "com.preconnect.${project.name.replace('-', '_')}"
            }
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
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
