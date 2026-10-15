"""Keep test-only asset resolver metadata outside the release install directory."""
from pathlib import Path
from uuid import uuid4

root = Path.cwd().resolve()
build = (root / "build").resolve()
assert build.is_relative_to(root)
for platform in ("windows", "macos", "linux"):
    source = build / "native_assets" / platform / "native_assets.json"
    if not source.exists():
        continue
    assert source.resolve().is_relative_to(build)
    target = build / "test_native_asset_metadata" / f"{platform}-{uuid4().hex}.json"
    assert target.resolve().is_relative_to(build)
    target.parent.mkdir(parents=True, exist_ok=True)
    data = source.read_bytes()
    with target.open("xb") as output:
        output.write(data)
    assert target.read_bytes() == data
    source.unlink()  # One known metadata file; never delete libraries/directories.
    print(f"Archived {platform} test asset resolver metadata before release.")
