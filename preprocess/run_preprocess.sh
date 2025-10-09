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

# Set the enviroment
source loadenv.UCAN-IFCA_WRF.ini

# ----------------------------------------------------------
# Main script: preprocessing
# ----------------------------------------------------------

# Set what you want to do
run_ungrib="True"
run_metgrid="True"
run_real="True"


# Check if argument for year is given
if [ -z "$1" ]; then
  echo "Usage: $0 <year>"
  exit 1
fi


# Define years
year=$1
pre_year=$((year - 1))
next_year=$((year + 1))

# Paths
export ERA5dir="/gpfs/projects/meteo/WORK/josipa/CMIP6toWRF/ERA5_forcing/ERA5/data/EUR/"
export WRFdir="/gpfs/projects/meteo/WORK/ASNA/projects/impetus/02_I4C_evaluation/rundir/WRF/run/"
export WPSdir="/gpfs/projects/meteo/WORK/ASNA/projects/impetus/02_I4C_evaluation/rundir/WPS/"


cd ${WPSdir}

# ----------------------------------------------------------
# Update dates in namelist.wps
# ----------------------------------------------------------
# Read number of domains
n=$(grep '^ *max_dom' namelist.wps | sed 's/[^0-9]*//g')

# Build date lists
start=$(yes "${year}-01-01_00:00:00," | head -n "$n" | tr '\n' ' ' | sed 's/ $//')
end=$(yes "${next_year}-01-02_00:00:00," | head -n "$n" | tr '\n' ' ' | sed 's/ $//')

# Replace lines in namelist.wps
sed -i -E "s|start_date *=.*|start_date = $start|; s|end_date *=.*|end_date = $end|" namelist.wps


# ----------------------------------------------------------
# Run ungrib
# ----------------------------------------------------------
if [ "$run_ungrib" = "True" ]; then
  echo "Running ungrib..."
  ./link_grib.csh ${ERA5dir}/${pre_year}/*${pre_year}12*.grib ${ERA5dir}/${year}/*.grib ${ERA5dir}/${next_year}/*${next_year}01*.grib
  ./ungrib.exe
fi

# ----------------------------------------------------------
# Run metgrid
# ----------------------------------------------------------
if [ "$run_metgrid" = "True" ]; then
  srun --cpu-bind=core ./metgrid.exe
  conda activate NCLtoPY										# Loda conda enviroment with cdo and nco
  python tavg_sfc_with_nco.py "met_em*d01*" # Run postprocessing for lake temperature (running mean of 15 days)
  python tavg_sfc_with_nco.py "met_em*d02*" # Run postprocessing for lake temperature (running mean of 15 days)
  conda deactivate NCLtoPY 									# To avoid conflicting with the NETCDF libraries needed for WRF
fi


# ----------------------------------------------------------
# Run real
# ----------------------------------------------------------
if [ "$run_real" = "True" ]; then
  ln -sf ${WPSdir}/met_em* ${WRFdir}/

  # Read number of domains
  n=$(grep '^ *max_dom' "${WRFdir}/namelist.input" | sed 's/[^0-9]*//g')

  # Helper function to repeat values
  repeat() { yes "$1" | head -n "$n" | tr '\n' ' ' | sed 's/ $//'; }

  # Update namelist.input in one sed call
  sed -i -E " \
    s|start_year *=.*| start_year = $(repeat "$year,")|; \
    s|start_month *=.*| start_month = $(repeat "01,")|; \
    s|start_day *=.*| start_day = $(repeat "01,")|; \
    s|end_year *=.*| end_year = $(repeat "$next_year,")|; \
    s|end_month *=.*| end_month = $(repeat "01,")|; \
    s|end_day *=.*| end_day = $(repeat "02,")|; \
    s|end_hour *=.*| end_hour = $(repeat "0,")|" \
    "${WRFdir}/namelist.input"

  srun --cpu-bind=core ./${WRFdir}/real.exe
  #sbatch ${WRFdir}/run_real.sh 
  #sleep 10s
  #exit
fi


