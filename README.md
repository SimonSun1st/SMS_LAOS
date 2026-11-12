# SMS-LAOS

SMS-LAOS is an English-language MATLAB app for large-amplitude oscillatory shear (LAOS) measurements. Inspect a strain and stress waveform, run Fourier-transform LAOS (FT-LAOS), stress decomposition (SD) or sequence of physical processes (SPP), and export the results. A single acquisition or a batch can use any combination of the three methods. [中文使用说明](README_ZH.md)

## Launch

Use MATLAB R2026b with Signal Processing Toolbox. Open the project folder that contains `launch_SMS_LAOS.m` as the MATLAB current folder. In the Command Window, run

```matlab
app = launch_SMS_LAOS;
```

To try the workflow, click **Load synthetic demo**, leave all three methods checked and click **Analyze selected**. Existing scripts can continue calling `launch_merged_laos_analysis`.

## Workflow

1. **Load data** or **Add folder**. The shared list supports multiple selection. Removing or clearing entries does not delete source files.
2. Open **Data & units**, select the units and column mapping of the acquisition files, and inspect the measured strain, stress, numerical strain rate, estimated frequency and Lissajous preview. Loading does not run an analysis method.
3. Tick **FT-LAOS**, **Stress decomposition**, **SPP**, or any combination. Each method's settings are on its own tab.
4. Use **Analyze selected** or **Analyze all**. Review each method's status and diagnostics. Stop finishes the current method before stopping subsequent work.
5. Open **Export** to choose the output package, curve CSVs, waveform data, Lissajous figures and image formats. **Export results** saves current results for the checked methods. **Save view** is also on Export.

Selection determines the displayed file and the scope of Analyze selected. Normal result export includes eligible results across the loaded list, not just the highlighted rows. SPP's comparison views use multiple selected files.

When loading a batch, the status bar shows the current file and the selected waveform appears first. **Stop** takes effect between file operations. Once the file list appears, stopping keeps the finished previews and lists the remaining files as **Queued**. Select a queued row to preview that file, or use **Load data** with the same files to finish preparing the batch. During analysis, Stop keeps the results of methods that have finished.

### Reading the file list

| File status | Meaning and next step |
| --- | --- |
| **Waiting** or **Running** | The file is queued for analysis or the named method is running. The progress bar advances after each method returns. The file counter advances after all checked methods have run for that file. |
| **Finished** | All checked methods completed without an automatic quality warning. |
| **Review (SPP)** | The checked methods completed and SPP raised a quality warning. Click anywhere on the row to read the specific reasons below the method status line in the left sidebar. Scroll the reasons if needed. When several methods raise warnings, the row names each of them. |
| **Error** or **Input error** | A calculation or input preview failed. Inspect the method diagnostics or the message on **Data & units**. |
| **Partial** | Some checked methods have results. Select the row and choose **Analyze selected** to run the file again. |

For example, if an SPP warning says that too few consecutive final cycles passed the stationarity check, inspect **SPP → Stationarity** and **Cycle metrics**. The per-cycle results remain available when the stable-cycle average is empty.

## Data & units

The required acquisition channels are **time, strain and stress**. The application derives strain rate, frequency and angular frequency from them. All three methods and the preview use the same input configuration.

If OneDrive shows a file in Finder but its contents have not downloaded, choose **Always Keep on This Device** for the acquisition or sweep folder. Once it is available locally, click **Retry preview** on **Data & units** to reread the selected file. To retry a whole sweep, use **Load data** with the same files again.

| Input quantity | Available units |
| --- | --- |
| Time | s, ms, µs (`us`), min, h |
| Strain | Percent (%), decimal, millistrain, microstrain |
| Stress | Pa, kPa, MPa, mPa, bar, psi, dyn/cm² |

For 1% strain, the equivalent stored values are `1` in percent, `0.01` in decimal, `10` in millistrain or `10000` in microstrain. Stress unit symbols are case-sensitive: **mPa** and **MPa** differ by a factor of one billion.

Configure the time/strain/stress column numbers, header rows, delimiter and Excel sheet on **Data & units**. DAT, CSV, TXT, TSV, XLS and XLSX use this shared mapping for all methods. Input settings initially select columns 1/2/3, seconds, percent strain, Pa, zero explicitly skipped rows and automatic delimiter detection. The settings apply to the whole loaded list, so files in the same batch should use the declared units and layout.

Data are converted for calculation to **seconds, decimal strain and Pa**. Frequency is expressed internally in Hz, angular frequency in rad/s, strain rate in s⁻¹, moduli in Pa and viscosity in Pa·s. Plot axes identify their displayed units; some SPP views use kPa. Original input units, conversion factors, column mapping and source paths are retained in the results and export metadata. Acquisition files are read only.

Changing shared input units or mapping refreshes the preview and makes affected method results stale. Restoring the exact previous configuration can restore a matching cached result. Source freshness uses file size and modification time, not a content hash.

## Method tabs

### FT-LAOS

FT-LAOS has its own cycle-selection, frequency-search and sign-convention settings. Its result area shows **strain and stress spectra, a numerical result table and quality diagnostics**. Harmonic amplitudes and moduli are available in the table and exports.

Frequency-search limits can be displayed in Hz or rad/s. Changing that selector preserves the physical limits; it does not reinterpret the numbers as a different frequency. Programmatic `applySettings` values `freq_min` and `freq_max` are always in Hz.

### Stress decomposition

Stress decomposition has its own cycle selection, frequency search and sign convention. It retains elastic/viscous components, reconstructed stress, residuals, Lissajous curves, Chebyshev coefficients, S/T, batch summaries and diagnostics.

FT-LAOS and stress decomposition use the same established SMS v2 equations, but **their settings, selected windows, result caches and freshness states are independent**. Changing or rerunning one does not change the other. If you need a direct comparison over the same interval, set both methods to the same cycle-selection and frequency-search options.

SMS reconstruction and S/T use the first and third terms only. A lower reconstruction residual does not identify the physical cause of the remaining mismatch.

### SPP

SPP retains **Average response** and **Cycle evolution**, plus cycle metrics, multi-file comparison, Lissajous views, fit-window and smoothing sensitivity, stationarity and quality diagnostics. Import settings and export options are no longer embedded in this method tab.

The manual frequency field accepts Hz or rad/s; blank means automatic estimation. Changing its unit selector preserves the physical frequency. Programmatic `applySettings(struct('Omega',value))` always uses rad/s.

Average response defaults to **Stable final cycles**: the longest passing suffix in the final contiguous block of eligible cycles. Defaults include at least five cycles, 5% bulk tolerance, 25% significant complex-harmonic tolerance and an inclusion floor of 0.1% of I1. These are engineering screening criteria, not confidence intervals. **If no suffix passes, the average stays empty; the application does not silently fall back to another window.** Diagnostics remain available. Manual selection is an explicit alternative.

Cycle evolution retains valid complete cycles by default. It uses actual timestamps, does not force individual loops to close, does not fit across gaps or unselected cycles, and masks points without sufficient support. Average-mode derivative settings do not govern evolution calculations. Per-file elapsed time is not a common loading-onset clock across files.

SPP receives the measured stress signal, not the first-/third-term SMS reconstruction. Even components and higher measured components are not automatically removed. Harmonic maximum order controls descriptive output, not reconstruction truncation.

## Preview and numerical conventions

The preview converts units but retains acquired samples, without phase averaging, smoothing or DC removal. Its strain rate is `gradient(strain,time)`, using time in seconds. Its frequency estimate starts from the dominant strain FFT peak and is refined by a sinusoidal fit at actual timestamps. File strain amplitude is the median half peak-to-peak amplitude of complete estimated periods, or the whole-record half range when no complete period exists.

Preview quantities do not override each analysis engine's own frequency, derivative or cycle-selection rules. The SMS adapter preserves the legacy rule that a NaN in any input column excludes that row. Preview and SPP use their recorded selected-channel/cleaning rules. Extra missing columns can therefore produce different row counts. Inspect variable-amplitude records before treating their median amplitude as one strain level.

Unit conversion involves floating-point rounding. If an SMS time cutoff falls exactly on a sampled timestamp, a rounding difference can include or exclude one boundary sample under the unchanged cropping rule. Equivalent-unit checks therefore use numerical tolerances rather than claiming universal bit-for-bit identity.

## Export

All export controls are on **Export**. They do not change numerical analysis or make calculated results stale.

- **Analysis output package: Full / Fast** controls the native stress-decomposition package. Full includes the original Excel, selected-cycle CSV and PNG/FIG plots. Fast retains summaries and complete MAT results while omitting those heavier outputs.
- **Decomposed curve CSV** is a separate option.
- FT-LAOS exports its numerical summary, harmonic/spectrum CSVs and complete MAT snapshot. SPP exports its complete results, cycle/harmonic tables, available phase data, diagnostics and settings.
- Optional waveform CSVs contain converted time, strain, strain rate and stress.
- Lissajous options and PNG/PDF/FIG choices are grouped here, together with **Save view**.

Only currently checked methods with successful current results enter the analysis output. Pending, failed or stale results remain documented in the status file. Each FT and SD export contains that method's own result and settings. A no-stable-average SPP warning can export diagnostics, without inventing an average curve.

| Output location | Contents |
| --- | --- |
| `FT_LAOS/` | FT MAT snapshots, summary, first-/third-harmonic and spectrum CSVs |
| `Stress_decomposition/` | Independent SD result; native Full/Fast output and optional curve CSV |
| `SPP/` | SPP MAT, cycle/harmonic tables, available phase traces, sensitivity and diagnostics |
| `Waveforms/`, `Lissajous/` | Optional converted waveforms, amplitude-matched figures and exact plotted samples |
| Export root | `analysis_status.csv`, `settings_snapshot.json`, `manifest.json` |

Choose a new or empty output folder. Existing output is not overwritten. Retain the original acquisition files separately.

For a workspace screenshot, choose the page in the dropdown beside **Save current workspace view**, then save the PNG. The selected method page is captured and the application returns to Export.

### Lissajous figures at a specific strain

Enter **Target strain amplitude (%)**, or use **Use selected file amplitude**. The tolerance is in absolute percentage points: target `10`, tolerance `0.1` matches 9.9–10.1%. Selection uses measured amplitude, not the filename; no interpolation between strain levels is performed.

Choose individual figures or an overlay, all measured data or the last N estimated periods, then PNG, vector PDF and/or editable FIG. **Export Lissajous only** works without running an analysis method.

The elastic plot is total measured stress versus measured strain; the viscous plot is total measured stress versus preview numerical strain rate. CSV files contain the exact plotted samples. The last-N window ends at the final measured sample and uses the preview frequency. It is not a phase-averaged or automatically stable cycle. Measured offsets are retained and loops are not forcibly closed.

## Running the checks

From the project folder, use the following MATLAB commands to check input units, independent FT/SD settings, the five-tab workspace and exports with synthetic data. The test writes its report and example exports to the new temporary folder returned by `tempname`.

```matlab
addpath('tests');
outputFolder = tempname;
report = test_merged_laos_revision(outputFolder);
assert(report.Passed);
```

## License

The copyright holder's terms for viewing, academic reference and reuse are in the [license](LICENSE).
