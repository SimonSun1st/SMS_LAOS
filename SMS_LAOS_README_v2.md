# SMS-LAOS MATLAB Script Manual

## Overview

This MATLAB script processes `.dat` files for Large Amplitude Oscillatin Shear (LAOS) analysis and outputs Fourier Transform rheology and stress-decomposition results.

The script is designed for LAOS data where each file contains time, strain, and stress columns. It automatically detects the fundamental frequency, selects steady cycles, performs Fourier analysis, calculates SMS-LAOS parameters, and optionally saves plots and selected-cycle data.

The script outputs:

- `I1`, `I3`, `I3/I1`
- `delta1`, `delta3`
- `G'1`, `G''1`, `G'3`, `G''3`
- `e1`, `e3`, `v1`, `v3`
- `e3/e1`, `v3/v1`
- `G_M_prime`, `G_L_prime`, `S`
- `eta_M_prime`, `eta_L_prime`, `T`
- elastic Lissajous stress
- viscous Lissajous stress
- reconstructed total stress

The stress-decomposition output allows the total LAOS response to be separated into elastic and viscous contributions, which helps visualize intracycle strain stiffening/softening and shear thickening/thinning behavior.

---

## License

Copyright (c) 2026 Yuchen Sun. All rights reserved.

This repository is made available for viewing and academic reference only. Reuse, redistribution, modification, or commercial use is not permitted without prior written permission from the author.

---

## Input data format

Each input `.dat` file should contain at least 3 numeric columns:

1. `Time`
2. `Strain`
3. `Stress`

The script uses only the first 3 numeric columns.

If the strain column is stored as percent, for example `50` means 50%, set:

```matlab
strain_is_percent = true;
```

If the strain column is already decimal strain, for example `0.5` means 50%, set:

```matlab
strain_is_percent = false;
```

---

## Main workflow

The script follows this workflow:

1. Reads all `.dat` files in the selected folder
2. Detects the fundamental frequency from the strain signal
3. Selects steady cycles using the chosen cycle-selection mode
4. Performs FFT on the selected data
5. Extracts first and third harmonic quantities
6. Applies the selected odd-harmonic sign convention
7. Calculates SMS-LAOS Chebyshev parameters
8. Calculates intracycle elastic and viscous measures
9. Reconstructs elastic and viscous stress contributions
10. Saves result tables
11. Optionally saves plots and selected-cycle CSV files

---

## User settings

### 1. Input folder

Set the folder containing your `.dat` files:

```matlab
folder_path = 'C:\your\path\to\data';
```

Only `.dat` files in this folder are processed.

---

### 2. Fast mode

```matlab
fast_mode = true;
```

Options:

- `true`: faster batch processing; saves only the main CSV output
- `false`: saves plots, `.fig` files, selected-cycle CSV files, Excel output, and CSV output

Use `fast_mode = true` when processing many files quickly.

Use `fast_mode = false` when checking new datasets or inspecting plots.

---

### 3. Cycle selection mode

Two cycle-selection modes are available.

#### Option A: remove cycles from both ends

```matlab
cycle_selection_mode = 'trim_ends';
remove_first_cycles = 3;
remove_last_cycles  = 3;
```

This removes the specified number of cycles from the beginning and end of the signal, then keeps the middle complete cycles.

This mode is useful when the first few cycles contain transient behavior and the final cycles may contain end effects.

#### Option B: use only the last N cycles

```matlab
cycle_selection_mode = 'last_n_cycles';
last_n_cycles = 5;
```

This keeps only the last complete cycles.

This mode is useful when the response gradually reaches a steady state and the final cycles are expected to be most representative.

---

### 4. Frequency search range

The script automatically detects the fundamental frequency from the strain signal.

If you want to restrict the frequency search range, use:

```matlab
use_freq_range = true;
freq_min = 0.01;
freq_max = 10;
```

If this restriction is not needed, use:

```matlab
use_freq_range = false;
```

A restricted frequency range can help avoid incorrect frequency detection when the raw data contain noise, drift, or unwanted low-frequency components.

---

### 5. Alternating odd-harmonic sign prefactor

```matlab
use_alternating_odd_sign = true;
```

This applies the odd-harmonic prefactor:

```text
(-1)^((n-1)/2)
```

For odd harmonics:

```text
n = 1  ->  +1
n = 3  ->  -1
```

In the current script, this prefactor is applied at the Fourier coefficient level while keeping the mapping:

```matlab
e3 = -Gp3;
v3 =  Gpp3 / omega;
```

This convention is used consistently in the SMS-LAOS calculations and the elastic/viscous stress reconstruction.

---

## Output files

### Main result files

Depending on the selected mode, the script saves:

```text
SMS_LAOS_results_fast.csv
SMS_LAOS_results_full.csv
SMS_LAOS_results_full.xlsx
```

The main result table contains the harmonic, phase, Fourier, Chebyshev, and intracycle quantities for each processed `.dat` file.

---

### Plot folder

If plot saving is enabled, the script creates:

```text
SMS_LAOS_Plots\
```

This folder contains:

- individual sample PNG plots
- optional MATLAB `.fig` files
- summary plots

---

### Selected-cycle data folder

If selected-cycle CSV export is enabled, the script creates:

```text
SMS_LAOS_SelectedCSV\
```

This folder contains files named:

```text
*_selected_cycles.csv
```

Each file contains the selected steady-cycle data and the reconstructed stress components.

---

## Main result table columns

The main result table includes:

```text
Filename
Detected Frequency (Hz)
Angular Frequency (rad/s)
Cycles Used
I1 (Pa)
I3 (Pa)
I3/I1
delta1 (rad)
delta3 (rad)
G'1 (Pa)
G''1 (Pa)
G'3 (Pa)
G''3 (Pa)
e1 (Pa)
v1 (Pa.s)
e3 (Pa)
v3 (Pa.s)
e3/e1
v3/v1
G_M_prime (Pa)
G_L_prime (Pa)
S
eta_M_prime (Pa.s)
eta_L_prime (Pa.s)
T
```

---

## Selected-cycle CSV columns

When selected-cycle CSV export is enabled, each selected-cycle file contains:

```text
Time_s
Strain
StrainRate_1_per_s
StrainRate_over_omega
Stress_Total_Pa
Stress_Elastic_Pa
Stress_Viscous_Pa
Stress_Reconstructed_Pa
```

These columns allow the decomposed LAOS response to be replotted or further processed in OriginPro, Excel, Python, MATLAB, or other software.

---

## Meaning of key outputs

### Harmonic quantities

- `I1`: first harmonic stress amplitude
- `I3`: third harmonic stress amplitude
- `I3/I1`: relative third harmonic intensity

`I3/I1` is commonly used as a simple indicator of nonlinear response strength.

---

### Phase quantities

- `delta1`: phase difference of the first harmonic
- `delta3`: phase difference of the third harmonic

These are calculated relative to the strain signal.

---

### Fourier quantities

The script calculates:

- `G'1`, `G''1`
- `G'3`, `G''3`

These correspond to the first and third harmonic elastic and viscous Fourier components under the selected sign convention.

---

### SMS-LAOS Chebyshev quantities

The script calculates:

- `e1`, `e3`
- `v1`, `v3`

The current convention is:

```matlab
e1 = Gp1;
v1 = Gpp1 / omega;

e3 = -Gp3;
v3 =  Gpp3 / omega;
```

The ratios are also calculated:

```text
e3/e1
v3/v1
```

These ratios describe the relative strength of elastic and viscous nonlinearities.

---

## Intracycle elastic measures

The script calculates:

```text
G_M_prime = e1 - 3*e3
G_L_prime = e1 + e3
S = (G_L_prime - G_M_prime) / G_L_prime
```

where:

- `G_M_prime`: minimum-strain modulus
- `G_L_prime`: large-strain modulus
- `S`: intracycle strain-stiffening ratio

Typical interpretation:

- `S > 0`: intracycle strain stiffening
- `S < 0`: intracycle strain softening
- larger `|S|`: stronger intracycle elastic nonlinearity

---

## Intracycle viscous measures

The script calculates:

```text
eta_M_prime = v1 - 3*v3
eta_L_prime = v1 + v3
T = (eta_L_prime - eta_M_prime) / eta_L_prime
```

where:

- `eta_M_prime`: minimum-rate dynamic viscosity
- `eta_L_prime`: large-rate dynamic viscosity
- `T`: intracycle shear-thickening ratio

Typical interpretation:

- `T > 0`: intracycle shear thickening
- `T < 0`: intracycle shear thinning
- larger `|T|`: stronger intracycle viscous nonlinearity

---

## Elastic and viscous Lissajous decomposition

This version adds stress decomposition to the LAOS analysis.

The total stress response is treated as:

```text
sigma_total = sigma_elastic + sigma_viscous
```

The elastic and viscous stresses are reconstructed using the first and third Chebyshev terms.

### Normalized variables

The script calculates strain rate from the selected strain-time data:

```matlab
gammadot = gradient(strain, time);
```

It then defines:

```text
x = gamma / gamma0
y = gammadot / (omega * gamma0)
```

where:

- `gamma`: selected strain signal
- `gamma0`: strain amplitude from FFT
- `gammadot`: strain rate
- `omega`: angular frequency

The script also stores:

```matlab
gammadot_over_omega = gammadot / omega;
```

This variable has the same unit as strain and is used for plotting the viscous Lissajous curve.

---

### Chebyshev basis

The first and third Chebyshev terms are:

```text
T1(x) = x
T3(x) = 4*x^3 - 3*x
```

The same form is used for the viscous variable `y`.

---

### Elastic stress reconstruction

The elastic stress is reconstructed as:

```text
sigma_elastic = gamma0 * [e1*T1(x) + e3*T3(x)]
```

In MATLAB:

```matlab
stress_elastic = gamma0 * (e1*T1x + e3*T3x);
```

This represents the part of the LAOS stress associated with strain.

The elastic Lissajous curve is plotted as:

```text
sigma_elastic vs strain
```

This curve helps visualize intracycle elastic nonlinearity.

---

### Viscous stress reconstruction

The viscous stress is reconstructed as:

```text
sigma_viscous = gamma0*omega * [v1*T1(y) + v3*T3(y)]
```

In MATLAB:

```matlab
stress_viscous = gamma0 * omega * (v1*T1y + v3*T3y);
```

This represents the part of the LAOS stress associated with strain rate.

The viscous Lissajous curve is plotted as:

```text
sigma_viscous vs gammadot/omega
```

This curve helps visualize intracycle dissipative nonlinearity.

---

### Reconstructed total stress

The reconstructed total stress is calculated as:

```matlab
stress_reconstructed = stress_elastic + stress_viscous;
```

This is used as a quality check.

If the reconstructed stress closely follows the selected raw stress signal, the first and third harmonic approximation is reasonable.

If the difference is large, higher harmonics such as the 5th, 7th, or higher terms may be important.

---

## Plot content

Each individual sample plot can include:

1. Raw strain with selected region
2. Raw stress with selected region
3. Selected strain vs time
4. Selected stress vs time
5. Total stress-strain Lissajous curve
6. Strain FFT
7. Stress FFT
8. Parameter summary
9. Elastic Lissajous curve
10. Viscous Lissajous curve
11. Total stress vs reconstructed stress
12. Raw vs reconstructed Lissajous curve

---

## Plot interpretation

### Total stress-strain Lissajous curve

```text
stress_total vs strain
```

This shows the measured LAOS response before stress decomposition.

A more distorted or non-elliptical shape usually indicates stronger nonlinear behavior.

---

### Elastic Lissajous curve

```text
stress_elastic vs strain
```

This shows the elastic contribution to the LAOS response.

Useful checks:

- Does the curve show stiffening at high strain?
- Does the trend agree with `S`?
- Does the trend agree with `e3/e1`?

Typical interpretation:

- stronger curvature indicates stronger elastic nonlinearity
- upward stiffening at large strain is associated with intracycle strain stiffening
- reduced slope at large strain is associated with intracycle strain softening

---

### Viscous Lissajous curve

```text
stress_viscous vs gammadot/omega
```

This shows the viscous contribution to the LAOS response.

Useful checks:

- Does the curve show thickening at high strain rate?
- Does the trend agree with `T`?
- Does the trend agree with `v3/v1`?

Typical interpretation:

- stronger curvature indicates stronger viscous nonlinearity
- increased slope at high rate is associated with intracycle shear thickening
- reduced slope at high rate is associated with intracycle shear thinning

---

### Total stress vs reconstructed stress

```text
raw selected stress vs stress_reconstructed
```

This plot checks whether the reconstructed elastic + viscous stress captures the measured stress signal in the time domain.

Good overlap suggests that the first and third harmonic approximation is sufficient.

Poor overlap suggests that higher harmonics should be considered.

---

### Raw vs reconstructed Lissajous curve

```text
raw total stress-strain Lissajous
reconstructed stress-strain Lissajous
```

This plot checks whether the reconstructed response captures the overall measured Lissajous shape.

---

## Recommended usage

### For fast batch processing

Use:

```matlab
fast_mode = true;
```

This is recommended when processing many files and only the main numerical output is required.

---

### For detailed checking

Use:

```matlab
fast_mode = false;
```

This is recommended when working with new datasets or when you want to inspect:

- selected cycle ranges
- FFT quality
- total Lissajous curves
- elastic Lissajous curves
- viscous Lissajous curves
- reconstructed stress quality
- summary plots

---

## Suggested validation steps

For a new dataset, check:

1. Is the detected frequency reasonable?
2. Is the selected cycle range correct?
3. Does the raw stress-strain Lissajous curve look physically reasonable?
4. Does the reconstructed stress overlap well with the selected raw stress?
5. Does the elastic Lissajous trend agree with `S` and `e3/e1`?
6. Does the viscous Lissajous trend agree with `T` and `v3/v1`?
7. Does `I3/I1` increase with stronger nonlinearity as expected?
8. If reconstruction is poor, consider including higher harmonics.

---

## Common issues

### No files found

Check:

- folder path
- file extension
- whether files are really `.dat`
- whether the files are in the selected folder rather than a subfolder

---

### Wrong modulus scale

Check whether the strain input is percent or decimal strain.

```matlab
strain_is_percent = true;
```

Use this if the strain column is stored as percent.

```matlab
strain_is_percent = false;
```

Use this if the strain column is already decimal strain.

---

### Wrong frequency detection

Use a restricted frequency search range:

```matlab
use_freq_range = true;
freq_min = 0.01;
freq_max = 10;
```

Also check whether the strain signal contains drift, noise, or incomplete cycles.

---

### Selected cycles look wrong

Try adjusting:

```matlab
remove_first_cycles
remove_last_cycles
last_n_cycles
```

If the early part contains transient behavior, use `trim_ends`.

If the response becomes steady only near the end, use `last_n_cycles`.

---

### Reconstructed stress does not match raw stress

Possible reasons:

- higher harmonics are significant
- selected cycles are not steady
- frequency detection is incorrect
- strain-rate calculation is noisy
- the first and third harmonic approximation is insufficient

For strongly nonlinear LAOS data, the decomposition may need to include higher odd harmonics:

```text
n = 5, 7, 9, ...
```

---

### Output file cannot be saved

This usually means:

- the CSV or Excel file is already open
- MATLAB does not have permission to write to the folder
- the output folder is read-only

Close the output file and rerun the script.

---

## Important notes

### 1. The decomposition follows the current sign convention

The script keeps the convention:

```matlab
e3 = -Gp3;
v3 =  Gpp3 / omega;
```

Therefore, `e3` and `v3` are used directly in the elastic and viscous stress reconstruction.

Do not add an additional negative sign to `e3` during reconstruction.

---

### 2. The current reconstruction uses only the first and third harmonics

The current decomposition uses:

```text
n = 1 and n = 3
```

This is suitable for weak-to-moderate nonlinear LAOS responses.

For strongly nonlinear responses, higher odd harmonics may become important.

---

### 3. Use selected steady cycles

The decomposition should be applied to selected steady-state cycles rather than the full raw signal.

The recommended workflow is:

```text
read raw data
detect frequency
select steady cycles
calculate FFT
extract harmonic coefficients
calculate SMS-LAOS parameters
reconstruct elastic and viscous stresses
plot total, elastic, viscous, and reconstructed Lissajous curves
```

---

### 4. Interpret visual plots together with numerical parameters

The elastic and viscous Lissajous curves are visual aids.

They should be interpreted together with:

```text
e3/e1
v3/v1
S
T
G_M_prime
G_L_prime
eta_M_prime
eta_L_prime
```

This is especially important when comparing different rubber networks, formulations, filler systems, or strain amplitudes.

---

## References

Klein et al., Macromolecules 40, 4250–4259 (2007) — Wilhelm-linked FT-rheology / nonlinear decomposition.

Cho et al., J. Rheol. 49, 747–758 (2005) — stress decomposition.

Ewoldt et al., J. Rheol. 52, 1427–1458 (2008) — `e3/v3`, `G'_M/G'_L`, `eta'_M/eta'_L`, `S/T`.

Ewoldt et al., Rheol. Acta 49, 191–212 (2010) — extended LAOS application.

Hyun et al., Prog. Polym. Sci. 36, 1697–1753 (2011) — LAOS review.

Mermet-Guyennet et al., J. Rheol. 59, 21–32 (2015) — strain softening / hardening paradox discussion.

Xia et al., ACS Sustainable Chem. Eng. 2023, 11, 50, 17857–17869.

Sun et al., Polymer, 341 (2025) 129299.

---

## Version note

This README corresponds to the SMS-LAOS script version with:

- SMS_LAOS naming
- fast mode
- cycle-selection mode
- automatic frequency detection
- optional frequency search range
- odd-harmonic sign prefactor option
- `e1/e3/v1/v3` outputs
- `G_M_prime/G_L_prime/S` outputs
- `eta_M_prime/eta_L_prime/T` outputs
- elastic Lissajous reconstruction
- viscous Lissajous reconstruction
- reconstructed total stress output
- expanded selected-cycle CSV output
- additional decomposition plots
