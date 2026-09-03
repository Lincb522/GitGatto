# Sources

GitGatto's language catalog follows the checked-in 833-language GitHub Linguist snapshot. It bundles 699 dedicated SVG marks directly from pinned GitHub open-source repositories. The source SVG bytes are not redrawn, wrapped in generated badges, or converted into raster variants. The remaining 134 languages use the shared File Code icon from GitHub Octicons instead of generated monograms.

| Source | Direct SVGs | Revision |
|---|---:|---|
| [Simple Icons](https://github.com/simple-icons/simple-icons) | 158 | `863ac0130ed810dbbe5383bbf21c8bfc53339654` |
| [Devicon](https://github.com/devicons/devicon) | 30 | `7330accdbc47e2dc0c19789a48533c4a3c50fe58` |
| [File Icons](https://github.com/file-icons/atom) | 426 | `28520868aee66e576145a0b18aa2cde5444a897a` |
| [VSCode Icons](https://github.com/vscode-icons/vscode-icons) | 59 | `91fcfee6aaf933d15047d93e17fa89dbcbaeb546` |
| [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) | 26 | `dbdaf3dec361471986530da138053538dfce9d6a` |
| [Octicons](https://github.com/primer/octicons) | 1 shared fallback | `0e21a4c2d8449102f10e533d241f04797af0914c` |

`Sources/GitGatto/Resources/GitHubLanguageIcons.json` records the source repository, revision, upstream path, and SHA-256 digest for every bundled SVG. Restore or verify the resource directory with:

```bash
python3 scripts/import-github-language-icons.py
```

Pass `--source-root <directory>` to use local pinned checkouts instead of downloading raw files. Upstream marks and trademarks remain the property of their respective owners.
