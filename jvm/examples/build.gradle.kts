dependencies {
    implementation(project(":core"))
    implementation(project(":nats"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    implementation("ch.qos.logback:logback-classic:1.4.14")
}

tasks.create<JavaExec>("runKotlinEcho") {
    mainClass.set("heddle.examples.KotlinEchoWorkerKt")
    classpath = sourceSets.main.get().runtimeClasspath
}

tasks.create<JavaExec>("runJavaEcho") {
    mainClass.set("heddle.examples.JavaEchoWorker")
    classpath = sourceSets.main.get().runtimeClasspath
}
