process FASTP {
    tag { sample_id }
    publishDir { "${params.outdir}/fastp/${sample_id}" }, mode: 'copy'

    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val(sample_id), path("${sample_id}_trimmed_R{1,2}.fastq"), emit: trimmed
    path "${sample_id}_report.html"
    path "${sample_id}_report.json"

    script:
    """
    fastp \
        -i ${reads[0]} -I ${reads[1]} \
        -o ${sample_id}_trimmed_R1.fastq -O ${sample_id}_trimmed_R2.fastq \
        --trim_poly_g \
        --length_required 15 \
        -h ${sample_id}_report.html \
        -j ${sample_id}_report.json
    """
}
