#!/bin/bash
#SBATCH --job-name=I4C_eval
#SBATCH --output=I4C_eval%j.out
#SBATCH --error=I4C_eval%j.error
#SBATCH --qos=meteo_high
#SBATCH --ntasks=832                 	# Total MPI ranks
#SBATCH --ntasks-per-node=64         	# MPI ranks per node
#SBATCH --exclusive                   	# Exclusive node allocation
#SBATCH --cpus-per-task=1             	# One CPU per MPI rank
#SBATCH --threads-per-core=1
#SBATCH --hint=nomultithread          	# Disable hyperthreading
#SBATCH --time=720:00:00
#SBATCH --partition=wncompute_meteo
#SBATCH --distribution=block:block
#SBATCH --exclude=wncompute056
#SBATCH --mem-per-cpu=3G
#SBATCH --mail-user=milovacj@unican.es
#SBATCH --mail-type=FAIL              	# Slurm email on job failure
#SBATCH --mail-type=END               	# Optional: job end notification

echo "START TIME: $(date)"
input_path="/gpfs/users/milovacj/asna/projects/impetus/02_I4C_evaluation/data/input/real/"

# -----------------------------
# Update namelist and aerosols
# -----------------------------
source ~/.bashrc
conda activate NCLtoPY
python restart_setup.py 2
conda deactivate

# -----------------------------
# System limits for MPI stability
# -----------------------------
ulimit -s unlimited   # Remove stack size limit (prevents Fortran stack overflow)
ulimit -l unlimited   # Remove locked memory limit (needed for MPI pinned memory)

# -----------------------------
# Load required modules
# -----------------------------
module purge
module use /gpfs/projects/meteo/WORK/ASNA/apps/privatemodules
module load wrflibs_spack/compiler/intel-classic-2021.10.0
module load wrflibs_spack/mpi/intel-oneapi-mpi-2021.11.0
module load wrflibs_spack/netcdf-c/4.9.2-intel-oneapi-mpi-2021.11.0-intel-2021.10.0
module load wrflibs_spack/netcdf-fortran/4.6.1-intel-oneapi-mpi-2021.11.0-intel-2021.10.0
module load OPENUCX/1.15.0_intel

# Path to NetCDF
export NETCDF=/gpfs/projects/meteo/WORK/josipa/CMIP6toWRF/WRF_binaries/WRF_spacklibs/NETCDF/

# -----------------------------
# Compiler settings for WRF
# -----------------------------
export CC=icc
export CXX=icpc
export FC=ifort
export F90=ifort
export F77=ifort

# WRF I/O options
export NETCDF4=1                         # Use NetCDF4/HDF5 I/O
export WRFIO_NCD_LARGE_FILE_SUPPORT=1    # Support files >2GB

# -----------------------------
# Intel MPI tuning
# -----------------------------
export I_MPI_ADJUST_ALLREDUCE=3          # Robust global reductions
export I_MPI_ADJUST_BARRIER=3            # Robust barrier sync
export I_MPI_SHM_HEAP_VSIZE=512          # Shared memory buffer per rank (MB)
export I_MPI_JOB_TIMEOUT=3600            # Kill job if no MPI progress >1h

# NUMA-aware process and memory pinning
export I_MPI_PIN_DOMAIN=numa             	# Pin ranks to NUMA nodes
export I_MPI_PIN_PROCESSOR_LIST=all      	# Allow ranks on all cores
export I_MPI_FABRICS=shm:ofi             	# Shared memory + Infiniband
export I_MPI_PMI_LIBRARY=/usr/lib64/libpmi.so  	# PMI library for Slurm

# Minimal MPI debug
export I_MPI_DEBUG=0
export I_MPI_HYDRA_DEBUG=1

# -----------------------------
# Watchdog to kill frozen WRF runs and send email
# -----------------------------
touch "rsl.error.0000"
(
  LOGFILE="rsl.out.0000"
  TIMEOUT_MIN=30
  while true; do
    if [ -f "$LOGFILE" ]; then
      last_mod=$(stat -c %Y "$LOGFILE")
      now=$(date +%s)
      diff=$(( (now - last_mod) / 60 ))
      if [ $diff -ge $TIMEOUT_MIN ]; then
        echo "[$(date)] WRF frozen (> $TIMEOUT_MIN min). Cancelling job." | \
          mail -s "WRF Job $SLURM_JOB_ID frozen on $(hostname)" milovacj@unican.es
        scancel $SLURM_JOB_ID
        exit 1
      fi
    fi
    sleep 30m
  done
) &
WATCHDOG_PID=$!

# -----------------------------
# Working directory
# -----------------------------
export wrkdir=$(pwd)
cd $wrkdir

# -----------------------------
# Run WRF
# -----------------------------
srun --cpu-bind=cores ./wrf.exe
STATUS=$?   # Capture exit status
echo "Status is: $STATUS"

# Kill watchdog if WRF finishes normally
kill $WATCHDOG_PID 2>/dev/null

# -----------------------------
# Email if WRF crashed
# -----------------------------
if [ $STATUS -ne 0 ]; then
  echo "WRF job $SLURM_JOB_ID crashed on $(hostname)" | \
  mail -s "WRF Job $SLURM_JOB_NAME Crash Alert" milovacj@unican.es
else
  echo "WRF job $SLURM_JOB_ID comleted on $(hostname) with success!" | \
  mail -s "WRF Job $SLURM_JOB_NAME Completed" milovacj@unican.es
fi

# -----------------------------
# Post-run save rsl file
# -----------------------------
mv rsl.error.0000 ${SLURM_NTASKS}_${SLURM_NTASKS_PER_NODE}_rsl.error.0000_${SLURM_JOB_ID}

# Extract the year from the latest wrfrst file
year=$(ls -t wrfrst_d02_* | head -n 1 | awk -F'[_-]' '{print $3}')

# Relink the correct forcing files:
ln -sf ${input_path}/wrfbdy*_$year wrfbdy_d01
ln -sf ${input_path}/wrflowinp*d01*_$year wrflowinp_d01
ln -sf ${input_path}/wrflowinp*d02*_$yeat wrflowinp_d02

echo "END TIME: $(date)"

# -----------------------------
# Resubmit the same job
# -----------------------------
sbatch "$0"

