# Third-party notices audit — 001.1

Current checkpoint 2026-10-13 for T045/T207/T233: the source-built Isar3.3.2 DLL is activated for local builds, and both actual normal Windows Debug/Release bundles contain the complete bound third-party notice payload. The final checkpoint below records the checked source/dependency artifacts, qualification and actual bundle evidence. Earlier dated checkpoints retain their original scope and limitations; they do not describe the current provider. Completed independent review found no defects, verified actual qualified selection and both normal bundles, and supported closure of T045/T207/T233 within their native-build scope. No application license is assigned here; full product/manual/CI acceptance and publication remain separate.

## Offline source-text preview — T089

`tools/collect-third-party-notices.ps1` reads the four actual configs/lockfiles and installed package identities without network or executing dependency binaries. It includes each root LICENSE and any additional root NOTICE/COPYING, the full Flutter/Dart/sky_engine/OFL sources and five pinned native texts under `licenses/native/`. The native source metadata retains public URLs/commits/SHA-256; these texts are preserved byte-for-byte in Git with a scoped no-newline-conversion attribute. No brandbook source is modified.

Run from repository root in PowerShell7:

```powershell
./tools/collect-third-party-notices.ps1
./tools/test-third-party-notices.ps1
```

Default output: `build/foundation/notices/THIRD_PARTY_NOTICES.preview.txt` and `notices.preview.json`. Both explicitly mark incomplete-native-chain/distributionReady false. No final THIRD_PARTY_NOTICES.txt is produced, no build wiring changes and no application license is assigned. Parameters WorkspaceRoot/SdkDirectory support owned source fixtures; OutputDirectory must stay inside the selected workspace and cannot traverse reparse ancestors. Input identity/license/hash checks complete before output replacement. SDK metadata must match the pinned framework/Dart identity; this is a source-file check, not runtime/compiled build verification.

Actual collection:89package versions,98source texts,1,561,772preview bytes; SHA-256 `884163465e29b145af7c63e21f146dd027fd89b9a44f671c42f60a0c3d8c3c8d`. Fixture tests verify two versions, full texts, source and output hashes, deterministic output, version/missing/empty-license/outside-target/pinned-native-hash rejection with previous output retained. A duplicate native source ID regression first failed, then passed after enforcing the exact five unique source IDs. Synthetic fixture SDK/source files do not prove native acceptance. No DLL or encryption tests execute in these scripts.

## Resolved Dart package sources

T090 output containment: both destination entries are checked for reparse points/directories before either write. New CreateNew regular temporary files replace entries, leaving outside hardlink aliases unchanged. Owned fixtures cover both hardlink outputs and a destination junction rejection before preview changes. Each file replacement is separate; the pair is not a transaction and previewSha256 detects an interrupted mismatched pair. Re-running the collector restores deterministic output. Symbolic-link-specific behavior has not been executed; the reparse gate is exercised with a junction.

Four package_config.json files were inspected: root, serverdeck_locald, serverdeck_protocol and serverdeck_windows. 89 distinct hosted package versions were found; all 89 contain a root LICENSE. This conservatively includes development dependencies; it does not assert all listed packages are shipped. Versions are retained separately rather than collapsing entries by package name. For example analyzer10.2.0/13.3.0, _fe_analyzer_shared96.0.0/103.0.0 and meta1.18.3/1.19.0 coexist in different resolutions.

SHA-256 below identifies the bytes read from each installed LICENSE; hashes do not classify licenses or prove release compliance. Actual license text and attribution must be retained in the eventual bundle. The ignored local machine-readable evidence is .local/audits/resolved-license-inventory.json; this document preserves the public, machine-independent inventory.

| Installed package/version | LICENSE SHA-256 | Resolutions |
| --- | --- | --- |
| _fe_analyzer_shared-103.0.0 | efa31b5ac790016736fa9761642b0af16d37cd4fb483de2905adb5258cb89722 | serverdeck_protocol, serverdeck_windows |
| _fe_analyzer_shared-96.0.0 | efa31b5ac790016736fa9761642b0af16d37cd4fb483de2905adb5258cb89722 | serverdeck_locald |
| analyzer-10.2.0 | 7e124af6a556f045cb3a20cafbdaa31602ac2c82cbcb3c3b15faaaf514b06028 | serverdeck_locald |
| analyzer-13.3.0 | 7e124af6a556f045cb3a20cafbdaa31602ac2c82cbcb3c3b15faaaf514b06028 | serverdeck_protocol, serverdeck_windows |
| args-2.7.0 | dfb09c74e29386cd3e2719f32d4995d59526179753931d31840757c77fbf2791 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| async-2.13.1 | ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| boolean_selector-2.1.2 | b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| build_config-1.2.0 | ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5 | serverdeck_locald |
| build_daemon-4.1.6 | 0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744 | serverdeck_locald |
| build_runner-2.10.5 | a4b5d7d31626e90b77e8696f1c47643aa31f52e17c1907c1ab60b068110e6e10 | serverdeck_locald |
| build-4.0.7 | a4b5d7d31626e90b77e8696f1c47643aa31f52e17c1907c1ab60b068110e6e10 | serverdeck_locald |
| built_collection-5.1.2 | 4f1b0f444c862e8dc586122c00592538fb0e9dd6d81a5214882b25b8054f7dfa | serverdeck_locald |
| built_value-8.13.0 | 4f1b0f444c862e8dc586122c00592538fb0e9dd6d81a5214882b25b8054f7dfa | serverdeck_locald |
| characters-1.4.1 | 0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744 | root, serverdeck_locald |
| checked_yaml-2.0.4 | 4771d808721f4d5f02318ab857c92f5a5dce87b14ae1c3770fe21ca7fd4a9280 | serverdeck_locald |
| cli_config-0.2.0 | 605bcf409f2347e3bcc9905ab70a2f3218e841bae372b0cbfbf305a222f74222 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| clock-1.1.3 | 58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd | root, serverdeck_locald |
| code_builder-4.12.0 | a4b5d7d31626e90b77e8696f1c47643aa31f52e17c1907c1ab60b068110e6e10 | serverdeck_locald |
| collection-1.19.1 | ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| convert-3.1.2 | ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| coverage-1.15.1 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| crypto-3.0.7 | ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| cryptography-2.9.0 | 59899c6091b540582ed617e8eeaac4919dc985ccfc35459ee9752b699be5205b | root, serverdeck_locald |
| dart_style-3.1.7 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald |
| dartx-1.2.0 | 347ddeffb5175ccb290ef8b96adce2faea1a3f2e465983deeff9d230269b5fa5 | serverdeck_locald |
| fake_async-1.3.3 | 58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd | root |
| ffi_leak_tracker-0.1.2 | 332f290333e64ed007b4f59aeeebd8fd3ceaadfbfa226a6cf2a3ab1583281624 | root, serverdeck_locald, serverdeck_windows |
| ffi-2.2.0 | 0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744 | root, serverdeck_locald, serverdeck_windows |
| file-7.0.1 | f6df86b1412172537273e8e80ee2fb8a66aa7307ce0b39ea5ddab47ca41b8c49 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| fixnum-1.1.1 | ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390 | serverdeck_locald |
| frontend_server_client-4.1.0 | 2cfa3ee8e7512e6d44c854b986510810fadc815f93f890373b3a81c1b6ccd256 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| glob-2.2.0 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| graphs-2.3.2 | ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5 | serverdeck_locald |
| http_multi_server-3.2.2 | ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| http_parser-4.1.2 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| io-1.1.0 | ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| isar_community_flutter_libs-3.3.2 | 58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd | root |
| isar_community_generator-3.3.2 | 58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd | serverdeck_locald |
| isar_community-3.3.2 | c41a720c120c21505f1a313781e0d5d699877b33399bbb802ccd7fa416ed5052 | root, serverdeck_locald |
| js-0.7.2 | efa4eaf6fdec22a36a61395ea70843db9ae815760bf663e068012c92b93c0184 | root, serverdeck_locald |
| json_annotation-4.12.0 | 143839f62c9b7f88143ea9f688361c27050888acde7696b34e04414bd254fafc | serverdeck_locald |
| leak_tracker_flutter_testing-3.0.10 | 08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6 | root |
| leak_tracker_testing-3.0.2 | 08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6 | root |
| leak_tracker-11.0.2 | 08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6 | root |
| logging-1.3.0 | dfb09c74e29386cd3e2719f32d4995d59526179753931d31840757c77fbf2791 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| matcher-0.12.20 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| material_color_utilities-0.13.0 | d103f246ef4c18dab8af0c1dcf6a8af884e5cff554da7261a48ac43c17d98f2e | root |
| meta-1.18.3 | b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a | root |
| meta-1.19.0 | b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| mime-2.1.0 | ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| node_preamble-2.0.2 | 41997ee02074e3796e539b81b4501ed7d8bc1a620d11ef32cf56494e778461a9 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| package_config-2.2.0 | 0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| path-1.9.1 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| platform-3.2.0 | 143839f62c9b7f88143ea9f688361c27050888acde7696b34e04414bd254fafc | root |
| pool-1.5.3 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| process-5.0.6 | 5f018bbc25a55406d7a4e1d3229135439e315210b0050ca56dbb367a4934e85d | root |
| pub_semver-2.2.1 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| pubspec_parse-1.6.0 | 479bb84361ed3d6b78f55871c9ae5d6c8f15f49c2089e59fc1d6644d8b0ed32b | serverdeck_locald |
| shelf_packages_handler-3.0.2 | b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| shelf_static-1.1.3 | ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| shelf_web_socket-3.0.0 | ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| shelf-1.4.2 | ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| source_gen-4.2.4 | ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888 | serverdeck_locald |
| source_map_stack_trace-2.1.2 | ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| source_maps-0.10.14 | ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| source_span-1.10.2 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| stack_trace-1.12.2 | ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| stream_channel-2.1.4 | ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| stream_transform-2.1.2 | ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5 | serverdeck_locald |
| string_scanner-1.4.1 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| sync_http-0.3.1 | b9b748d4dd6f725387bf69e96df4e4ebff167ae83547954242a731504d037644 | root |
| term_glyph-1.2.2 | ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| test_api-0.7.12 | ff1b9f0df9036c04be424b1e3ce12789bea880ad5ffc3a48e069ae2d40a087a4 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| test_core-0.6.18 | ff1b9f0df9036c04be424b1e3ce12789bea880ad5ffc3a48e069ae2d40a087a4 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| test-1.31.1 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| time-2.1.6 | a992e80fde9630e9f2d3ca68cad031d4d843469487da5a619164464402dcba9c | serverdeck_locald |
| typed_data-1.4.0 | ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| unorm_dart-0.3.3 | 8884fc22f0944465ab8fca4e934fef3db9ab2b3b14f95874f1d833aa75f81553 | root, serverdeck_locald, serverdeck_protocol |
| vector_math-2.4.0 | 420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d | root |
| vm_service-15.3.0 | ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888 | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| watcher-1.2.1 | 3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| web_socket_channel-3.0.3 | a4b5d7d31626e90b77e8696f1c47643aa31f52e17c1907c1ab60b068110e6e10 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| web_socket-1.0.1 | cbe822ef3446af4366b2b82c48b0979d0b12865edfe74c22b9aa617fc362d6e0 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| web-1.1.1 | aa913ff50d7542eb8cc35b9f48a80928ac6819ba9057f85d424655e3e8dc271c | root, serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| webdriver-3.2.0 | 74cb46b123c9fa918ea8e0a0f5be736a1cd661edf145ccc723dc7ce30324ebab | root |
| webkit_inspection_protocol-1.2.1 | eb9a6b9672316612439514f10b5d3b24bcd140313c96a73c370bb7b07897a8cd | serverdeck_locald, serverdeck_protocol, serverdeck_windows |
| win32-6.4.0 | 87ef8bccdd619f2345ba5b9026cf1d6cccb305e36ab83849a8a3af9293abde7e | root, serverdeck_locald, serverdeck_windows |
| xxh3-1.2.0 | 9a1e81c2a0f8f7e798bc548b9de8e0aafd816da1377866571fce5b5cc9667757 | serverdeck_locald |
| yaml-3.1.4 | d47b93335401b052d79a2f5a3710e4cf7b5aed782faedf84d40fbdd6eb934ec7 | serverdeck_locald, serverdeck_protocol, serverdeck_windows |

## Flutter/Dart and fonts

- .local/sdk/3.47.7/flutter/LICENSE: 1544 bytes; SHA-256 a3a9fd82f800a47377f7d3f60c60a5c91cae0495be8f329031e1448ce0f5dab9.
- .local/sdk/3.47.7/flutter/bin/cache/dart-sdk/LICENSE: 1502 bytes; SHA-256 2cfa3ee8e7512e6d44c854b986510810fadc815f93f890373b3a81c1b6ccd256.
- .local/sdk/3.47.7/flutter/bin/cache/pkg/sky_engine/LICENSE: 1269349 bytes; SHA-256 3c0040023a5789bf56d6bf41fd44f08b21758523d41f128fb7dd6beb398d1191.
- assets/brand/fonts/OFL.txt: 4377 bytes; SHA-256 0dab92d0544f7b233403f14b84a663bdbfa746982eda629e7f4f9ffe1b036feb.

Pinned Flutter3.47.7 / Dart3.13.5 are unchanged. The actual sky_engine LICENSE is a 1,269,349-byte third-party collection; the small engine license.windows_flutter.md is a pointer, not a replacement for these notices. Noto Sans400/600 and Noto Sans Mono400 use the preserved bundled OFL.txt; T087 tests independently confirmed source/resource byte parity, actual font loading and weights. Engine/runtime and build-only SDK notices still need distribution-scope verification.

## Historical native-source checkpoint — 2026-10-11

Installed isar_community / isar_community_flutter_libs / isar_community_generator3.3.2 each carry an Apache2.0 LICENSE, included in the inventory above. The advertised upstream tag3.3.2 resolves to commit4c2cd02d4e5c17b7edca89d141d1729ddc1698ff; the tag reference was read from the GitHub API. This is source-reference evidence, not proof that the downloaded DLL was reproducibly built from that commit.

The pinned [Isar NOTICE](https://raw.githubusercontent.com/isar-community/isar-community/4c2cd02d4e5c17b7edca89d141d1729ddc1698ff/NOTICE) attributes libmdbx under Apache2.0. The separate [mdbx-sys Cargo metadata](https://raw.githubusercontent.com/isar-community/isar-community/4c2cd02d4e5c17b7edca89d141d1729ddc1698ff/packages/mdbx_sys/Cargo.toml) declares MPL2.0 for Rust bindings13.7.0. These are different components; a single generic license label would lose this distinction. Preserve both notices/terms until the native chain is fully verified.

Pinned [build.rs](https://raw.githubusercontent.com/isar-community/isar-community/4c2cd02d4e5c17b7edca89d141d1729ddc1698ff/packages/mdbx_sys/build.rs) names the separate source repository https://github.com/isar-community/libmdbx.git and tag v0.13.8-temp-upstream-fix. The Isar source tree contains no Cargo.lock at this tag; semver declarations alone do not establish the resolved Rust dependency versions of the distributed DLL. Native dependency notices, source references and corresponding-source requirements therefore remain under T045; do not infer exact resolved versions from these declarations.

Installed Windows libisar.dll SHA-256: f1f96cf6e7a7b582b2387801f97d72d8f89f7c0642ad57bc40338fc15e08ea67. Only file metadata/source licenses were read; the DLL was not loaded and no encryption/native acceptance tests were run.

Remaining T045 work: finish the native source/dependency audit without guessing DLL build provenance; complete all required source texts/attributions for that chain; generate and include THIRD_PARTY_NOTICES.txt in the complete Windows bundle; verify actual output before declaring distribution notices complete. Full001.1 acceptance, publishing and merge remain open.

### Release asset identity checkpoint — 2026-10-11

GitHub release API for tag3.3.2 reports release300390969, published2026-03-23T20:19:52Z. Its isar_windows_x64.dll asset379966240 is996352bytes with digest sha256:f1f96cf6e7a7b582b2387801f97d72d8f89f7c0642ad57bc40338fc15e08ea67. Re-reading the installed libisar.dll confirmed both byte length and SHA-256 match. This establishes correspondence to the advertised release asset; it does not prove a reproducible build or the resolved native dependency graph. The API metadata snapshot is retained locally in .local/audits/isar-release-identity.json; the DLL was not downloaded or loaded for this check.

Actions run23458092140 reports Isar release, push event, head_sha4c2cd02d4e5c17b7edca89d141d1729ddc1698ff and success. Windows x64 job68252713154 likewise reports success. The pinned [release workflow](https://raw.githubusercontent.com/isar-community/isar-community/4c2cd02d4e5c17b7edca89d141d1729ddc1698ff/.github/workflows/release.yaml) uploads the binary only with artifact retention1day. Its artifacts API currently reports0artifacts. The job logs endpoint returned403 with Must have admin rights to Repository; logs were not obtained, so no dependency inventory was inferred from them.

The pinned [Windows build script](https://raw.githubusercontent.com/isar-community/isar-community/4c2cd02d4e5c17b7edca89d141d1729ddc1698ff/tool/build_windows.sh) selects Rust1.88.0-x86_64-pc-windows-msvc and cargo build --target x86_64-pc-windows-msvc --release, without --locked. Combined with the source tree's missing Cargo.lock, a fresh resolution today would not establish the graph used by the published binary. No replacement native build, Rust installation or runtime/security tests were performed. T045 remains open for authoritative resolved native source/license coverage and the final bundled notices.

### UI localization resolution — T187, 2026-10-12

The current root resolution adds SDK flutter_localizations and hosted intl0.20.3 (locked package SHA-2561ca20c894b1717686a2319b8548763d812bc0aabdac580420a44c5178c57a867). The offline collector was actually rerun against all four current resolutions:90 hosted package versions and99 complete source texts. intl's installed LICENSE is included; SDK localizations use the existing full Flutter license. Current preview SHA-256 is1b3141188c273334ab09defe0ce933a8c2dde2c4072ff7abead11a44a44e0c0e. The earlier89/98 inventory is a historical checkpoint. Preview remains incomplete-native-chain/distributionReady=false; T045 and final distribution notices are still open. No previous rejected cleanup operation was rerun.
### New native candidate preparation — T232/T233, 2026-10-12

The earlier statement that no Rust installation/resolution occurred describes that historical checkpoint. A new isolated standalone Rust/Cargo1.88.0 and libclang18.1.1 toolchain has now been prepared from hash-checked archives; cargo lock generation/Windows-target metadata succeeded for67packages. The checked recipe and exact Cargo.lock are in native/isar-3.3.2; the design is specs/001-service-foundation/contracts/native-artifact.md. No candidate DLL has been compiled, qualified or selected. The current cached DLL and preview remain unchanged/distributionReady=false. The new graph belongs to a future new artifact and does not establish the old release's graph. T045/T207/T233 remain open pending native license/source collection, build, qualification and actual bundle verification. No denied upstream log access or cleanup operation was retried.

### Activated source-built native artifact and actual bundles — 2026-10-13

The current local-build DLL is newly compiled from the checked Isar/MDBX inputs, exact Cargo.lock, verified vendor checksums and recorded toolchain using the offline frozen build. Its SHA-256 is `17fb5deaba528a0627cf5caf4526c6dbce91629e8c4805f05b3b2ffefac7e520`; the original artifact manifest SHA-256 is `da422f01b3a25f69aa1a2f026a004e21e51d22f1210b548fbde2451b06986061`. This establishes the graph of this new artifact. The old downloaded DLL's graph remains unestablished and is not attributed to the new lockfile.

The artifact retains `native-build.json`, `native-dependencies.json`, `native-notice-inventory.json`, `rust-license-material.json`, `supplemental-licenses.json`, `native-source-receipt.json`, `mdbx-patch.json`, `Cargo.lock`, `recipe.json`, `source-reproduction.json` and `REPRODUCE.txt`. `NATIVE_SOURCES.zip` retains the corresponding Isar/MDBX and vendored sources needed by the checked reproduction recipe. `THIRD_PARTY_NATIVE_NOTICES.txt` preserves the resolved native texts, including the separate Apache/MPL components; Dart, SDK/engine and OFL materials are included by the bound offline collector. Source and notice inventories are hash-bound to the compiled artifact, not inferred from the old release or inaccessible upstream job logs.

Full current-source qualification completed all14 phases: ABI, exact root format/analyze/tests, all three package analyze/tests, normal candidate Debug/Release,13 available native/UI phases and runtime diagnostics. The compatibility receipt is `.local/native-qualification-4656889443f3494b9f4d59547f10969a/compatibility-receipt.json`, SHA-256 `3ab4ee02c44d74c4212dc0ef0a6c32ab23c3442c2358ff23bdc9c5df0f601d6f`, bound to source snapshot `60c9ba37267657a16bb8978a3a31de664f063e3e9bdcc26eabce54334c953d94`. Both original normal output trees were independently verified restored. A fresh completed independent review found no defects in the native-build-only scope and independently verified the current receipt and retained bundles; its faithful record is `.local/audits/t233-compatibility-clean-review-3ac89444b2e248da905a06019bbc5eee.json`.

Explicit activation then succeeded through `tools/activate-native-isar.ps1`. Subsequent ordinary `tools/run-foundation.ps1 -Configuration Debug -BuildOnly` and Release builds both succeeded without candidate context or acceptance flags. Actual `build/windows/x64/runner/{Debug,Release}/foundation.manifest.json` records have `testOnly=false`; all three binary hashes were verified and both DLLs equal the new artifact. Each bundle includes `notices/THIRD_PARTY_NOTICES.txt`, `notices/third-party-notices.json` and the full copied native material:199 notice files with identical tree SHA-256 `3541077fc18ceacbb0f00ef4db28c5092a1e3138fd433723ad30b80c752de74d`. The copied original artifact manifest remains assembly provenance; reviewed qualification and the active pointer are separate records.

Actual post-activation acceptance rejected an invalid pointer state, mismatched qualification hash and missing pointer after the established marker. Each case was refused by both the provider and normal build preflight. The exact original pointer/marker and both normal bundle trees were verified preserved, and qualified selection worked again after restoration. Evidence: `.local/native-activation-acceptance-e6d3fcef3aae431f8873c5afd0a49efa/result.json` and `.local/audits/t233-qualified-normal-acceptance.txt`; the executed local acceptance script is `.local/audits/t233-qualified-normal-acceptance.ps1`. Product distribution readiness/fullAcceptance remain false; manual, other-user, reboot, physical/offline, CI and exact deferred operations are not established by these native-build proofs. Nothing was published and no denied operation was retried.
