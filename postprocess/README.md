# pCMORizer

**pCMORizer** is used to postprocess WRF output raw file. It is a Fortran-based tool developed by a group of contributors led by **Sebastian Knist** and **Klaus Görgen (k.goergen@fz-juelich.de)**.  
The code extracts and/or calculates (when necessary) variables from raw **WRF** output files (`wrfout`, `wrfpress`, `wrfxtrm`) and produces **CMORized** output aggregated by year, month, or any specified period.

## Features

- Direct extraction and calculation of variables from WRF outputs  
- Generation of CMORized output with:
  - **1-hour**
  - **3-hour**
  - **6-hour**  
  frequency data
- Daily data can be calculated afterward using [**CDO**](https://code.mpimet.mpg.de/projects/cdo) and [**NCO**](https://nco.sourceforge.net/) commands

## Updates and Improvements

Several enhancements have been added to the original code by **Josipa Milovac (milovacj@unican.es)**, which include:

1. Support for different map projections (e.g., **Lambert**, **rotated lat-lon**)
2. Simplified internal processes for better maintainability
3. New variables added to postprocessing
4. Possibility to extract data directly from wrfpress files added
5. Functionality to postprocess static data added
6. Several bugs fixed

All updates have been communicated with **Klaus Görgen**, one of the principal developers and maintainers.

## Access

The code is currently hosted on a **[private GitLab repository](https://icg4geo.icg.kfa-juelich.de/ExternalRepos/pCMORizer/-/tree/josipa?ref_type=heads)**.  
Access is required for future users, and can be granted only by Klaus Görgen via email.

## Reporting Issues

If you encounter any problems or bugs, please **report the issue in the GitLab repository**.  
This helps improve the codebase and supports future development.

---

*Maintained by the pCMORizer development team.*

