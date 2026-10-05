"""Generate deterministic WiX v4+ components for the complete desktop bundle."""
import argparse
import hashlib
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
from release_manifest import ROOT, version

NS = "http://wixtoolset.org/schemas/v4/wxs"
ET.register_namespace("", NS)


def node(parent, tag, **attrs):
    return ET.SubElement(parent, "{" + NS + "}" + tag, attrs)


def build(bundle, output, test_version=None):
    release = test_version or version()
    root = ET.Element("{" + NS + "}Wix")
    package = node(root, "Package", Name="ServerDeck", Manufacturer="unng-lab", Version=release.replace("+", "."), UpgradeCode="B51674F3-B330-4F64-87F4-202ED63E94AB", Scope="perUser", InstallerVersion="500", Compressed="yes")
    node(package, "MajorUpgrade", DowngradeErrorMessage="A newer ServerDeck is already installed.", AllowSameVersionUpgrades="yes")
    node(package, "MediaTemplate", EmbedCab="yes", CompressionLevel="high")
    node(package, "Icon", Id="AppIcon", SourceFile=str(ROOT / "windows/runner/resources/app_icon.ico"))
    node(package, "Property", Id="ARPPRODUCTICON", Value="AppIcon")
    local = node(package, "StandardDirectory", Id="LocalAppDataFolder")
    programs = node(local, "Directory", Id="UserPrograms", Name="Programs")
    install = node(programs, "Directory", Id="INSTALLFOLDER", Name="ServerDeck")
    feature = node(package, "Feature", Id="Complete", Title="ServerDeck", Level="1")
    directories = {Path("."): install}
    for file in sorted(bundle.rglob("*")):
        if not file.is_file() or file.suffix in {".pdb", ".exp", ".lib"}:
            continue
        relative = file.relative_to(bundle)
        parent = Path(".")
        for part in relative.parts[:-1]:
            next_parent = parent / part
            if next_parent not in directories:
                key = "D" + hashlib.sha256(next_parent.as_posix().encode()).hexdigest()[:24]
                directories[next_parent] = node(directories[parent], "Directory", Id=key, Name=part)
            parent = next_parent
        key = hashlib.sha256(relative.as_posix().encode()).hexdigest()[:24]
        component = node(directories[parent], "Component", Id="C" + key, Guid=str(uuid.uuid5(uuid.UUID("B51674F3-B330-4F64-87F4-202ED63E94AB"), relative.as_posix().lower())))
        node(component, "File", Id="F" + key, Source=str(file.resolve()))
        node(component, "RegistryValue", Root="HKCU", Key="Software\\unng-lab\\ServerDeck\\Components", Name=key, Type="integer", Value="1", KeyPath="yes")
        node(feature, "ComponentRef", Id="C" + key)
    menu = node(package, "StandardDirectory", Id="ProgramMenuFolder")
    shortcut = node(menu, "Component", Id="MenuShortcut", Guid="*")
    node(shortcut, "Shortcut", Id="LaunchServerDeck", Name="ServerDeck", Target="[INSTALLFOLDER]serverdeck.exe", WorkingDirectory="INSTALLFOLDER", Icon="AppIcon")
    node(shortcut, "RegistryValue", Root="HKCU", Key="Software\\unng-lab\\ServerDeck", Name="MenuShortcut", Type="integer", Value="1", KeyPath="yes")
    node(feature, "ComponentRef", Id="MenuShortcut")
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root)
    ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--test-version", choices=["0.0.0+0"], help="Synthetic older installer for isolated upgrade tests only")
    args = parser.parse_args()
    build(args.bundle, args.output, args.test_version)
