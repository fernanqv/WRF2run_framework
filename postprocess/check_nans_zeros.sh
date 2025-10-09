#!/bin/bash
#SBATCH --job-name=checksum
#SBATCH --output=checksum%j.out
#SBATCH --error=checksum%j.error
#SBATCH --ntasks=1
#SBATCH --qos=meteo_high
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=720:00:00
#SBATCH --mem=12G
#SBATCH --hint=nomultithread
#SBATCH --mail-type=all 
#SBATCH --mail-user=milovacj@unican.es
#SBATCH --partition=wncompute_meteo
##SBATCH --nodelist=wncompute051

source ~/.bashrc
conda activate NCLtoPY

# Check if no arguments are given
if [[ $# -eq 0 ]]; then
    echo "Warning: Argument is missing."
    echo "Please provide at least domain and optionally year as an argument."
    exit 1
fi

# Set enviromental variables
export domain=$1
export year=${2:-""}    # Year to check
export path="../../data/postprocessed/I4C/CMIP6/DD/${domain}/"   # Base directory path

# Log files
export logfile="files_corrupted_${domain}.log"
export checked_files="checked_files.txt"
[ ! -f "$checked_files" ] && touch "$checked_files"
[ ! -f "$logfile" ] && touch "$logfile"

# Find all .nc files modified before today (-mtime +0) for a given year (if given, else all years checked)
find $path -type f -name "*_$year*.nc" | while read -r file; do
#find $path -type f -mtime +0 -name "*_$year*.nc" | while read -r file; do
    basename_file=$(basename "$file")
    echo $basename_file
    # Check if the file's basename is already in the checked_files
    if grep -Fxq "$basename_file" "$checked_files"; then
        echo "Skipping $basename_file (already checked)"
        sed -i "/$basename_file/d" "$logfile"
    else
        # Check if the file contains NaN values using cdo
        if cdo -s info "$file" | grep -q nan; then
            # If NaN values are found, log it to logfile with jobid
            sed -i "/$basename_file/d" "$logfile"
            echo "$basename_file has NaN values!" | tee -a "$logfile"

        # Check if all lines with data have 0.0000 for Minimum, Mean, and Maximum
        elif cdo info $file | tail -n +2 | head -n -1 | awk '{if (($9 != "0.0000" || $10 != "0.0000" || $11 != "0.0000")) exit 1}' && [[ "$file" != *_fx* ]] ; then
            sed -i "/$basename_file/d" "$logfile"
            echo "$basename_file is filled with zeros" | tee -a "$logfile"         

        # Check if file is for fixed variable, then no need to cut the last line
        elif cdo info $file | tail -n +2 | awk '{if (($9 != "0.0000" || $10 != "0.0000" || $11 != "0.0000")) exit 1}' && [[ "$file" == *_fx* ]] ; then
            sed -i "/$basename_file/d" "$logfile"
            echo "$basename_file is filled with zeros" | tee -a "$logfile" 

        else
            # If no NaN and no all zero values, remove from logfile (if present) and write to $checked_files
            sed -i "/$basename_file/d" "$logfile"
            echo "$basename_file" | tee -a "$checked_files"
        fi
    fi
done

# Remove duplicates in logfile if any
#sort $logfile | uniq > temp.txt && mv temp.txt $logfile

# Send the email with the info:
email="milovacj@unican.es" 
subject="[IFCA_info]:Postprocessed files checked for $domain ${year:+Year: $year}"
body="The postprocessed files checked for the domain $domain ${year:+Year: $year}.\n\nHere is the list of corrupted files:\n"

# Append the content of logfile to the email body
if [[ -s "$logfile" ]]; then
    body+=$(cat "$logfile")
else
    body+="No corrupted files found!"
fi

# Send email
echo -e "$body" | mail -s "$subject" "$email"


