# Data model

- AppVersion: canonical stable `major.minor.patch+build`, numeric comparison including build; components are nonnegative integers. Prereleases are rejected.
- UpdateManifest: schemaVersion exactly 1; version; notes string <=20000 characters; assets nonempty map.
- ReleaseAsset: key `windows-x64`, `macos-x64`, `macos-arm64`, `linux-x64`; URL belongs to github.com/unng-lab/serverdeck/releases/download/<matching-tag>/; filename is a basename and has OS-specific .msi/.dmg/.deb suffix; size 1..1073741824; sha256 exactly 64 lowercase hexadecimal characters.
- UpdateSession: idle -> checking -> current/available/notPublished/unsupported/error; available -> downloading -> downloaded/error; downloaded -> installer opened (state stays downloaded). Checks/downloads serialize; cancellation on disposal aborts HTTP. Previous verified file is deleted before retry/disposal; partial files always removed after failure.
- UpdatePreference: autoCheck bool, default true, stored alongside theme using merged settings updates. Startup loads preference before checking. Automatic checks run only while app is alive, every six hours; manual check ignores opt-out.
- Package version source: pubspec.yaml. PackageInfo reads installed native version metadata; pubspec.yaml drives native version metadata and manifest. Preference JSON is an additive nullable field of the existing Isar metadata record; null means default settings.
