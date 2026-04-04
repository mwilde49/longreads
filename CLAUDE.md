# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository will contain a **SQANTI3 pipeline module** designed to plug into the TJP HPC ecosystem at https://github.com/mwilde49/hpc. SQANTI3 is a long-read transcriptome QC and curation tool (QC → Filter → Rescue stages) used after transcript collapse from PacBio IsoSeq or Oxford Nanopore data.

## Parent Ecosystem Context

Before making architectural decisions, read the HPC repo thoroughly — particularly `PIPELINE_DESIGN_REVIEW.md` and `TJP_HPC_COMPLETE_GUIDE.md`. Key ecosystem constraints:

- **Runtime**: SLURM + Apptainer (Singularity) on Juno HPC
- **Config**: YAML files passed at job submission
- **Shared paths**: `/groups/tprice/pipelines` (deployment), `/work/<username>` (output), `/scratch/juno/<username>` (temp)
- **Tools**: `tjp-launch`, `tjp-test`, `tjp-test-validate` are the user-facing CLI
- **Apptainer requires real filesystem paths** — no symlinks in bind mounts

Two pipeline patterns exist in the ecosystem — **inline** (simple, code in-repo) and **submoduled** (external git submodule + container). SQANTI3 follows the **submoduled pattern**.

## Current Repo State (as of 2026-03-27)

```
longreads/
├── CLAUDE.md                            # This file
├── run_sqanti3_test.sh                  # Local smoke test runner (Apptainer)
├── reports/
│   └── 2026-03-27_dev_status.md        # Timestamped development status report
├── Nanopore_LRS_femalehDRG/            # Upstream prep pipeline reference (private repo clone)
│   └── README.md                        # EPI2ME wf-transcriptomes + featureCounts workflow
└── SQANTI3/                             # ConesaLab/SQANTI3 v5.5.4 (local testing only, not submodule yet)
    ├── data/                            # chr22 UHR example inputs (GTF, FASTA, short reads, CAGE, polyA)
    ├── example/config_files/            # Example YAML configs — hardcoded paths fixed
    └── sqanti3_v5.5.4.sif              # Apptainer SIF (built from docker://anaconesalab/sqanti3:v5.5.4)
```

**Not yet created** (planned):
```
containers/sqanti3/                       # git submodule → ConesaLab/SQANTI3 @ v5.5.4
slurm_templates/
  sqanti3_slurm_template.sh              # Orchestrator: chains stages via SLURM --dependency
  sqanti3_qc_slurm_template.sh           # Stage 1a: long-read QC  (32–128 GB, 16–32 CPUs)
  sqanti3_refqc_slurm_template.sh        # Stage 1b: reference QC  (runs parallel to 1a)
  sqanti3_filter_slurm_template.sh       # Stage 2: filter         (8 GB, 4 CPUs)
  sqanti3_rescue_slurm_template.sh       # Stage 3: rescue         (16 GB, 8 CPUs)
templates/
  sqanti3_config.yaml                    # User-facing config template
test_data/sqanti3/                       # Minimal GTF + genome slice for dev partition smoke test
docs/
  SQANTI3_HPC_GUIDE.md
```

## SQANTI3 Architecture

### Three stages with different resource envelopes

| Stage | Script | RAM | CPUs | Notes |
|-------|--------|-----|------|-------|
| QC (long-read) | `sqanti3_qc.py` | 32–256 GB | 16–32 | Scales with `-n chunks`; memory ≈ base × chunks |
| QC (reference) | `sqanti3_qc.py` | 16 GB | 8 | Runs in parallel with long-read QC; required input for rescue |
| Filter | `sqanti3_filter.py rules\|ml` | 8 GB | 4 | Fast; rules mode is default |
| Rescue | `sqanti3_rescue.py` | 16 GB | 8 | Requires ref QC output (`ref_classification.txt`) |

**Stages 1a and 1b are independent and must run as separate parallel SLURM jobs.** Stage 2 depends on 1a. Stage 3 depends on both 2 and 1b. The orchestrator handles `--dependency=afterok:` chaining.

### Dynamic resource allocation

Compute recommended chunks from input GTF line count before job submission:

| Transcripts | RAM | CPUs | Chunks |
|---|---|---|---|
| <50K | 16 GB | 8 | 4 |
| 50K–200K | 32 GB | 16 | 8 |
| 200K–1M | 128 GB | 32 | 14 |
| >1M | 256 GB | 32 | 20 |

### Container

```bash
# Build once into shared container storage
apptainer build /groups/tprice/containers/sqanti3_v5.5.4.sif \
  docker://anaconesalab/sqanti3:v5.5.4
```

Use the Docker → SIF path (not conda) to avoid conda environment fragility across SQANTI3 version bumps.

## Key Design Decisions

- **Pre-compute short-read junctions externally**: accept `SJ.out.tab` files via `coverage:` config key, not raw FASTQs. Running STAR inside SQANTI3 requires ~32 GB for genome indexing and is wasteful on HPC.
- **`--force_id_ignore` always on**: users may bring Nanopore data (FLAIR, StringTie2, Bambu) where transcript IDs are not in PacBio `PB.X.Y` format.
- **`--report skip` by default**: the R-based HTML report (150+ plots) is slow and memory-intensive; add a `generate_report: false` config toggle.
- **Filter mode default: `rules`**: deterministic and auditable; ML mode requires careful TP/TN set curation and is opt-in.
- **Rescue mode default: `automatic`**: safer and faster; `full` mode is opt-in.
- **Pre-flight validation** must run before any SLURM jobs: check file existence, verify chromosome name consistency across isoforms GTF / refGTF / refFasta (the #1 failure mode), and auto-compute chunks if not set by user.

## Critical SQANTI3 Pitfalls

- Chromosome name mismatch (e.g., `chr1` vs `1`) silently produces wrong results — validate before running.
- Memory scales with both transcript count AND chunk count — do not set chunks too high on small datasets.
- ML filter reuses `.RData` model if re-run in same directory — delete `randomforest.RData` to force retraining.
- `sqanti3_rescue.py` requires a **pre-computed SQANTI3 QC run on the reference GTF itself** (not just the long-read data) — this is the reference QC stage (1b).
- v5.0+ output is backward-incompatible with v4.x tools — pin the container version.
- TransDecoder2 (v5.5+) increases runtime; use `skip_orf: true` if ORF prediction is not needed.

## Config Template Keys (reference)

```yaml
# Required
isoforms:   /path/to/collapsed.gtf
refGTF:     /path/to/gencode.gtf
refFasta:   /path/to/genome.fa

# Strongly recommended
coverage:   /path/to/SJ.out.tab   # Pre-computed STAR short-read junctions
fl_count:   /path/to/abundance.tsv

# Optional orthogonal evidence
CAGE_peak:        ""   # blank = use built-in human/mouse data
polyA_motif_list: ""   # blank = use built-in
polyA_peak:       ""

# Technology
force_id_ignore: true   # true for Nanopore; false for PacBio IsoSeq

# Resources (auto-computed from GTF size if blank)
cpus:   16
chunks: 8

# Feature toggles
skip_report:        true
skip_orf:           false
filter_mode:        rules    # "rules" or "ml"
filter_mono_exonic: false
filter_rules_json:  ""
rescue_mode:        automatic  # "automatic" or "full"

# Output
sample: my_sample
outdir: /work/${USER}/sqanti3/${sample}
```
