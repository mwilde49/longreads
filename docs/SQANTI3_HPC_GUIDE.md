# SQANTI3 HPC Guide

SQANTI3 is a long-read transcriptome QC and curation tool (v5.5.4) integrated into the TJP HPC ecosystem. It runs three stages — QC, Filter, and Rescue — using SLURM on the Juno cluster with an Apptainer container.

## Quick Start

```bash
# 1. Copy the config template to your project
cp /groups/tprice/pipelines/templates/sqanti3/config.yaml ~/my_project/sqanti3_config.yaml

# 2. Edit the config — fill in your file paths
vim ~/my_project/sqanti3_config.yaml

# 3. Launch
tjp-launch sqanti3 --config ~/my_project/sqanti3_config.yaml

# 4. Monitor
squeue -u $USER
```

## Pipeline Architecture

SQANTI3 runs as four parallel/chained SLURM jobs:

```
Stage 1a: QC (long-read)  ─┐
                             ├─► Stage 2: Filter ─► Stage 3: Rescue
Stage 1b: QC (reference)  ─┘
```

| Stage | Job Name | RAM | CPUs | Time limit |
|-------|----------|-----|------|-----------|
| 1a — Long-read QC | `sqanti3_qc_<sample>` | 16–256 GB* | 8–32* | 48h |
| 1b — Reference QC | `sqanti3_rfqc_<sample>` | 16 GB | 8 | 12h |
| 2 — Filter | `sqanti3_filter_<sample>` | 8 GB | 4 | 4h |
| 3 — Rescue | `sqanti3_rescue_<sample>` | 16 GB | 8 | 8h |

*Stage 1a resources are auto-computed from transcript count. Set `cpus: 0` and `chunks: 0` in config to enable auto-sizing.

### Resource auto-sizing (Stage 1a)

| Transcripts | CPUs | RAM | Chunks |
|---|---|---|---|
| <50K | 8 | 16 GB | 4 |
| 50K–200K | 16 | 32 GB | 8 |
| 200K–1M | 32 | 128 GB | 14 |
| >1M | 32 | 256 GB | 20 |

## Config Reference

```yaml
sample: "my_sample"

# Required
isoforms: /path/to/collapsed_isoforms.gtf  # From EPI2ME wf-transcriptomes, FLAIR, etc.
refGTF:   /path/to/gencode.v47.annotation.gtf
refFasta: /path/to/GRCh38.primary_assembly.genome.fa

# Strongly recommended
coverage: /path/to/SJ.out.tab   # Pre-computed STAR junction file
fl_count: /path/to/abundance.tsv

# Optional evidence (blank = use built-in human/mouse data)
CAGE_peak:        ""
polyA_motif_list: ""
polyA_peak:       ""

# Technology
force_id_ignore: true   # true for Nanopore; false for PacBio IsoSeq

# Resources (0 = auto-compute from GTF size)
cpus:   0
chunks: 0

# Toggles
skip_report: true        # Skip 150-plot HTML report (saves ~30 min)
skip_orf:    false       # Skip TransDecoder ORF prediction
filter_mode: rules       # "rules" (default) or "ml"
filter_mono_exonic: false
rescue_mode: automatic   # "automatic" (default) or "full"

# Output
outdir: /work/__USER__/sqanti3/my_sample
```

## Output Structure

```
outdir/
├── qc/
│   ├── <sample>_classification.txt     ← Main QC table
│   ├── <sample>_corrected.gtf          ← Corrected isoforms GTF
│   ├── <sample>_corrected.fasta        ← Corrected isoforms FASTA
│   ├── <sample>_corrected.faa          ← ORF predictions (if skip_orf: false)
│   └── <sample>_junctions.txt
├── refqc/
│   └── ref_classification.txt          ← Required by rescue stage
├── filter/
│   ├── <sample>_RulesFilter_result_classification.txt
│   ├── <sample>.filtered.gtf           ← Filtered transcriptome
│   └── <sample>.filtered.fasta
└── rescue/
    ├── <sample>_rescued.gtf            ← Final curated transcriptome
    └── <sample>_rescued.fasta
```

After all stages complete, outputs are archived to the run directory:
```
/work/$USER/pipelines/sqanti3/runs/<timestamp>/outputs/
```

## Upstream Data Preparation

SQANTI3 expects inputs from a prior collapse/quantification step:

### Short-read junctions (critical for QC quality)

SQANTI3 uses STAR junction files to validate splice sites. Compute these separately:

```bash
# Run STAR alignment (bulk RNA-seq short reads)
STAR --runMode alignReads \
     --genomeDir /path/to/star_index \
     --readFilesIn R1.fastq.gz R2.fastq.gz \
     --readFilesCommand zcat \
     --outSAMtype BAM SortedByCoordinate \
     --outFileNamePrefix ./star_output/

# The SJ.out.tab file contains splice junctions
# Point coverage: in config to the SJ.out.tab path
```

Do NOT use SQANTI3's internal STAR — it requires ~32 GB for genome indexing and is wasteful when short-read data is already available.

### From EPI2ME wf-transcriptomes (Oxford Nanopore)

```bash
# wf-transcriptomes outputs:
str_merged.annotated.gtf    → isoforms in config
# Run featureCounts for fl_count:
featureCounts -a refGTF -o counts.tsv -L aligned.bam
```

### Chromosome naming consistency

**This is the #1 failure mode.** Isoforms GTF, refGTF, and refFasta must all use the same chromosome naming convention (either `chr1` or `1`, not mixed).

The pre-flight check (`sqanti3_preflight.sh`) validates this before submitting any jobs.

## Critical Notes

- **ML filter mode** reuses `randomforest.RData` if it exists in the output dir. Delete it to force retraining.
- **Rescue requires Stage 1b** (reference QC). The `refClassif` path in the rescue config points to `outdir/refqc/ref_classification.txt`.
- **v5.0+ outputs are incompatible with v4.x tools** — pin the container version (`sqanti3_v5.5.4.sif`).
- **TransDecoder2** (v5.5+) increases runtime significantly. Set `skip_orf: true` if ORF predictions aren't needed.

## Smoke Test

```bash
# On HPC (submits to dev partition)
tjp-test sqanti3

# Locally (without SLURM, using Apptainer directly)
cd /groups/tprice/pipelines/containers/sqanti3
./run_sqanti3_test.sh
```

## Container

The pipeline uses the official `anaconesalab/sqanti3:v5.5.4` Docker image converted to Apptainer SIF:

```bash
# Build once into shared container storage
apptainer pull /groups/tprice/pipelines/containers/sqanti3/sqanti3_v5.5.4.sif \
    docker://anaconesalab/sqanti3:v5.5.4
```

The SIF is expected at: `$PROJECT_ROOT/containers/sqanti3/sqanti3_v5.5.4.sif`
