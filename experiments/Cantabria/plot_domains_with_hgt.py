#!/usr/bin/env python
import xarray as xr
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import geopandas as gpd
import matplotlib as mpl

# ---------------------
# USER SETTINGS
# ---------------------
geo_files = ["geo_em.d01.nc", "geo_em.d02.nc", "geo_em.d03.nc"]
buffer_cells = 10
santander_lon, santander_lat = -3.807, 43.462

# ---------------------
# Load Cantabria boundary (GADM Level-1)
# ---------------------
print("Loading Cantabria boundary...")
url = "https://geodata.ucdavis.edu/gadm/gadm4.1/shp/gadm41_ESP_shp.zip"
cantabria = gpd.read_file(url, layer="gadm41_ESP_1")
cantabria = cantabria[cantabria["NAME_1"] == "Cantabria"].to_crs(epsg=4326)

# ---------------------
# Load domains and determine global colormap range
# ---------------------
print("Loading WRF domains...")
datasets = [xr.open_dataset(f) for f in geo_files]

hmin = min(ds["HGT_M"].min().item() for ds in datasets)
hmax = max(ds["HGT_M"].max().item() for ds in datasets)

proj = ccrs.PlateCarree()
fig, ax = plt.subplots(figsize=(14, 12), subplot_kw=dict(projection=proj))

# ---------------------
# Plot terrain from all domains (d01 bottom → d03 top)
# ---------------------
print("Plotting terrain...")
for ds in datasets:
    lat = ds["XLAT_M"].isel(Time=0)
    lon = ds["XLONG_M"].isel(Time=0)
    hgt = ds["HGT_M"].isel(Time=0)

    ax.pcolormesh(lon, lat, hgt, cmap="terrain", shading="auto",
                  vmin=hmin, vmax=hmax, transform=proj)

# Add colorbar
cbar = fig.colorbar(
    plt.cm.ScalarMappable(cmap="terrain", norm=plt.Normalize(hmin, hmax)),
    ax=ax, shrink=0.80, orientation="vertical"
)
cbar.set_label("Terrain Elevation (m)", fontweight='bold')

# ---------------------
# Plot Cantabria boundary
# ---------------------
print("Drawing Cantabria boundary...")
cantabria.boundary.plot(ax=ax, color="black", linewidth=1.2)

# ---------------------
# Plot domain boundaries + relaxation zones
# ---------------------
print("Drawing domain boundaries...")
colors = ["red", "orange", "white"]
labels = ["d01", "d02", "d03"]

for ds, color, label in zip(datasets, colors, labels):
    lat = ds["XLAT_M"].isel(Time=0)
    lon = ds["XLONG_M"].isel(Time=0)

    # Domain outer boundary
    ax.plot(lon[0, :], lat[0, :], color=color, linewidth=2, transform=proj)
    ax.plot(lon[-1, :], lat[-1, :], color=color, linewidth=2, transform=proj)
    ax.plot(lon[:, 0], lat[:, 0], color=color, linewidth=2, transform=proj)
    ax.plot(lon[:, -1], lat[:, -1], color=color, linewidth=2, transform=proj)

    # Relaxation boundary (dashed inner)
    ax.plot(lon[buffer_cells, buffer_cells:-buffer_cells],
            lat[buffer_cells, buffer_cells:-buffer_cells],
            "--", color=color, linewidth=1, transform=proj)
    ax.plot(lon[-buffer_cells, buffer_cells:-buffer_cells],
            lat[-buffer_cells, buffer_cells:-buffer_cells],
            "--", color=color, linewidth=1, transform=proj)
    ax.plot(lon[buffer_cells:-buffer_cells, buffer_cells],
            lat[buffer_cells:-buffer_cells, buffer_cells],
            "--", color=color, linewidth=1, transform=proj)
    ax.plot(lon[buffer_cells:-buffer_cells, -buffer_cells],
            lat[buffer_cells:-buffer_cells, -buffer_cells],
            "--", color=color, linewidth=1, transform=proj)

    # Label domain center
    ax.text(float(lon.max()), float(lat.max()), label,
            color=color, fontsize=18, fontweight='bold', transform=proj)

# ---------------------
# Mark Santander
# ---------------------
print("Marking Santander...")
ax.scatter(santander_lon, santander_lat, color='white', s=60, marker='o', transform=proj)
ax.text(santander_lon-0.9, santander_lat + 0.2, "Santander", color='white', transform=proj)

# ---------------------
# Final layout / Save
# ---------------------
ax.coastlines(resolution="10m")
ax.set_title("WRF Domains with Multi-Resolution Terrain, Relaxation Zones & Cantabria", fontsize=16)

output_name = "wrf_domains_multi_res_terrain"
plt.savefig(f"{output_name}.png", dpi=300, bbox_inches="tight")
plt.savefig(f"{output_name}.pdf", dpi=300, bbox_inches="tight")

print(f"\n Saved: {output_name}.png and {output_name}.pdf\n")




