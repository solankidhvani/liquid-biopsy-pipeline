#!/usr/bin/env bash
# Generates a tiny synthetic dataset for CI smoke testing.
# Not biologically meaningful — just structurally valid input
# to exercise the full pipeline (fastp -> Salmon -> DESeq2) quickly.
set -euo pipefail

FIXDIR="tests/fixtures"
mkdir -p "$FIXDIR/reads"

# 3 tiny synthetic transcripts (150bp each)
cat > "$FIXDIR/transcriptome_ci.fa" << 'FASTA'
>tx1
ATCACTTCTCGGCCTTTTGGCTAAGATCAACTGTAGTATCTGTTGTTATTAATATAATATTGTATATTCAACCAATTGTCAATACAAGGCTGTTTGTATCTGATATGAACCAAGGCTGTTTGTATCTGATATGAACCAAGGCTGTTTGTATCTGA
>tx2
GAGTACTCTCATGTGAAGTCTACCAAGCTCGTGTTCAAGGGAACCAAGGCGAAGAGTAAGAAGAAAAAGATCACTTCTCGGCCTTTTGGCTAAGATCAACTGTAGTATCTGTTGTTATTAATATAATATTGTATATTCAACCAATTGTCAATACAA
>tx3
CCAATTGTCAATACAAGGCTGTTTGTATCTGATATGAACCAAGAGTACTCTCATGTGAAGTCTACCAAGCTCGTGTTCAAGGGAACCAAGGCGAAGAGTAAGAAGAAAAAGATCACTTCTCGGCCTTTTGGCTAAGATCAACTGTAGTATCTGTT
FASTA

# Generate 4 tiny samples (2 conditions x 2 replicates), 20 read pairs each
python3 - << 'PYEOF'
import random

random.seed(42)
transcripts = {
    "tx1": "ATCACTTCTCGGCCTTTTGGCTAAGATCAACTGTAGTATCTGTTGTTATTAATATAATATTGTATATTCAACCAATTGTCAATACAAGGCTGTTTGTATCTGATATGAACCAAGGCTGTTTGTATCTGATATGAACCAAGGCTGTTTGTATCTGA",
    "tx2": "GAGTACTCTCATGTGAAGTCTACCAAGCTCGTGTTCAAGGGAACCAAGGCGAAGAGTAAGAAGAAAAAGATCACTTCTCGGCCTTTTGGCTAAGATCAACTGTAGTATCTGTTGTTATTAATATAATATTGTATATTCAACCAATTGTCAATACAA",
    "tx3": "CCAATTGTCAATACAAGGCTGTTTGTATCTGATATGAACCAAGAGTACTCTCATGTGAAGTCTACCAAGCTCGTGTTCAAGGGAACCAAGGCGAAGAGTAAGAAGAAAAAGATCACTTCTCGGCCTTTTGGCTAAGATCAACTGTAGTATCTGTT",
}
tx_names = list(transcripts.keys())

def revcomp(seq):
    comp = {"A":"T","T":"A","C":"G","G":"C"}
    return "".join(comp[b] for b in reversed(seq))

samples = ["cond1_rep1", "cond1_rep2", "cond2_rep1", "cond2_rep2"]
read_len = 50

for sample in samples:
    r1_lines, r2_lines = [], []
    for i in range(20):
        tx = random.choice(tx_names)
        seq = transcripts[tx]
        start = random.randint(0, len(seq) - read_len)
        fwd = seq[start:start+read_len]
        rev = revcomp(fwd)
        qual = "I" * read_len
        r1_lines += [f"@read{i}_{sample}/1", fwd, "+", qual]
        r2_lines += [f"@read{i}_{sample}/2", rev, "+", qual]
    with open(f"tests/fixtures/reads/{sample}_R1.fastq", "w") as f:
        f.write("\n".join(r1_lines) + "\n")
    with open(f"tests/fixtures/reads/{sample}_R2.fastq", "w") as f:
        f.write("\n".join(r2_lines) + "\n")

print("Generated 4 samples in tests/fixtures/reads/")
PYEOF

# Samplesheet
cat > "$FIXDIR/samplesheet_ci.csv" << 'CSV'
sample,condition
cond1_rep1,cond1
cond1_rep2,cond1
cond2_rep1,cond2
cond2_rep2,cond2
CSV

echo "CI fixture generated in $FIXDIR"
