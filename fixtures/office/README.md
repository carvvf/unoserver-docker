# Office Fixtures (Permissive License)

This directory contains small, deterministic fixtures for document conversion
tests across Microsoft Office and LibreOffice/OpenDocument formats.

## License

All source fixtures are from `file-format-commons`, which is licensed under
CC0 1.0 (public domain dedication):

- Source repository: https://github.com/alexschiller/file-format-commons
- Source license: https://github.com/alexschiller/file-format-commons/blob/master/LICENSE

`sample.odp` is generated from the CC0 `sample.pptx` fixture and is therefore
treated as CC0-compatible test data in this repository.

## Included Formats

| File | Family | Format |
|---|---|---|
| `sample.doc` | Microsoft Office legacy | Word binary (`.doc`) |
| `sample.xls` | Microsoft Office legacy | Excel binary (`.xls`) |
| `sample.ppt` | Microsoft Office legacy | PowerPoint binary (`.ppt`) |
| `sample.docx` | Microsoft Office OOXML | Word OOXML (`.docx`) |
| `sample.xlsx` | Microsoft Office OOXML | Excel OOXML (`.xlsx`) |
| `sample.pptx` | Microsoft Office OOXML | PowerPoint OOXML (`.pptx`) |
| `sample.odt` | OpenDocument | Text (`.odt`) |
| `sample.ods` | OpenDocument | Spreadsheet (`.ods`) |
| `sample.odp` | OpenDocument | Presentation (`.odp`) |

## Provenance

Downloaded from `file-format-commons`:

- `sample.doc` <- `files/ffc_97_2000_xp.doc`
- `sample.docx` <- `files/ffc.docx`
- `sample.xls` <- `files/ffc.xls`
- `sample.xlsx` <- `files/ffc.xlsx`
- `sample.ppt` <- `files/ffc.ppt`
- `sample.pptx` <- `files/ffc.pptx`
- `sample.odt` <- `files/ffc.odt`
- `sample.ods` <- `files/ffc.ods`

Generated locally:

- `sample.odp` <- converted from `sample.pptx` using LibreOffice headless:

```bash
docker run --rm \
  -v "$PWD/fixtures/office:/data" \
  --entrypoint soffice \
  unoserver-docker:local \
  --headless --convert-to odp --outdir /data /data/sample.pptx
```

## Integrity

Checksums are recorded in `SHA256SUMS`.

Verify with:

```bash
cd fixtures/office
sha256sum -c SHA256SUMS
```
