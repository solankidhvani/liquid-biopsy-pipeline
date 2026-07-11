FROM continuumio/miniconda3:latest

RUN conda config --add channels bioconda && \
    conda config --add channels conda-forge && \
    conda create -n pipeline -y fastp salmon nextflow r-base bioconductor-deseq2 r-ggplot2 r-pheatmap bioconductor-tximport gffread r-optparse && \
    echo "conda activate pipeline" >> ~/.bashrc
SHELL ["conda", "run", "-n", "pipeline", "/bin/bash", "-c"]

WORKDIR /pipeline
COPY . .

ENTRYPOINT ["./run_pipeline.sh"]
