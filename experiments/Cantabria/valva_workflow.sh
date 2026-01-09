#!/bin/bash
#SBATCH --job-name=WPS
#SBATCH --output=wps_%j.out
#SBATCH --error=wps_%j.error
#SBATCH --ntasks=32
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --mem=256G
##SBATCH --mem-per-cpu=256G
#SBATCH --qos=main
#SBATCH --hint=nomultithread
#SBATCH --partition=wncompute_meteo

date
source $HOME/.bashrc

rm *.log

tar xzvf WPS.tar.gz
cd WPS

# Copy geo files
cp ../*.nc .

# Copy namelist
cp ../namelist.wps_cantabria namelist.wps
cp ../namelist.input_cantabria namelist.input


export ERA5dir="/gpfs/projects/meteo/WORK/josipa/CMIP6toWRF/ERA5_forcing/ERA5/data/EUR/"
export RUNDIR="/gpfs/users/milovacj/valva/Cantabria"
source ../../../preprocess/loadenv.UCAN-IFCA_WRF.ini 

#if [ 1 -eq 0 ]; then
year=2000
#pre_year=$((year - 1))
#next_year=$((year + 1))

ln -sf ungrib/Variable_Tables/Vtable.ERA-interim.pl Vtable
./link_grib.csh ${ERA5dir}/${year}/*11*.grib
# Whole years
#./link_grib.csh ${ERA5dir}/${pre_year}/*${pre_year}12*.grib ${ERA5dir}/${year}/*.grib ${ERA5dir}/${next_year}/*${next_year}01*.grib
echo "Running ungrib"
./ungrib.exe
echo "Running metgrid"
srun --cpu-bind=core ./metgrid.exe

# Copy and run tavg_sfc_with_nco
cp ../../../preprocess/tavg_sfc_with_nco.py .

conda activate NCLtoPY                                                                                # Loda conda enviroment with cdo and nco
python tavg_sfc_with_nco.py "met_em*d01*" # Run postprocessing for lake temperature (running mean of 15 days)
python tavg_sfc_with_nco.py "met_em*d02*" # Run postprocessing for lake temperature (running mean of 15 days)
python tavg_sfc_with_nco.py "met_em*d03*" # Run postprocessing for lake temperature (running mean of 15 days)
conda deactivate NCLtoPY
#fi

cd ../

tar xzvf WRF.tar.gz
cp namelist.input_cantabria WRF/run/namelist.input
cd WRF/run
ln -s CAMtr_volume_mixing_ratio.SSP370 CAMtr_volume_mixing_ratio
ln -sf ../../WPS/met_em.d0*.nc .
srun --cpu-bind=core ./real.exe
mkdir real_out
mv rsl.out* rsl.err* real_out
srun --cpu-bind=core ./wrf.exe
date
