# Compressed GuideLLM results

The detailed GuideLLM `benchmarks.json` files are excluded from Git because
they are very large. Compressed Zstandard copies are retained alongside the
CSV summaries.

Restore a single-file archive with:

```bash
zstd -d benchmarks.json.zst -o benchmarks.json
```

The `2pdp8-1ddp4-guidellm` archive exceeds GitHub's per-file size limit even
after compression, so it is stored in parts. Restore it with:

```bash
cat benchmarks.json.zst.part-* | zstd -d -o benchmarks.json
```
