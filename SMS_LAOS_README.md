# SMS-LAOS MATLAB Script Manual

## Overview

This script processes `.dat` files for SMS-LAOS analysis and outputs harmonic and intracycle measures, including:

* `I1`, `I3`, `I3/I1`
* `delta1`, `delta3`
* `G'1`, `G''1`, `G'3`, `G''3`
* `e1`, `e3`, `v1`, `v3`
* `e3/e1`, `v3/v1`
* `G\_M\_prime`, `G\_L\_prime`, `S`
* `eta\_M\_prime`, `eta\_L\_prime`, `T`

It can also save plots and selected-cycle CSV files.

\---

## License

Copyright (c) 2026 Yuchen Sun. All rights reserved.

This repository is made available for viewing and academic reference only. Reuse, redistribution, modification, or commercial use is not permitted without prior written permission.

\---

## Input data format

Each input `.dat` file should contain at least 3 numeric columns:

1. `Time`
2. `Strain`
3. `Stress`

The script uses only the first 3 columns.

If the strain column is stored as percent, set:

```matlab
strain\_is\_percent = true;
```

If the strain column is already decimal strain, set:

```matlab
strain\_is\_percent = false;
```

\---

## Main workflow

The script does the following:

1. Reads all `.dat` files in the selected folder
2. Detects the fundamental frequency from the strain signal
3. Selects cycles according to the chosen mode
4. Performs FFT on the selected data
5. Extracts 1st and 3rd harmonic quantities
6. Applies the selected odd-harmonic sign convention
7. Computes SMS-LAOS quantities
8. Saves results to CSV / Excel
9. Optionally saves plots and selected-cycle data

\---

## User settings

### 1\. Input folder

Set the folder containing your `.dat` files:

```matlab
folder\_path = 'C:\\your\\path\\to\\data';
```

\---

### 2\. Fast mode

```matlab
fast\_mode = true;
```

* `true`: faster run, only main CSV output
* `false`: saves plots, `.fig`, selected-cycle CSV, Excel

\---

### 3\. Cycle selection mode

Two options are available:

#### Option A: remove cycles from both ends

```matlab
cycle\_selection\_mode = 'trim\_ends';
remove\_first\_cycles = 3;
remove\_last\_cycles  = 3;
```

This removes the first and last specified cycles and keeps the middle complete cycles.

#### Option B: use only the last N cycles

```matlab
cycle\_selection\_mode = 'last\_n\_cycles';
last\_n\_cycles = 5;
```

This keeps only the last complete cycles.

\---

### 4\. Frequency search range

If you want to restrict automatic frequency detection:

```matlab
use\_freq\_range = true;
freq\_min = 0.01;
freq\_max = 10;
```

If not needed:

```matlab
use\_freq\_range = false;
```

\---

### 5\. Alternating odd-harmonic sign prefactor

```matlab
use\_alternating\_odd\_sign = true;
```

This applies the prefactor:

```text
(-1)^((n-1)/2)
```

For odd harmonics:

* `n = 1` -> `+1`
* `n = 3` -> `-1`

In the current script this prefactor is applied at the Fourier coefficient level while keeping the mapping:

* `e3 = -Gp3`
* `v3 =  Gpp3 / omega`

\---

## Output files

### Main results

Depending on mode:

* `SMS\_LAOS\_results\_fast.csv`
* `SMS\_LAOS\_results\_full.csv`
* `SMS\_LAOS\_results\_full.xlsx`

### Plot folder

If enabled:

* `SMS\_LAOS\_Plots\\`

Contains:

* individual sample PNG files
* optional `.fig` files
* summary plot

### Selected-cycle data folder

If enabled:

* `SMS\_LAOS\_SelectedCSV\\`

Contains:

* `\*\_selected\_cycles.csv`

\---

## Meaning of key outputs

### Harmonic quantities

* `I1`, `I3`: 1st and 3rd harmonic amplitudes of stress
* `I3/I1`: nonlinear harmonic ratio
* `delta1`, `delta3`: phase differences

### Fourier quantities

* `G'1`, `G''1`
* `G'3`, `G''3`

### SMS-LAOS quantities

* `e1`, `e3`
* `v1`, `v3`

### Intracycle elastic measures

* `G\_M\_prime`: minimum-strain modulus
* `G\_L\_prime`: large-strain modulus
* `S = (G\_L\_prime - G\_M\_prime) / G\_L\_prime`

Interpretation:

* `S > 0`: intracycle strain stiffening
* `S < 0`: intracycle strain softening

### Intracycle viscous measures

* `eta\_M\_prime`: minimum-rate viscosity
* `eta\_L\_prime`: large-rate viscosity
* `T = (eta\_L\_prime - eta\_M\_prime) / eta\_L\_prime`

Interpretation:

* `T > 0`: intracycle shear thickening
* `T < 0`: intracycle shear thinning

\---

## Plot content

Each plot can include:

* Raw strain with selected region
* Raw stress with selected region
* Selected strain vs time
* Selected stress vs time
* Stress-strain Lissajous
* Strain FFT
* Stress FFT
* Parameter summary

The summary section includes:

* `e1`, `e3`, `v1`, `v3`
* `G'1`, `G''1`, `G'3`, `G''3`
* `S`, `T`
* `G\_M\_prime`, `G\_L\_prime`

\---

## Recommended usage

### For fast batch processing

Use:

```matlab
fast\_mode = true;
```

### For detailed checking

Use:

```matlab
fast\_mode = false;
```

This is useful when you want to inspect:

* selected cycle ranges
* FFT quality
* Lissajous curves
* summary plots

\---

## Suggested validation steps

For a new dataset, check:

1. Is the detected frequency reasonable?
2. Is the selected cycle range correct?
3. Does the Lissajous mapping agree with:

   * `e3` / `S` on the elastic side?
   * `v3` / `T` on the viscous side?
4. Does `I3/I1` increase with stronger nonlinearity as expected?

\---

## Common issues

### No files found

Check:

* folder path
* file extension
* whether files are really `.dat`

### Wrong modulus scale

Check:

```matlab
strain\_is\_percent = true/false
```

### Wrong frequency

Use:

```matlab
use\_freq\_range = true;
```

### Output file cannot be saved

Usually this means:

* the CSV or Excel file is already open
* you do not have permission to write to the folder

\---

## References

Klein et al., Macromolecules 40, 4250–4259 (2007) — Wilhelm-linked FT-rheology / nonlinear decomposition.

Cho et al., J. Rheol. 49, 747–758 (2005) — stress decomposition.

Ewoldt et al., J. Rheol. 52, 1427–1458 (2008) — e3/v3, G'\_M/G'\_L, η'\_M/η'\_L, S/T.

Ewoldt et al., Rheol. Acta 49, 191–212 (2010) — extended LAOS application.

Hyun et al., Prog. Polym. Sci. 36, 1697–1753 (2011) — the main review.

Mermet-Guyennet et al., J. Rheol. 59, 21–32 (2015) — strain softening / hardening paradox discussion.

Xia et al., ACS Sustainable Chem. Eng. 2023, 11, 50, 17857–17869

Sun et al., POLYMER, 341 (2025) 129299



\---

\---

## Version note

This manual corresponds to the SMS-LAOS script version with:

* SMS\_LAOS naming
* cycle selection mode
* odd-harmonic prefactor option
* e1/e3/v1/v3 shown in plot summaries



