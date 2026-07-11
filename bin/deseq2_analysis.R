#!/usr/bin/env Rscript
suppressMessages({
  library(optparse)
  library(tximport)
  library(DESeq2)
  library(ggplot2)
  library(pheatmap)
})

option_list <- list(
  make_option("--quant_dirs", type = "character"),
  make_option("--samplesheet", type = "character"),
  make_option("--outdir", type = "character", default = ".")
)
opt <- parse_args(OptionParser(option_list = option_list))

quant_dirs <- strsplit(opt$quant_dirs, ",")[[1]]

samples <- read.csv(opt$samplesheet)
rownames(samples) <- samples$sample

names(quant_dirs) <- basename(quant_dirs)
files <- file.path(quant_dirs, "quant.sf")
names(files) <- names(quant_dirs)      # <-- add this line
files <- files[samples$sample]

txi <- tximport(files, type = "salmon", txOut = TRUE, dropInfReps = TRUE)

dds <- DESeqDataSetFromTximport(txi, colData = samples, design = ~condition)
dds <- DESeq(dds, fitType = "mean")
res <- results(dds)
res_df <- as.data.frame(res)
res_df$gene <- rownames(res_df)
write.csv(res_df, file.path(opt$outdir, "deseq2_results.csv"), row.names = FALSE)

res_df$sig <- with(res_df, !is.na(padj) & padj < 0.05 & abs(log2FoldChange) > 1)
p_volcano <- ggplot(res_df, aes(x = log2FoldChange, y = -log10(pvalue), color = sig)) +
  geom_point(alpha = 0.6, size = 1.5) +
  scale_color_manual(values = c("grey70", "firebrick")) +
  theme_minimal() +
  labs(title = "Volcano Plot", x = "log2 Fold Change", y = "-log10(p-value)")
ggsave(file.path(opt$outdir, "volcano_plot.pdf"), p_volcano, width = 6, height = 5)
ggsave(file.path(opt$outdir, "volcano_plot.png"), p_volcano, width = 6, height = 5, dpi = 150)

if (nrow(dds) < 1000) {
  vsd <- varianceStabilizingTransformation(dds, blind = TRUE, fitType = "mean")
} else {
  vsd <- vst(dds, blind = TRUE)
}
pca_data <- plotPCA(vsd, intgroup = "condition", returnData = TRUE)
p_pca <- ggplot(pca_data, aes(PC1, PC2, color = condition)) +
  geom_point(size = 3) +
  theme_minimal() +
  labs(title = "PCA Plot")
ggsave(file.path(opt$outdir, "pca_plot.pdf"), p_pca, width = 6, height = 5)
ggsave(file.path(opt$outdir, "pca_plot.png"), p_pca, width = 6, height = 5, dpi = 150)


top_genes <- head(order(rowVars(assay(vsd)), decreasing = TRUE), 30)
pdf(file.path(opt$outdir, "heatmap.pdf"), width = 6, height = 8)
pheatmap(assay(vsd)[top_genes, ], annotation_col = samples[, "condition", drop = FALSE])
dev.off()

png(file.path(opt$outdir, "heatmap.png"), width = 6, height = 8, units = "in", res = 150)
pheatmap(assay(vsd)[top_genes, ], annotation_col = samples[, "condition", drop = FALSE])
dev.off()
