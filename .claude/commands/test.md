Run the SDK checks:

```bash
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
dotnet build examples/dotnet/EchoWorker/EchoWorker.csproj
swift build --package-path swift
swift test --package-path swift
swift build --package-path examples/swift/echo-worker
```

Build docs:

```bash
uvx --from mkdocs --with mkdocs-material mkdocs build --strict
```
