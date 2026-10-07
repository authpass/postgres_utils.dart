## 2.0.0

- Require `postgres` ^3.5.0; remove the `postgres/src` implementation import.
- Remove `CustomTypeBind`; `CustomBind` no longer takes a `type`.
- Replace the discontinued `pedantic` lint set with `lints` recommended.
- Add a dockerized smoke test (`test/smoke_test.dart`).

## 2.0.0-rc.5

- Migrate to `postgres` v3.
- Add `concatColumns` to `OnConflictActionDoUpdate` for allowing incremental updates in `upset`.

## 1.0.0

- Initial version.
