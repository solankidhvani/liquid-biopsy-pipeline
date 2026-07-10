process SALMON_INDEX {
    tag "salmon_index"
    publishDir "${params.outdir}/salmon_index", mode: 'copy'

    input:
    path transcriptome

    output:
    path "salmon_index", emit: index

    script:
    """
    salmon index -t ${transcriptome} -i salmon_index -k 31
    """
}

process SALMON_QUANT {
    tag { sample_id }
    publishDir "${params.outdir}/salmon_quant", mode: 'copy'

    input:
    tuple val(sample_id), path(reads)
    path index

    output:
    path "${sample_id}", emit: quant

    script:
    """
    salmon quant -i ${index} -l A \
        -1 ${reads[0]} -2 ${reads[1]} \
        -p 4 --validateMappings \
        -o ${sample_id}
    """
}
