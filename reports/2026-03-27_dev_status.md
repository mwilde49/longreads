# SQANTI3 HPC Module — Development Status Report
**Date:** 2026-03-27
**Author:** Mike Wilde (mwilde49)
**Project:** SQANTI3 pipeline module for TJP HPC ecosystem
**Repo:** `/mnt/c/users/mwild/firebase2/longreads` (local dev), target deployment: `github.com/mwilde49/hpc` submoduled pattern

---

## Executive Summary

Architecture and environment setup are complete. Local smoke-testing infrastructure is in place using the official SQANTI3 example dataset (chr22 UHR). A container image pull is in progress. No HPC SLURM templates, config templates, or production pipeline scripts have been written yet.

---

## Phase Status

| Phase | Status | Notes |
|-------|--------|-------|
| Architecture design | Complete | Documented in CLAUDE.md |
| Environment setup | Complete | Apptainer available; SIF pull in progress |
| Test data acquisition | Complete | Official SQANTI3 chr22 example data |
| Upstream prep analysis | In progress | `Nanopore_LRS_femalehDRG` repo reviewed; real data pending from requester |
| Local smoke test | Pending | Blocked on SIF download completion |
| SLURM templates | Not started | — |
| Config template | Not started | — |
| Pre-flight validation script | Not started | — |
| HPC deployment | Not started | — |
| Docs (SQANTI3_HPC_GUIDE.md) | Not started | — |

---

## What Exists in This Repo

```
longreads/
├── CLAUDE.md                          # Architecture reference (complete)
├── run_sqanti3_test.sh                # Local smoke test runner via Apptainer
├── reports/
│   └── 2026-03-27_dev_status.md      # This file
├── Nanopore_LRS_femalehDRG/           # Upstream prep pipeline reference (private repo clone)
│   └── README.md                      # EPI2ME wf-transcriptomes workflow notes
└── SQANTI3/                           # ConesaLab/SQANTI3 v5.5.4 (cloned for local testing only)
    ├── data/                          # Example inputs: UHR chr22 GTF, FASTA, short reads, CAGE, polyA
    ├── example/config_files/          # Example YAML configs (QC, filter, rescue) — paths fixed
    └── sqanti3_v5.5.4.sif            # Apptainer SIF (download in progress ~3-4 GB)
```

**Not yet created** (per planned layout in CLAUDE.md):
- `slurm_templates/` — orchestrator + per-stage SLURM scripts
- `templates/sqanti3_config.yaml` — user-facing config template
- `test_data/sqanti3/` — minimal in-repo smoke test data (separate from SQANTI3 repo clone)
- `docs/SQANTI3_HPC_GUIDE.md`
- `containers/sqanti3/` — git submodule to ConesaLab/SQANTI3 @ v5.5.4

---

## Upstream Prep Pipeline (Context from Requester)

**Source:** `github.com/asta-a-t/Nanopore_LRS_femalehDRG` (private)
**Dataset:** 8 ONT cDNA samples (female hDRG), GRCh38/GENCODE v47, 2 PromethION flow cells (barcodes 9–16)

The upstream workflow that produces SQANTI3 inputs:
1. **EPI2ME `wf-transcriptomes`** (Nextflow + Docker) → `str_merged.annotated.gtf` + aligned BAM
2. **`featureCounts`** → transcript-level counts TSV
3. **Short-read FASTQ cleaning** (awk; removes corrupt reads) → cleaned FASTQs for STAR → `SJ.out.tab`

**Note:** Requester provided preprocessing details that were partially cut off in handoff — follow up needed to capture the full preprocessing command set.

**Definitive test data:** To be provided by requester (not yet received).

---

## Key Architecture Decisions (Locked)

- **Pattern:** Submoduled (external git submodule + Apptainer SIF)
- **Container:** `docker://anaconesalab/sqanti3:v5.5.4` → SIF at `/groups/tprice/containers/sqanti3_v5.5.4.sif`
- **Stage DAG:** QC-longread (1a) ‖ QC-reference (1b) → Filter (2) → Rescue (3), SLURM `--dependency=afterok:`
- **Short-read junctions:** Pre-computed `SJ.out.tab` passed via `coverage:` key; STAR not run inside SQANTI3
- **`--force_id_ignore`:** Always on (Nanopore data, non-PB IDs)
- **`--report skip`:** Default; toggle via `generate_report: false`
- **Filter mode:** `rules` default, `ml` opt-in
- **Rescue mode:** `automatic` default, `full` opt-in
- **Dynamic resources:** Auto-computed from GTF line count pre-submission

---

## Open Questions (Unresolved)

1. Organism scope — human only confirmed (hDRG); mouse support needed?
2. Upstream coupling — will IsoSeq/ONT collapse pipeline live in the same HPC ecosystem?
3. STAR `SJ.out.tab` auto-discovery — should it pull from BulkRNASeq module output automatically?
4. Shared container storage path on Juno — `/groups/tprice/containers/`? Confirm with sysadmin.
5. Requester's preprocessing steps — full command set not yet received (message cut off).

---

## Immediate Next Steps

1. Confirm SIF download complete → run `./run_sqanti3_test.sh` → validate QC → Filter → Rescue on chr22 data
2. Receive full preprocessing commands from requester
3. Receive definitive test data from requester
4. Begin writing SLURM templates (start with orchestrator, then per-stage)
5. Write pre-flight validation script (chromosome name check, GTF line count → resource sizing)
6. Write user-facing `templates/sqanti3_config.yaml`
