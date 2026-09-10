allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Nekateri starejši plugin-i (npr. on_audio_query_android 1.1.0) še ne
// nastavijo `namespace` v svojem build.gradle, kar novejši Android Gradle
// Plugin zahteva. Namesto da čakamo na upstream popravek, namespace
// naknadno preberemo iz AndroidManifest.xml `package` atributa in ga
// nastavimo, če ga knjižnica sama še ne definira. `plugins.withId` se sproži
// takoj ob apply-ju (ne šele ob afterEvaluate), zato se izognemo napaki
// "already evaluated" iz `evaluationDependsOn(":app")` spodaj.
subprojects {
    plugins.withId("com.android.library") {
        val androidExtension = extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (androidExtension.namespace == null) {
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val packageName = groovy.xml.XmlParser()
                    .parse(manifestFile)
                    .attribute("package") as String?
                if (packageName != null) {
                    androidExtension.namespace = packageName
                }
            }
        }

        // Isti stari plugin (on_audio_query_android) tudi ne nastavi
        // Java/Kotlin compile target, zato ta privzeto pade na 1.8 za javac
        // in novejšo JDK verzijo za Kotlin - AGP to zavrne kot neusklajeno.
        // Poravnamo oboje na 11 (enako kot v app/build.gradle.kts) direktno
        // na android extension-u, da nas AGP kasneje ne prepiše nazaj na 1.8.
        androidExtension.compileOptions {
            sourceCompatibility = JavaVersion.VERSION_11
            targetCompatibility = JavaVersion.VERSION_11
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
