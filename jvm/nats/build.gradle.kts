dependencies {
    implementation(project(":core"))
    implementation("io.nats:jnats:2.17.6")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    implementation("org.slf4j:slf4j-api:2.0.11")
    
    testImplementation(kotlin("test"))
}
