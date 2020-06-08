

workflow PreProcessIntervalsWorkflow {

	File ref_fasta
    File ref_fasta_fai
    File ref_fasta_dict

	File intervals


    call PreprocessIntervals {
        input:
            intervals = intervals,
            ref_fasta = ref_fasta,
            ref_fasta_fai = ref_fasta_fai,
            ref_fasta_dict = ref_fasta_dict
    }

    call AnnotateIntervals {
        input:
            intervals = PreprocessIntervals.preprocessed_intervals,
            ref_fasta = ref_fasta,
            ref_fasta_fai = ref_fasta_fai,
            ref_fasta_dict = ref_fasta_dict
    }

  	call FilterIntervals {
        input:
            intervals = PreprocessIntervals.preprocessed_intervals,
            annotated_intervals = AnnotateIntervals.annotated_intervals
    }


    output {
    	File preprocessed_intervals = PreprocessIntervals.preprocessed_intervals
    	File filtered_intervals = FilterIntervals.filtered_intervals

    }

}

task PreprocessIntervals {
    File? intervals
    File? blacklist_intervals
    File ref_fasta
    File ref_fasta_fai
    File ref_fasta_dict
    Int? padding
    Int? bin_length

    # Determine output filename
    #String filename = select_first([intervals, "wgs"])

    String base_filename = basename(intervals, ".bed")

    command <<<
        set -e
        module load GATK/4.1.0.0-Java-1.8.0_121

        gatk --java-options "-Xmx14g -Xms5g" PreprocessIntervals \
            ${"-L " + intervals} \
            ${"-XL " + blacklist_intervals} \
            --sequence-dictionary ${ref_fasta_dict} \
            --reference ${ref_fasta} \
            --padding ${default="250" padding} \
            --bin-length ${default="1000" bin_length} \
            --interval-merging-rule OVERLAPPING_ONLY \
            --output ${base_filename}.preprocessed.interval_list
    >>>

    runtime {
        cpus: 4
        requested_memory: 16000  
    }

    output {
        File preprocessed_intervals = "${base_filename}.preprocessed.interval_list"
    }
}

task AnnotateIntervals {
    File intervals
    File ref_fasta
    File ref_fasta_fai
    File ref_fasta_dict
    File? mappability_track_bed
    File? mappability_track_bed_idx
    File? segmental_duplication_track_bed
    File? segmental_duplication_track_bed_idx
    Int? feature_query_lookahead
    
    # Determine output filename
    #String filename = select_first([intervals, "wgs.preprocessed"])
    String base_filename = basename(intervals, ".interval_list")

    command <<<
        set -e
        module load GATK/4.1.0.0-Java-1.8.0_121

        gatk --java-options "-Xmx14g -Xms5g" AnnotateIntervals \
            -L ${intervals} \
            --reference ${ref_fasta} \
            ${"--mappability-track " + mappability_track_bed} \
            ${"--segmental-duplication-track " + segmental_duplication_track_bed} \
            --feature-query-lookahead ${default=1000000 feature_query_lookahead} \
            --interval-merging-rule OVERLAPPING_ONLY \
            --output ${base_filename}.annotated.tsv
    >>>

    runtime {
        cpus: 4
        requested_memory: 16000  
    }

    output {
        File annotated_intervals = "${base_filename}.annotated.tsv"
    }
}

task FilterIntervals {
    File intervals
    File? blacklist_intervals
    File? annotated_intervals
    Array[File]? read_count_files
    Float? minimum_gc_content
    Float? maximum_gc_content
    Float? minimum_mappability
    Float? maximum_mappability
    Float? minimum_segmental_duplication_content
    Float? maximum_segmental_duplication_content
    Int? low_count_filter_count_threshold
    Float? low_count_filter_percentage_of_samples
    Float? extreme_count_filter_minimum_percentile
    Float? extreme_count_filter_maximum_percentile
    Float? extreme_count_filter_percentage_of_samples


    # Determine output filename
    #String filename = select_first([intervals, "wgs.preprocessed"])
    String base_filename = basename(intervals, ".preprocessed.interval_list")

    command <<<
        set -e
        module load GATK/4.1.0.0-Java-1.8.0_121

        gatk --java-options "-Xmx14g -Xms5g" FilterIntervals \
            -L ${intervals} \
            ${"-XL " + blacklist_intervals} \
            ${"--annotated-intervals " + annotated_intervals} \
            ${if defined(read_count_files) then "--input " else ""} ${sep=" --input " read_count_files} \
            --minimum-gc-content ${default="0.1" minimum_gc_content} \
            --maximum-gc-content ${default="0.9" maximum_gc_content} \
            --minimum-mappability ${default="0.9" minimum_mappability} \
            --maximum-mappability ${default="1.0" maximum_mappability} \
            --minimum-segmental-duplication-content ${default="0.0" minimum_segmental_duplication_content} \
            --maximum-segmental-duplication-content ${default="0.5" maximum_segmental_duplication_content} \
            --low-count-filter-count-threshold ${default="5" low_count_filter_count_threshold} \
            --low-count-filter-percentage-of-samples ${default="90.0" low_count_filter_percentage_of_samples} \
            --extreme-count-filter-minimum-percentile ${default="1.0" extreme_count_filter_minimum_percentile} \
            --extreme-count-filter-maximum-percentile ${default="99.0" extreme_count_filter_maximum_percentile} \
            --extreme-count-filter-percentage-of-samples ${default="90.0" extreme_count_filter_percentage_of_samples} \
            --interval-merging-rule OVERLAPPING_ONLY \
            --output ${base_filename}.filtered.interval_list
    >>>

    runtime {
        cpus: 4
        requested_memory: 16000  
    }

    output {
        File filtered_intervals = "${base_filename}.filtered.interval_list"
    }
}
