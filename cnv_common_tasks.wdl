
task CollectCounts {
    File bam
    File bai

    File intervals

    File ref_fasta
    File ref_fasta_fai
    File ref_fasta_dict

    # Sample name is derived from the bam filename
    String base_filename = basename(bam, ".bam")
    String counts_filename = "${base_filename}.counts.tsv"

    command <<<
        set -e

        /home/ml2529/bin/gatk-4.1.7.0/gatk --java-options "-Xmx14g -Xms5g" CollectReadCounts \
            -I ${bam} \
            --read-index ${bai} \
            -L ${intervals} \
            --reference ${ref_fasta} \
            --format TSV \
            --interval-merging-rule OVERLAPPING_ONLY \
            --output ${counts_filename}
    >>>

    runtime {
        cpus: 4
        requested_memory: 16000  
    }

    output {
        String entity_id = base_filename
        File counts = counts_filename
    }
}

task ScatterIntervals {
    File interval_list
    Int num_intervals_per_scatter
    String? output_dir

    # If optional output_dir not specified, use "out";
    String output_dir_ = select_first([output_dir, "out"])

    String base_filename = basename(interval_list, ".interval_list")

    command <<<
        set -e
        mkdir ${output_dir_}

        
        {
            >&2 echo "Attempting to run IntervalListTools..."
            /home/ml2529/bin/gatk-4.1.7.0/gatk --java-options "-Xmx4000m" IntervalListTools \
                --INPUT ${interval_list} \
                --SUBDIVISION_MODE INTERVAL_COUNT \
                --SCATTER_CONTENT ${num_intervals_per_scatter} \
                --OUTPUT ${output_dir_} &&
            # output files are named output_dir_/temp_0001_of_N/scattered.interval_list, etc. (N = num_intervals_per_scatter);
            # we rename them as output_dir_/base_filename.scattered.0000.interval_list, etc.
            ls ${output_dir_}/*/scattered.interval_list | \
                cat -n | \
                while read n filename; do mv $filename ${output_dir_}/${base_filename}.scattered.$(printf "%04d" $n).interval_list; done
        } || {
            # if only a single shard is required, then we can just rename the original interval list
            >&2 echo "IntervalListTools failed because only a single shard is required. Copying original interval list..."
            cp ${interval_list} ${output_dir_}/${base_filename}.scattered.1.interval_list
        }
    >>>

    runtime {
        cpus: 1
        requested_memory: 4000
    }

    output {
        Array[File] scattered_interval_lists = glob("${output_dir_}/${base_filename}.scattered.*.interval_list")
    }
}

task PostprocessGermlineCNVCalls {
    String entity_id
    Array[File] gcnv_calls_tars
    Array[File] gcnv_model_tars
    Array[File] calling_configs
    Array[File] denoising_configs
    Array[File] gcnvkernel_version
    Array[File] sharded_interval_lists
    File contig_ploidy_calls_tar
    Array[String]? allosomal_contigs
    Int ref_copy_number_autosomal_contigs
    Int sample_index

    String genotyped_intervals_vcf_filename = "genotyped-intervals-${entity_id}.vcf.gz"
    String genotyped_segments_vcf_filename = "genotyped-segments-${entity_id}.vcf.gz"
    String denoised_copy_ratios_filename = "denoised_copy_ratios-${entity_id}.tsv"

    Array[String] allosomal_contigs_args = if defined(allosomal_contigs) then prefix("--allosomal-contig ", select_first([allosomal_contigs])) else []

    String dollar = "$" #WDL workaround for using array[@], see https://github.com/broadinstitute/cromwell/issues/1819

    command <<<
        set -e

        module load miniconda/4.6.14
        source /ycga-gpfs/apps/hpc/software/Python/miniconda/bin/activate /gpfs/ycga/project/lek/ml2529/conda_envs/gatk

        sharded_interval_lists_array=(${sep=" " sharded_interval_lists})

        # untar calls to CALLS_0, CALLS_1, etc directories and build the command line
        # also copy over shard config and interval files
        gcnv_calls_tar_array=(${sep=" " gcnv_calls_tars})
        calling_configs_array=(${sep=" " calling_configs})
        denoising_configs_array=(${sep=" " denoising_configs})
        gcnvkernel_version_array=(${sep=" " gcnvkernel_version})
        sharded_interval_lists_array=(${sep=" " sharded_interval_lists})
        calls_args=""
        for index in ${dollar}{!gcnv_calls_tar_array[@]}; do
            gcnv_calls_tar=${dollar}{gcnv_calls_tar_array[$index]}
            mkdir -p CALLS_$index/SAMPLE_${sample_index}
            tar xzf $gcnv_calls_tar -C CALLS_$index/SAMPLE_${sample_index}
            cp ${dollar}{calling_configs_array[$index]} CALLS_$index/
            cp ${dollar}{denoising_configs_array[$index]} CALLS_$index/
            cp ${dollar}{gcnvkernel_version_array[$index]} CALLS_$index/
            cp ${dollar}{sharded_interval_lists_array[$index]} CALLS_$index/
            calls_args="$calls_args --calls-shard-path CALLS_$index"
        done

        # untar models to MODEL_0, MODEL_1, etc directories and build the command line
        gcnv_model_tar_array=(${sep=" " gcnv_model_tars})
        model_args=""
        for index in ${dollar}{!gcnv_model_tar_array[@]}; do
            gcnv_model_tar=${dollar}{gcnv_model_tar_array[$index]}
            mkdir MODEL_$index
            tar xzf $gcnv_model_tar -C MODEL_$index
            model_args="$model_args --model-shard-path MODEL_$index"
        done

        mkdir extracted-contig-ploidy-calls
        tar xzf ${contig_ploidy_calls_tar} -C extracted-contig-ploidy-calls

        /home/ml2529/bin/gatk-4.1.7.0/gatk --java-options "-Xmx7000m" PostprocessGermlineCNVCalls \
            $calls_args \
            $model_args \
            ${sep=" " allosomal_contigs_args} \
            --autosomal-ref-copy-number ${ref_copy_number_autosomal_contigs} \
            --contig-ploidy-calls extracted-contig-ploidy-calls \
            --sample-index ${sample_index} \
            --output-genotyped-intervals ${genotyped_intervals_vcf_filename} \
            --output-genotyped-segments ${genotyped_segments_vcf_filename} \
            --output-denoised-copy-ratios ${denoised_copy_ratios_filename}
        
        rm -rf CALLS_*
        rm -rf MODEL_*
        rm -rf extracted-contig-ploidy-calls
    >>>

    runtime {
        cpus: 1
        requested_memory: 8000
    }

    output {
        File genotyped_intervals_vcf = genotyped_intervals_vcf_filename
        File genotyped_segments_vcf = genotyped_segments_vcf_filename
        File denoised_copy_ratios = denoised_copy_ratios_filename
    }
}


