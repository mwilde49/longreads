#!/usr/bin/env bash
# sqanti3_preflight.sh — Pre-flight validation for SQANTI3 pipeline
#
# Checks:
#   1. All required input files exist
#   2. Chromosome names are consistent across isoforms GTF, refGTF, and refFasta
#   3. outdir parent is writable
#
# Usage: sqanti3_preflight.sh <config.yaml>
# Exit 0 = pass, Exit 1 = fail

set -euo pipefail

CONFIG="${1:?Usage: $0 <config.yaml>}"

if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: Config file not found: $CONFIG"
    exit 1
fi

yaml_get() {
    local file="$1" key="$2"
    grep -E "^${key}:" "$file" 2>/dev/null | head -1 \
        | sed "s/^${key}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^['\"]//; s/['\"]$//" || true
}

ERRORS=0
WARNINGS=0

err()  { echo "  ERROR: $*" >&2; ((ERRORS++)) || true; }
warn() { echo "  WARN:  $*"; ((WARNINGS++)) || true; }
ok()   { echo "  OK:    $*"; }

echo "SQANTI3 Pre-flight Validation"
echo "Config: $CONFIG"
echo ""

# ── Read required fields ──────────────────────────────────────────────────────

SAMPLE=$(yaml_get "$CONFIG" "sample")
ISOFORMS=$(yaml_get "$CONFIG" "isoforms")
REF_GTF=$(yaml_get "$CONFIG" "refGTF")
REF_FASTA=$(yaml_get "$CONFIG" "refFasta")
COVERAGE=$(yaml_get "$CONFIG" "coverage")
FL_COUNT=$(yaml_get "$CONFIG" "fl_count")
OUTDIR=$(yaml_get "$CONFIG" "outdir")

echo "[1/3] Required fields"

[[ -z "$SAMPLE"   ]] && err "'sample' is not set"    || ok "sample = $SAMPLE"
[[ -z "$ISOFORMS" ]] && err "'isoforms' is not set"  || true
[[ -z "$REF_GTF"  ]] && err "'refGTF' is not set"    || true
[[ -z "$REF_FASTA" ]] && err "'refFasta' is not set"  || true
[[ -z "$OUTDIR"   ]] && err "'outdir' is not set"    || true

# ── Required file existence ───────────────────────────────────────────────────

echo ""
echo "[2/3] Input file existence"

check_file() {
    local label="$1" path="$2"
    if [[ -z "$path" ]]; then
        err "$label: path is empty"
    elif [[ ! -f "$path" ]]; then
        err "$label does not exist: $path"
    else
        ok "$label: $path"
    fi
}

check_opt_file() {
    local label="$1" path="$2"
    if [[ -z "$path" ]]; then
        ok "$label: (not provided, skipped)"
    elif [[ ! -f "$path" ]]; then
        warn "$label does not exist (optional): $path"
    else
        ok "$label: $path"
    fi
}

check_file "isoforms GTF" "$ISOFORMS"
check_file "refGTF"       "$REF_GTF"
check_file "refFasta"     "$REF_FASTA"
check_opt_file "coverage (SJ.out.tab)" "$COVERAGE"
check_opt_file "fl_count"              "$FL_COUNT"

# ── Chromosome name consistency ───────────────────────────────────────────────

echo ""
echo "[3/3] Chromosome name consistency"

if [[ -f "$ISOFORMS" && -f "$REF_GTF" && -f "$REF_FASTA" ]]; then
    # Extract first chromosome name from each source (single-process awk avoids SIGPIPE with pipefail)
    ISO_CHR=$(awk '!/^#/{print $1; exit}' "$ISOFORMS")
    REF_CHR=$(awk '!/^#/{print $1; exit}' "$REF_GTF")
    FA_CHR=$(awk '/^>/{print substr($1,2); exit}' "$REF_FASTA")

    ok "Isoforms GTF first chrom: $ISO_CHR"
    ok "RefGTF first chrom:       $REF_CHR"
    ok "RefFasta first seq:        $FA_CHR"

    # Check for chr prefix mismatch (e.g. "chr1" vs "1")
    ISO_HAS_CHR=false; REF_HAS_CHR=false; FA_HAS_CHR=false
    [[ "$ISO_CHR" == chr* ]] && ISO_HAS_CHR=true
    [[ "$REF_CHR" == chr* ]] && REF_HAS_CHR=true
    [[ "$FA_CHR"  == chr* ]] && FA_HAS_CHR=true

    if [[ "$ISO_HAS_CHR" != "$REF_HAS_CHR" ]]; then
        err "Chromosome prefix mismatch: isoforms GTF (chr-prefix=$ISO_HAS_CHR) vs refGTF (chr-prefix=$REF_HAS_CHR)"
        err "  This causes silent wrong results. Fix: use matching chromosome naming."
    fi

    if [[ "$REF_HAS_CHR" != "$FA_HAS_CHR" ]]; then
        err "Chromosome prefix mismatch: refGTF (chr-prefix=$REF_HAS_CHR) vs refFasta (chr-prefix=$FA_HAS_CHR)"
    fi

    if [[ "$ISO_HAS_CHR" == "$REF_HAS_CHR" && "$REF_HAS_CHR" == "$FA_HAS_CHR" ]]; then
        ok "Chromosome naming consistent across all inputs"
    fi
else
    warn "Skipping chromosome consistency check (one or more files not found)"
fi

# ── Outdir writability ────────────────────────────────────────────────────────

if [[ -n "$OUTDIR" ]]; then
    OUTDIR_PARENT=$(dirname "$OUTDIR")
    mkdir -p "$OUTDIR" 2>/dev/null || true
    if [[ ! -w "$OUTDIR" && ! -w "$OUTDIR_PARENT" ]]; then
        err "outdir is not writable: $OUTDIR"
    else
        ok "outdir writable: $OUTDIR"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo "Pre-flight FAILED — $ERRORS error(s), $WARNINGS warning(s)"
    echo "Fix errors above before submitting the pipeline."
    exit 1
else
    echo "Pre-flight PASSED — $WARNINGS warning(s)"
    exit 0
fi
