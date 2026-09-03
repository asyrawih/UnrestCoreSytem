# Third-party notices

UnrestCoreSystem is MIT licensed (see `LICENSE`). It bundles one third-party
component, under a different licence, in the builds noted below.

## Scythe

* Upstream: <https://github.com/synttx/scythe>, published as `synttx/scythe` on Wally.
* Version bundled: **1.2.2**, taken verbatim from `Packages/_Index/synttx_scythe@1.2.2/scythe/src/scythe.luau`.
* Licence: **MPL-2.0**. Full text in `vendor/LICENSE-Scythe-MPL-2.0`.

MPL-2.0 is a file-level copyleft: the file stays MPL-2.0 and any modification to
**that file** must be published under the same licence, while the rest of this
project remains MIT. `vendor/Scythe.luau` is unmodified, and must stay that way —
if it ever needs a patch, the patch is MPL-2.0 and belongs upstream.

**Where it ships.** Only in the Creator Store model, built with
`model.project.json`, which mounts `vendor/Scythe.luau` as `Unrest.Scythe`. A
Rojo or Wally install does not use the vendored copy at all: it resolves the one
Wally fetched. `src/shared/Util/Scope.luau` is what decides, and the reason it
searches instead of naming a path is that there must only ever be ONE copy of
Scythe in a place — two copies mint scope handles that mean different things.

**Keeping it in step.** `vendor/Scythe.luau` is a copy, so it can drift from the
version `wally.toml` pins. When the pin moves, re-copy the file and update the
version above.
