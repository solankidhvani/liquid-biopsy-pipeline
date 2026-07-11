#!/usr/bin/env nextflow

/*
 * Liquid Biopsy / RNA-seq Mini Pipeline
 * QC/Trim (fastp) -> Pseudo-alignment (Salmon) -> DESeq2 + plots (R)
 */

nextflow.enable.dsl=2

params.reads   = "data/raw/*_R{1,2}.fastq"
params.transcriptome = "data/reference/transcriptome.fa"
params.outdir  = "data/results"
params.samplesheet = "data/samplesheet.csv"



include { FASTP }  from './modules/fastp.nf'
include { SALMON_INDEX; SALMON_QUANT } from './modules/salmon.nf'
include { DESEQ2 } from './modules/deseq2.nf'

workflow {
    read_pairs_ch = Channel.fromFilePairs(params.reads, checkIfExists: false)

    read_pairs_ch.ifEmpty {
        error "No paired FASTQ files found matching pattern: ${params.reads}\n" +
              "Add files to data/raw/ named like sample1_R1.fastq / sample1_R2.fastq, then re-run."
    }

    FASTP(read_pairs_ch)

    SALMON_INDEX(file(params.transcriptome))
    SALMON_QUANT(FASTP.out.trimmed, SALMON_INDEX.out.index)

    quant_dirs_ch = SALMON_QUANT.out.quant.collect()
    samplesheet_ch = Channel.fromPath(params.samplesheet, checkIfExists: true)

    DESEQ2(quant_dirs_ch, samplesheet_ch)
}

