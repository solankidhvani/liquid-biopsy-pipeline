# Liquid Biopsy / RNA-seq Mini Pipeline

An end-to-end, reproducible pipeline for processing RNA-seq / liquid biopsy small-RNA data:
**QC & adapter trimming (fastp) → pseudo-alignment (Salmon) → differential expression & visualization (DESeq2, ggplot2 in R)**.

Built with **Nextflow** for workflow standardization, **Docker** for reproducibility, and **GitHub Actions** for continuous testing.

## Why this pipeline

Liquid biopsy and small-RNA workflows require careful adapter trimming (short reads risk adapter read-through) and lightweight quantification suited to low-input, non-invasive blood/plasma samples. This pipeline mirrors a production-style setup: modular steps, logging, CI validation, and containerization — not a one-off analysis script.

## Quick start — zero local setup

Click **Code → Codespaces → Create codespace on main** on this repo. Everything (fastp, Salmon, Nextflow, R/DESeq2) installs automatically via `.devcontainer/devcontainer.json`. No conda, no local Python/R setup on your machine.

Once the Codespace loads:

```bash
conda activate pipeline
nextflow run main.nf -profile standard
```

## Alternative: Docker (also zero local installs beyond Docker itself)

```bash
docker build -t liquid-biopsy-pipeline .
docker run -v $(pwd)/data:/pipeline/data liquid-biopsy-pipeline
```

## Pipeline steps

| Step | Tool | Purpose |
|------|------|---------|
| 1. QC/Trim | `fastp` | Adapter trimming, poly-G trimming, length filtering (15bp+) |
| 2. Index | `salmon index` | Build transcriptome index |
| 3. Quantify | `salmon quant` | Pseudo-alignment + transcript quantification |
| 4. Differential Expression | `DESeq2` (R) | Identify significantly up/down-regulated genes |
| 5. Visualization | `ggplot2`, `pheatmap` | Volcano plot, PCA plot, expression heatmap |

## Repo structure

```
.
├── .devcontainer/devcontainer.json   # Codespaces auto-setup
├── .github/workflows/ci.yml          # CI smoke test on every push
├── main.nf                           # Nextflow pipeline entrypoint
├── modules/
│   ├── fastp.nf
│   └── salmon.nf
├── nextflow.config
├── r/differential_expression.R
├── Dockerfile
└── data/
    ├── raw/           # input fastq files (not committed)
    ├── results/       # pipeline outputs (not committed)
    └── samples.csv    # sample_id, condition mapping
```

## Data

This pipeline is data-agnostic. Point `params.reads` in `main.nf` at any paired-end FASTQ files — public liquid biopsy / plasma RNA-seq data can be sourced from [NCBI GEO](https://www.ncbi.nlm.nih.gov/geo/) or [SRA](https://www.ncbi.nlm.nih.gov/sra).

## Results

_Volcano plot, PCA plot, and heatmap will be generated in `data/results/` and embedded here once run on real sample data._

## License

MIT
