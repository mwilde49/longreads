# SQANTI3 HPC Module — Development Status Report
**Date:** 2026-03-28
**Author:** Mike Wilde (mwild49)
**Project:** SQANTI3 pipeline module for TJP HPC ecosystem
**Repo:** `/mnt/c/users/mwild/firebase2/longreads` (submodule → `containers/sqanti3/` in parent HPC repo)

---

## Summary of Work Since Last Report (2026-03-27)

The pipeline was fully implemented and verified end-to-end in a single session. All SLURM templates, the orchestrator, pre-flight validation, config template, and documentation were written from scratch. A local smoke test confirmed all four pipeline stages produce correct output.

---

## Phase Status

| Phase | Status | Notes |
|-------|--------|-------|
| Architecture design | Complete | Documented in CLAUDE.md |
| Environment setup | Complete | Apptainer SIF pulled (9.5 GB) |
| Test data acquisition | Complete | chr22 UHR example data |
| Upstream prep analysis | In progress | EPI2ME workflow reviewed; requester commands not yet received |
| Local smoke test | **Complete ✓** | All 8/8 outputs verified |
| SLURM templates | **Complete ✓** | Orchestrator + 4 per-stage templates |
| Config template | **Complete ✓** | `hpc/templates/sqanti3/config.yaml` |
| Pre-flight validation script | **Complete ✓** | File existence + chromosome name check |
| HPC integration | **Complete ✓** | Registered in common.sh, validate.sh, tjp-launch, tjp-test |
| Documentation | **Complete ✓** | `docs/SQANTI3_HPC_GUIDE.md` |
| HPC deployment | Not started | Pending SIF transfer to Juno, submodule registration |
| Real data test | Not started | Pending requester's data |

---

## What Was Built (2026-03-28)

### `longreads/` repo

```
longreads/
├── run_sqanti3_test.sh                  ← Local end-to-end smoke test (verified)
├── scripts/
│   └── sqanti3_preflight.sh            ← Pre-flight validation
├── slurm_templates/
│   ├── sqanti3_qc_slurm_template.sh    ← Stage 1a: long-read QC
│   ├── sqanti3_refqc_slurm_template.sh ← Stage 1b: reference QC (parallel to 1a)
│   ├── sqanti3_filter_slurm_template.sh← Stage 2: filter
│   └── sqanti3_rescue_slurm_template.sh← Stage 3: rescue + stage-out rsync
├── docs/
│   └── SQANTI3_HPC_GUIDE.md           ← User documentation
└── SQANTI3/
    └── sqanti3_v5.5.4.sif             ← Apptainer SIF (9.5 GB, verified)
```

### `hpc/` parent repo

| File | Change |
|------|--------|
| `slurm_templates/sqanti3_slurm_template.sh` | Orchestrator: pre-flight → resource sizing → submits 4 SLURM sub-jobs with `--dependency` chaining |
| `templates/sqanti3/config.yaml` | User-facing config template |
| `bin/lib/common.sh` | `sqanti3` added to all pipeline registries |
| `bin/lib/validate.sh` | `_validate_sqanti3()` validator |
| `bin/tjp-launch` | sqanti3 dispatch case (outdir passthrough, no fastq_dir) |
| `bin/tjp-test` | sqanti3 smoke test code path (uses GTF/FASTA test data, no FASTQs) |

---

## Pipeline Architecture (Implemented)

```
tjp-launch sqanti3 --config config.yaml
    │
    └── sbatch sqanti3_slurm_template.sh   [1 CPU, 4G, 30 min]
            │
            ├── pre-flight validation (chromosome names, file existence)
            ├── resource sizing from GTF transcript count
            ├── generate per-stage SQANTI3 YAML configs
            │
            ├── sbatch sqanti3_qc_slurm_template.sh       [Stage 1a, 8–32 CPUs, 16–256G]
            ├── sbatch sqanti3_refqc_slurm_template.sh    [Stage 1b, 8 CPUs, 16G]  ← parallel
            ├── sbatch sqanti3_filter_slurm_template.sh   [Stage 2,  4 CPUs, 8G,  after 1a]
            └── sbatch sqanti3_rescue_slurm_template.sh   [Stage 3,  8 CPUs, 16G, after 2 + 1b]
                    └── rsync outputs → run_dir/outputs/
```

**Dynamic resource sizing (Stage 1a):**

| Transcripts | CPUs | RAM | Chunks |
|---|---|---|---|
| <50K | 8 | 16 GB | 4 |
| 50K–200K | 16 | 32 GB | 8 |
| 200K–1M | 32 | 128 GB | 14 |
| >1M | 32 | 256 GB | 20 |

---

## Smoke Test Results (2026-03-28)

Ran on chr22 UHR example data (3,925 isoforms) via Apptainer SIF on WSL2:

| Check | Result |
|-------|--------|
| QC classification | ✓ |
| QC corrected GTF | ✓ |
| QC corrected FASTA | ✓ |
| Ref QC classification | ✓ |
| Filter classification | ✓ |
| Filtered GTF | ✓ |
| Rescued GTF | ✓ |
| Rescued FASTA | ✓ |

**Total: 8/8 outputs verified.** Pipeline completed in ~4 min on WSL2 laptop hardware.

**WSL2-specific workarounds (not relevant on HPC):**
- STAR requires Linux filesystem for FIFO temp files → test outputs redirected to `/tmp/sqanti3_test/`
- FOFN short-reads file used relative paths → test generates absolute-path FOFN on the fly

---

## Key Technical Decisions Made

1. **Container invocation:** `conda run --no-capture-output -n sqanti3 sqanti3 <stage> -c <config>` — bare `sqanti3` call fails because the sqanti3 conda env must be active for dependencies
2. **SLURM DAG pattern:** Orchestrator is a lightweight SLURM job that submits sub-jobs via `sbatch --parsable`, capturing job IDs for `--dependency=afterok:` chaining
3. **Per-stage YAML generation:** Orchestrator generates SQANTI3-format YAML configs from the flat user config at runtime, stored in `run_dir/stage_configs/`
4. **filter_default.json path:** Absolute path inside container: `/opt2/sqanti3/5.5.4/SQANTI3-5.5.4/src/utilities/filter/filter_default.json`
5. **Ref classification rename:** Stage 1b copies `*_classification.txt` → `ref_classification.txt` for canonical rescue input

---

## Open Questions

1. **Organism scope** — human confirmed (hDRG); mouse support needed?
2. **Upstream coupling** — will the IsoSeq/ONT collapse pipeline live in the same HPC ecosystem? SQANTI3 config currently assumes user provides collapsed GTF manually.
3. **SJ.out.tab auto-discovery** — should the pipeline auto-locate `SJ.out.tab` from a prior BulkRNASeq module run on the same sample set?
4. **Shared container path on Juno** — confirm `/groups/tprice/containers/` vs `/groups/tprice/pipelines/containers/sqanti3/` with sysadmin
5. **Requester preprocessing commands** — full EPI2ME + featureCounts + STAR command set not yet received (message was cut off in handoff)

---

## Immediate Next Steps

1. **Transfer SIF to Juno** — `rsync sqanti3_v5.5.4.sif <user>@juno:/groups/tprice/pipelines/containers/sqanti3/`
2. **Register submodule in HPC parent repo** — `git submodule add <longreads_remote> containers/sqanti3`
3. **Run `tjp-test sqanti3` on Juno dev partition** — first real SLURM smoke test
4. **Receive requester's real data** — run against actual ONT hDRG dataset
5. **Resolve open questions 1–5 above** before wider release

---

## Previous Report

[2026-03-27 Dev Status](./2026-03-27_dev_status.md) — architecture design and environment setup phase
