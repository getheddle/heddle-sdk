# Diagram sources

`.drawio` files in this directory are the source of truth for SDK diagrams.
CI exports them to SVG and then generates dark-mode variants.

## How it works

- Source diagrams live in `docs/diagrams/*.drawio`.
- Exported SVGs live in `docs/images/`.
- CI runs `.github/workflows/build-diagrams.yml` when diagram sources change.
- The workflow uses `rlespinasse/drawio-export-action` with
  `embed-diagram: true`, so exported SVGs can be reopened in draw.io.
- `docs/diagrams/make_dark_variants.py` creates `<name>-dark.svg` variants.

## Referencing diagrams

Use both variants:

```markdown
![Caption](images/<name>.svg#only-light)
![Caption](images/<name>-dark.svg#only-dark)
```

The CSS hooks are defined in `docs/stylesheets/theme-aware-images.css`.
