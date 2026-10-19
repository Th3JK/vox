allprojects {
    repositories {
        google()
        mavenCentral()

        // Unity ships prebuilt .aar files inside the exported project.
        if (rootProject.file("unityLibrary/libs").exists()) {
            flatDir { dirs(rootProject.file("unityLibrary/libs")) }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
