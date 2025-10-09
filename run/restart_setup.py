#################################################################################################
# This script prepares files to restart WRF:
# 1. Updates the namelist.input according to the most recent wrfrst file available in the 
#			running directory.
# 2. Updates AOD (Aerosol Optical Depth) files according to the most recent wrfrst file, as WRF 
#			cannot recognize timestamps in the AOD files, AND reads the AOD files consecutively  
#			from the 1st timestep.
# 3. Updates CO2 (Carbon Dioxide) concentration in the MPTABLE according to the year obtained 
#			from the most recent restart file.
#
# To run the script:
# 		python wrf2restart_setup.py <NDOMAINS>
#################################################################################################

import re
import os
import sys
import netCDF4 as nc
import numpy as np
import subprocess
import glob
import calendar
from datetime import datetime, timedelta
from warnings import filterwarnings
filterwarnings(action='ignore', category=DeprecationWarning, message='`np.bool` is a deprecated alias')

#################################################################################################
# Reading given argument for the number of domains NDOMAINS
#################################################################################################

if len(sys.argv) < 2:
    NDOMAINS = 1
    print("Usage: python script.py <NDOMAINS>")
    print("If no argument, NDOMAINS=1!")
else: 
    NDOMAINS = int(sys.argv[1])

#################################################################################################
# Set the env variables (Check if something to be changed, e.g. AOD initial date, or GHG file)
#################################################################################################

FOLDER_PATH = './'
PATTERN = f'wrfrst_d01'
NAMELIST = 'namelist.input'
AOD_DIR = '/gpfs/projects/meteo/WORK/ASNA/projects/impetus/02_I4C_evaluation/data/input/AOD_files/evaluation/'
AOD_START = '1998-01-01' # AOD initial date; format: yyyy-mm-dd#
GHG_FILE = './CAMtr_volume_mixing_ratio.SSP370'

#################################################################################################
# Predefined functions:
#################################################################################################

def extract_date_from_filename(filename, pattern):
    match = re.search(pattern, filename)
    return match.group(1) if match else None

def day_in_year(date_str):
    return datetime.strptime(date_str, "%Y-%m-%d").timetuple().tm_yday

def ndays_per_year(year):
    return 366 if calendar.isleap(year) else 365

def read_lines_from_file(file_path):
    with open(file_path, 'r') as file:
        return file.readlines()

def write_lines_to_file(file_path, lines):
    with open(file_path, 'w') as file:
        file.writelines(lines)
        
def is_netcdf_file_complete(file_path):
    try:
        with nc.Dataset(file_path, 'r') as ncfile:
            # If the file can be opened without errors, it's considered complete
            return True
    except FileNotFoundError:
        print(f"The NetCDF file '{file_path}' does not exist.")
        return False
    except Exception as e:
        print(f"An error occurred while opening the file '{file_path}': {e}")
        return False
    
def generate_repeated_dates(date, ndomains):
    return ', '.join([str(date)] * ndomains)

def extract_multiple_values(line):
    values = line.split('=')[1].strip().rstrip(',').split(',')
    return [int(value.strip()) for value in values]

#################################################################################################
# Extract start date from the latest restart files or from the namelist.input, and update 
# the namelist.input if necessary
#################################################################################################

nc_files = [file for file in os.listdir(FOLDER_PATH) if file.startswith(PATTERN)]

if nc_files:
    print(f"Reading start date from the restart file:")
    nc_files.sort(key=lambda x: os.path.getctime(os.path.join(FOLDER_PATH, x)), reverse=True)
    latest_nc_files = nc_files[:2]
    dates = [extract_date_from_filename(file, r"(\d{4}-\d{2}-\d{2})") for file in latest_nc_files]
    
    if is_netcdf_file_complete(latest_nc_files[0]):
        date=dates[0]
    elif len(latest_nc_files) < 2:
        print(f'The restart date cannot be extracted from a restart file, the file is not complete. Exiting...')
        sys.exit()
    else:
        date=dates[1]
                        
    restart_date = datetime.strptime(date, "%Y-%m-%d")       
    
    print(f"  Restart date is: {restart_date.strftime('%Y-%m-%d')}")
    
    # Update restart dates in the namelist
    lines = read_lines_from_file(NAMELIST)
    for i, line in enumerate(lines):
        if "start_year" in line:
            lines[i] = f" start_year                          = {generate_repeated_dates(restart_date.year, NDOMAINS)},\n"
        elif "start_month" in line:
            lines[i] = f" start_month                         = {generate_repeated_dates(f'{restart_date.month:02d}', NDOMAINS)},\n"
        elif "start_day" in line:
            lines[i] = f" start_day                           = {generate_repeated_dates(f'{restart_date.day:02d}', NDOMAINS)},\n"
        elif "end_year" in line:
            lines[i] = f" end_year                            = {generate_repeated_dates(restart_date.year + 1, NDOMAINS)},\n"
        #elif "end_month" in line:
        #    lines[i] = f" end_month                           = {generate_repeated_dates(f'{restart_date.month:02d}', NDOMAINS)},\n"
        #elif "end_day" in line:
        #    lines[i] = f" end_day                             = {generate_repeated_dates(f'{restart_date.day:02d}', NDOMAINS)},\n"
        elif "restart" in line and "false" in line:
            lines[i] = f" restart                             = .true.,\n"

    write_lines_to_file(NAMELIST, lines)

else:
    print(f"  No valid restart file found. Reading from namelist.")

    # Extract initial date from namelist
    lines = read_lines_from_file(NAMELIST)
    date_format = "%Y-%m-%d"

    for i, line in enumerate(lines):
        if "start_year" in line:
            years = extract_multiple_values(line)[0]
        elif "start_month" in line:
            months = extract_multiple_values(line)[0]
        elif "start_day" in line:
            days = extract_multiple_values(line)[0]
    
    restart_date = datetime(years, months, days)
    print(f'  Initial date read from namelist.input is: {restart_date.strftime("%Y-%m-%d")}')
    

################################################################################################  
# Extract correct AOD files from the complete list of yearly AOD files in WRF/run directory
#################################################################################################

print(f'Updating AOD files:')
for N in np.arange(1,NDOMAINS+1):
    DOMAIN=f'd0{N}'
    print(f'  Working on the domain {DOMAIN}:')
    output_file = f'AOD_{DOMAIN}'

    if os.path.exists(output_file):
        os.remove(output_file)

    if os.path.exists(f'merged_{DOMAIN}.nc'):
        os.remove(f'merged_{DOMAIN}.nc')
        
    file1 = glob.glob(os.path.join(f'{AOD_DIR}/', f'AOD*_{restart_date.year}*{DOMAIN}*'))
    file2 = glob.glob(os.path.join(f'{AOD_DIR}/', f'AOD*_{restart_date.year+1}*{DOMAIN}*'))
    print(file1)
    print(file2)

    if file1:
        start_time = restart_date.strftime('%Y-%m-%d')

        if AOD_START and AOD_START[0:4] == str(restart_date.year):
                start_timestep = day_in_year(start_time) - day_in_year(AOD_START)
                print(start_timestep)
                print(day_in_year(start_time))
                print(AOD_START)
                print(day_in_year(AOD_START))
        else:
            start_timestep = day_in_year(start_time) - 1
            print(start_time)
            print(start_timestep)
            
        if file1 and file2:
            try:
                subprocess.run([f'ncrcat {file1[0]} {file2[0]} merged_{DOMAIN}.nc'], check=True, shell=True)                
                
            except subprocess.CalledProcessError as e:
                print(f'    Command failed with return code {e.returncode}')

        elif file1 and not file2:
            try:
                subprocess.run([f'cp {file1[0]} merged_{DOMAIN}.nc'], check=True, shell=True)
            except subprocess.CalledProcessError as e:
                print(f'    Command failed with return code {e.returncode}')
            
        nc_aod = nc.Dataset(f'merged_{DOMAIN}.nc', 'r')
        last_timestep = len(nc_aod.dimensions['Time'])-1
        last_date_bytes = nc_aod.variables['Times'][last_timestep].tobytes()
        last_date = last_date_bytes.decode('utf-8')[:10]
        
          
        try:
            subprocess.run(['ncks', '-d', 'Time,{},{}'.format(start_timestep, last_timestep), f'merged_{DOMAIN}.nc', output_file], check=True)
            subprocess.run(['rm', f'merged_{DOMAIN}.nc'], check=True)
            print(f'    {output_file} from {start_time} until {last_date} successfully created!')
        except subprocess.CalledProcessError as e:
            print(f'    Command failed with return code {e.returncode}')        

    else:
        print(f'    AOD files for the year {restart_date.year} are missing. Provide the files and rerun the script!')
    
    
#################################################################################################
# Update MPTABLE
#################################################################################################

print(f'Updating MPTABLE:')
mptable = './MPTABLE.TBL'
target_string = "!co2 partial pressure"

# Extract target year from namelist.input
with open("./namelist.input", 'r') as file:
    target_year = int(file.read().split('start_year')[1].split('=')[1].split(',')[0])

# Extract CO2 value from ghg_file for the target year
lines = read_lines_from_file(GHG_FILE)
for line in lines:
    if line.startswith(f'{target_year}'):
        CO2_update = line.split()[1]

# Update MPTABLE with the new CO2 value
lines = read_lines_from_file(mptable)
for i, line in enumerate(lines):
    if target_string in line:
        lines[i] = f'  CO2 = {CO2_update}e-06 !co2 partial pressure \n'
        print(f'  CO2 in the MPTABLE.TBL updated for the year {target_year}, set to {CO2_update}.')        
write_lines_to_file(mptable,lines)
