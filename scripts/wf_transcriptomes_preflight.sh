#!/bin/bash
# Pre-flight validation for wf-transcriptomes.
# Called by wf_transcriptomes_slurm_template.sh before Nextflow runs.
# Usage: wf_transcriptomes_preflight.sh <config.yaml>

set -euo pipefail

CONFIG="${1:?ERROR: Config path not provided}"

errors=0

yaml_get() {
    grep -E "^${2}:" "$1" 2>/dev/null | head -1 \
        | sed "s/^${2}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^['\"]//; s/['\"]$//" || true
}

fail() { echo "  ERROR: $*" >&2; ((errors++)) || true; }
warn() { echo "  WARN:  $*"; }
ok()   { echo "  OK:    $*"; }

echo "====================================================================="
echo "  wf-transcriptomes — Pre-flight Validation"
echo "====================================================================="

SAMPLE=$(yaml_get "$CONFIG" "sample")
FASTQ_DIR=$(yaml_get "$CONFIG" "fastq_dir")
SAMPLE_SHEET=$(yaml_get "$CONFIG" "sample_sheet")
REF_GENOME=$(yaml_get "$CONFIG" "ref_genome")
REF_ANNOTATION=$(yaml_get "$CONFIG" "ref_annotation")
OUTDIR=$(yaml_get "$CONFIG" "outdir")
DE_ANALYSIS=$(yaml_get "$CONFIG" "de_analysis")

# ── Required keys ─────────────────────────────────────────────────────────────

[[ -z "$SAMPLE" ]]         && fail "Missing required key: sample"
[[ -z "$FASTQ_DIR" ]]      && fail "Missing required key: fastq_dir"
[[ -z "$SAMPLE_SHEET" ]]   && fail "Missing required key: sample_sheet"
[[ -z "$REF_GENOME" ]]     && fail "Missing required key: ref_genome"
[[ -z "$REF_ANNOTATION" ]] && fail "Missing required key: ref_annotation"
[[ -z "$OUTDIR" ]]         && fail "Missing required key: outdir"

# ── File/directory existence ──────────────────────────────────────────────────

if [[ -n "$FASTQ_DIR" ]]; then
    if [[ -d "$FASTQ_DIR" ]]; then
        ok "fastq_dir: $FASTQ_DIR"
    else
        fail "fastq_dir not found: $FASTQ_DIR"
    fi
fi

if [[ -n "$SAMPLE_SHEET" ]]; then
    if [[ -f "$SAMPLE_SHEET" ]]; then
        ok "sample_sheet: $SAMPLE_SHEET"
    else
        fail "sample_sheet not found: $SAMPLE_SHEET"
    fi
fi

if [[ -n "$REF_GENOME" ]]; then
    if [[ -f "$REF_GENOME" ]]; then
        ok "ref_genome: $REF_GENOME"
    else
        fail "ref_genome not found: $REF_GENOME"
    fi
fi

if [[ -n "$REF_ANNOTATION" ]]; then
    if [[ -f "$REF_ANNOTATION" ]]; then
        ok "ref_annotation: $REF_ANNOTATION"
    else
        fail "ref_annotation not found: $REF_ANNOTATION"
    fi
fi

# ── Chromosome name consistency ───────────────────────────────────────────────
# Mismatch between genome and annotation is the #1 silent failure mode.

if [[ -f "$REF_GENOME" && -f "$REF_ANNOTATION" ]]; then
    genome_chr=$(grep -m1 "^>" "$REF_GENOME" | grep -c "^>chr" || true)
    annot_chr=$(grep -v "^#" "$REF_ANNOTATION" | awk 'NR<=200{print $1}' | grep -c "^chr" || true)

    if [[ $genome_chr -gt 0 && $annot_chr -eq 0 ]]; then
        fail "Chromosome name mismatch: genome uses 'chr' prefix but annotation does not (e.g. 'chr1' vs '1')"
    elif [[ $genome_chr -eq 0 && $annot_chr -gt 0 ]]; then
        fail "Chromosome name mismatch: annotation uses 'chr' prefix but genome does not (e.g. '1' vs 'chr1')"
    else
        ok "Chromosome name format consistent between genome and annotation"
    fi
fi

# ── Sample sheet format ───────────────────────────────────────────────────────

if [[ -f "$SAMPLE_SHEET" ]]; then
    header=$(head -1 "$SAMPLE_SHEET")
    if ! echo "$header" | grep -q "barcode"; then
        fail "sample_sheet header must contain 'barcode' column (got: $header)"
    fi
    if ! echo "$header" | grep -q "alias"; then
        fail "sample_sheet header must contain 'alias' column (got: $header)"
    fi
    if [[ "$DE_ANALYSIS" == "true" ]] && ! echo "$header" | grep -q "type"; then
        fail "de_analysis is true but sample_sheet is missing 'type' column (test/control)"
    fi
    n_samples=$(tail -n +2 "$SAMPLE_SHEET" | grep -c "." || true)
    ok "sample_sheet: $n_samples samples"
fi

# ── Nextflow availability ─────────────────────────────────────────────────────

NEXTFLOW=/groups/tprice/pipelines/bin/nextflow
if [[ -x "$NEXTFLOW" ]]; then
    nf_version=$("$NEXTFLOW" -version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "unknown")
    ok "Nextflow $nf_version found at $NEXTFLOW"
elif command -v nextflow &>/dev/null; then
    nf_version=$(nextflow -version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "unknown")
    ok "Nextflow $nf_version found on PATH"
else
    fail "Nextflow not found at $NEXTFLOW and not on PATH"
fi

if command -v apptainer &>/dev/null || command -v singularity &>/dev/null; then
    ok "Apptainer/Singularity found"
else
    warn "Neither apptainer nor singularity found in PATH — required for container execution"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [[ $errors -gt 0 ]]; then
    echo "Pre-flight FAILED with $errors error(s). Fix the above before resubmitting."
    exit 1
fi

echo "Pre-flight passed — all checks OK."
