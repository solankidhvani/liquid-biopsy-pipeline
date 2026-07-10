process DESEQ2 {
    publishDir params.outdir, mode: 'copy'

    input:
    path quant_dirs
    path samplesheet

    
    output:
    path "volcano_plot.pdf"
    path "volcano_plot.png"
    path "pca_plot.pdf"
    path "pca_plot.png"
    path "heatmap.pdf"
    path "heatmap.png"
    path "deseq2_results.csv"

    script:
    """
    Rscript ${projectDir}/bin/deseq2_analysis.R \\
        --quant_dirs '${quant_dirs.join(",")}' \\
        --samplesheet ${samplesheet} \\
        --outdir .
    """
}
