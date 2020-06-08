#!/bin/bash
#SBATCH -c 8
#SBATCH -J launch_cromwell
#SBATCH --mem=64000

java -Xmx64g -Dconfig.file=/gpfs/ycga/project/ysm/lek/shared/tools/cromwell_wdl/slurm.conf \
-jar /gpfs/ycga/project/ysm/lek/shared/tools/jars/cromwell-36.jar \
run /home/ml2529/project/GATK_gCNV/cnv_germline_cohort_workflow.wdl \
-i /home/ml2529/project/GATK_gCNV/cnv_germline_cohort_workflow.json \
-o /home/ml2529/project/GATK_gCNV/cromwell.options
