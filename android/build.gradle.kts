allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.get().dir("../../build")
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureAndroid: Project.() -> Unit = {
        extensions.findByName("android")?.let { androidExt ->
            try {
                val namespaceMethod = androidExt.javaClass.getMethod("getNamespace")
                val currentNamespace = namespaceMethod.invoke(androidExt) as? String
                if (currentNamespace.isNullOrBlank()) {
                    var packageName = "dev.unknown.pkg"
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val text = manifestFile.readText()
                        val match = Regex("""package="([^"]*)"""").find(text)
                        if (match != null) {
                            packageName = match.groupValues[1]
                        }
                    }
                    val setNamespaceMethod = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespaceMethod.invoke(androidExt, packageName)
                }
            } catch (e: Exception) {
                // Ignore reflection or resolution errors
            }
        }
    }

    if (state.executed) {
        configureAndroid()
    } else {
        afterEvaluate {
            configureAndroid()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
