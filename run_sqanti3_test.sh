#!/bin/bash
# Local smoke test: run SQANTI3 QC → ref QC → Filter → Rescue on chr22 UHR example data.
# Uses the Apptainer SIF (not SLURM). Runs all 4 stages sequentially.
#
# NOTE: Outputs are written to /tmp/sqanti3_test/ (Linux filesystem) because STAR
# requires Linux filesystem for FIFO temp files and cannot write to NTFS/FAT mounts.
#
# Run from: /mnt/c/users/mwild/firebase2/longreads/
#   ./run_sqanti3_test.sh
#
# Optional: clean previous outputs first
#   ./run_sqanti3_test.sh --clean

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQANTI3_DIR="$REPO_DIR/SQANTI3"
SIF="$SQANTI3_DIR/sqanti3_v5.5.4.sif"
DATA_DIR="$SQANTI3_DIR/data"

# All outputs go to Linux filesystem to support STAR's FIFO temp files
OUTDIR=/tmp/sqanti3_test
FILTER_JSON=/opt2/sqanti3/5.5.4/SQANTI3-5.5.4/src/utilities/filter/filter_default.json

# ── Args ──────────────────────────────────────────────────────────────────────

CLEAN=false
[[ "${1:-}" == "--clean" ]] && CLEAN=true

# ── Pre-flight ────────────────────────────────────────────────────────────────

if [[ ! -f "$SIF" ]]; then
    echo "ERROR: SIF not found at $SIF"
    echo "  Pull it with:"
    echo "  cd '$SQANTI3_DIR' && apptainer pull sqanti3_v5.5.4.sif docker://anaconesalab/sqanti3:v5.5.4"
    exit 1
fi

if [[ ! -f "$DATA_DIR/UHR_chr22.gtf" ]]; then
    echo "ERROR: Test data not found at $DATA_DIR"
    exit 1
fi

# Run pre-flight validation
bash "$REPO_DIR/scripts/sqanti3_preflight.sh" /tmp/sqanti3_test.yaml 2>/dev/null || true

# ── Clean outputs if requested ────────────────────────────────────────────────

if $CLEAN; then
    echo "Cleaning previous outputs at $OUTDIR..."
    rm -rf "$OUTDIR"
fi

mkdir -p "$OUTDIR/qc" "$OUTDIR/refqc" "$OUTDIR/filter" "$OUTDIR/rescue"

# ── Create absolute-path FOFN (SQANTI3 FOFN uses relative paths; STAR needs abs) ───
ABS_FOFN="$OUTDIR/short_reads.fofn"
{
    echo "${DATA_DIR}/short_reads/UHR_Rep1_chr22.R1.fastq.gz ${DATA_DIR}/short_reads/UHR_Rep1_chr22.R2.fastq.gz"
    echo "${DATA_DIR}/short_reads/UHR_Rep2_chr22.R1.fastq.gz ${DATA_DIR}/short_reads/UHR_Rep2_chr22.R2.fastq.gz"
} > "$ABS_FOFN"

# ── Write per-stage configs (absolute paths, Linux output dirs) ───────────────

CONFIG_DIR="$OUTDIR/configs"
mkdir -p "$CONFIG_DIR"

# Stage 1a: QC
cat > "$CONFIG_DIR/qc.yaml" <<YAML
main:
  refGTF: '${DATA_DIR}/reference/gencode.v38.basic_chr22.gtf'
  refFasta: '${DATA_DIR}/reference/GRCh38.p13_chr22.fasta'
  cpus: 4
  dir: '${OUTDIR}/qc'
  output: 'UHR_chr22'
  log_level: INFO
qc:
  enabled: true
  options:
    isoforms: '${DATA_DIR}/UHR_chr22.gtf'
    min_ref_len: 0
    force_id_ignore: false
    fasta: false
    genename: false
    short_reads: '${ABS_FOFN}'
    SR_bam: ''
    novel_gene_prefix: ''
    aligner_choice: minimap2
    gmap_index: ''
    sites: ATAC,GCAG,GTAG
    skipORF: false
    orf_input: ''
    CAGE_peak: '${DATA_DIR}/ref_TSS_annotation/human.refTSS_v3.1.hg38.bed'
    polyA_motif_list: '${DATA_DIR}/polyA_motifs/mouse_and_human.polyA_motif.txt'
    polyA_peak: ''
    phyloP_bed: ''
    saturation: false
    report: skip
    isoform_hits: false
    ratio_TSS_metric: max
    chunks: 1
    is_fusion: false
    expression: ''
    coverage: ''
    window: 20
    fl_count: '${DATA_DIR}/UHR_abundance.tsv'
    isoAnnotLite: false
    gff3: ''
filter:
  enabled: false
rescue:
  enabled: false
YAML

# Stage 1b: Reference QC
cat > "$CONFIG_DIR/refqc.yaml" <<YAML
main:
  refGTF: '${DATA_DIR}/reference/gencode.v38.basic_chr22.gtf'
  refFasta: '${DATA_DIR}/reference/GRCh38.p13_chr22.fasta'
  cpus: 4
  dir: '${OUTDIR}/refqc'
  output: 'ref'
  log_level: INFO
qc:
  enabled: true
  options:
    isoforms: '${DATA_DIR}/reference/gencode.v38.basic_chr22.gtf'
    min_ref_len: 0
    force_id_ignore: false
    fasta: false
    genename: false
    short_reads: ''
    SR_bam: ''
    novel_gene_prefix: ''
    aligner_choice: minimap2
    gmap_index: ''
    sites: ATAC,GCAG,GTAG
    skipORF: true
    orf_input: ''
    CAGE_peak: ''
    polyA_motif_list: ''
    polyA_peak: ''
    phyloP_bed: ''
    saturation: false
    report: skip
    isoform_hits: false
    ratio_TSS_metric: max
    chunks: 1
    is_fusion: false
    expression: ''
    coverage: ''
    window: 20
    fl_count: ''
    isoAnnotLite: false
    gff3: ''
filter:
  enabled: false
rescue:
  enabled: false
YAML

# Stage 2: Filter
cat > "$CONFIG_DIR/filter.yaml" <<YAML
main:
  refGTF: '${DATA_DIR}/reference/gencode.v38.basic_chr22.gtf'
  refFasta: '${DATA_DIR}/reference/GRCh38.p13_chr22.fasta'
  cpus: 4
  dir: '${OUTDIR}/filter'
  output: 'UHR_chr22'
  log_level: INFO
qc:
  enabled: false
filter:
  enabled: true
  options:
    common:
      sqanti_class: '${OUTDIR}/qc/UHR_chr22_classification.txt'
      isoAnnotGFF3: ''
      filter_isoforms: '${OUTDIR}/qc/UHR_chr22_corrected.fasta'
      filter_gtf: '${OUTDIR}/qc/UHR_chr22_corrected.gtf'
      filter_sam: ''
      filter_faa: '${OUTDIR}/qc/UHR_chr22_corrected.faa'
      skip_report: true
      filter_mono_exonic: false
    rules:
      enabled: true
      options:
        json_filter: '${FILTER_JSON}'
    ml:
      enabled: false
rescue:
  enabled: false
YAML

# Stage 3: Rescue
cat > "$CONFIG_DIR/rescue.yaml" <<YAML
main:
  refGTF: '${DATA_DIR}/reference/gencode.v38.basic_chr22.gtf'
  refFasta: '${DATA_DIR}/reference/GRCh38.p13_chr22.fasta'
  cpus: 4
  dir: '${OUTDIR}/rescue'
  output: 'UHR_chr22'
  log_level: INFO
qc:
  enabled: false
filter:
  enabled: false
rescue:
  enabled: true
  options:
    common:
      filter_class: '${OUTDIR}/filter/UHR_chr22_RulesFilter_result_classification.txt'
      rescue_isoforms: '${OUTDIR}/qc/UHR_chr22_corrected.fasta'
      rescue_gtf: '${OUTDIR}/filter/UHR_chr22.filtered.gtf'
      refClassif: '${OUTDIR}/refqc/ref_classification.txt'
      counts: '${DATA_DIR}/UHR_abundance.tsv'
      rescue_mono_exonic: all
      mode: automatic
      requant: false
    rules:
      enabled: true
      options:
        json_filter: '${FILTER_JSON}'
    ml:
      enabled: false
      options:
        random_forest: ''
        threshold: 0.7
YAML

# ── Helper: run a sqanti3 command inside the SIF ─────────────────────────────

run_sqanti3() {
    local stage="$1"
    local config="$2"
    echo ""
    echo "========================================"
    echo "  SQANTI3 $stage"
    echo "========================================"
    apptainer exec \
        --env HOME=/tmp \
        --env PYTHONNOUSERSITE=1 \
        --bind "$SQANTI3_DIR:$SQANTI3_DIR" \
        --bind "$OUTDIR:$OUTDIR" \
        --bind "/tmp:/tmp" \
        "$SIF" \
        conda run --no-capture-output -n sqanti3 \
        sqanti3 "$stage" -c "$config"
}

# ── Run all stages ────────────────────────────────────────────────────────────

run_sqanti3 qc     "$CONFIG_DIR/qc.yaml"
run_sqanti3 qc     "$CONFIG_DIR/refqc.yaml"

# Rename ref_classification for rescue
REFQC_CLASSIF=$(find "$OUTDIR/refqc" -name "*_classification.txt" | head -1)
if [[ -n "$REFQC_CLASSIF" && "$(basename "$REFQC_CLASSIF")" != "ref_classification.txt" ]]; then
    cp "$REFQC_CLASSIF" "$OUTDIR/refqc/ref_classification.txt"
    echo "  → Copied $(basename "$REFQC_CLASSIF") → ref_classification.txt"
fi

run_sqanti3 filter "$CONFIG_DIR/filter.yaml"
run_sqanti3 rescue "$CONFIG_DIR/rescue.yaml"

# ── Validate outputs ──────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "  Output validation"
echo "========================================"

PASS=0
FAIL=0

check() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        echo "  OK:   $label"
        ((PASS++)) || true
    else
        echo "  FAIL: $label — not found: $path"
        ((FAIL++)) || true
    fi
}

check "QC classification"     "$OUTDIR/qc/UHR_chr22_classification.txt"
check "QC corrected GTF"      "$OUTDIR/qc/UHR_chr22_corrected.gtf"
check "QC corrected FASTA"    "$OUTDIR/qc/UHR_chr22_corrected.fasta"
check "Ref QC classification" "$OUTDIR/refqc/ref_classification.txt"
check "Filter classification" "$OUTDIR/filter/UHR_chr22_RulesFilter_result_classification.txt"
check "Filtered GTF"          "$OUTDIR/filter/UHR_chr22.filtered.gtf"
check "Rescued GTF"           "$OUTDIR/rescue/UHR_chr22_rescued.gtf"
check "Rescued FASTA"         "$OUTDIR/rescue/UHR_chr22_rescued.fasta"

echo ""
if [[ $FAIL -gt 0 ]]; then
    echo "RESULT: FAILED — $PASS passed, $FAIL missing"
    exit 1
else
    echo "RESULT: ALL PASSED ($PASS/$(( PASS + FAIL )) outputs present)"
    echo ""
    echo "QC output:      $OUTDIR/qc/"
    echo "Ref QC output:  $OUTDIR/refqc/"
    echo "Filter output:  $OUTDIR/filter/"
    echo "Rescue output:  $OUTDIR/rescue/"
fi
