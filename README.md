# SMS-LAOS app

SMS-LAOS app analyzes large-amplitude oscillatory shear measurements in MATLAB. Use FT-LAOS to quantify stress harmonics, stress decomposition (SD) to separate intracycle elastic and viscous contributions, and sequence of physical processes (SPP) analysis to follow the response within or across cycles. Each method can run independently on one file or a batch. [中文使用说明](README_ZH.md)

The graphical application is in the [SMS-LAOS app folder](SMS-LAOS%20app/). The original MATLAB scripts have separate manuals for [v1](SMS_LAOS_README.md) and [v2](SMS_LAOS_README_v2.md).

## Download and install

1. Install MATLAB if needed. The app has been tested with MATLAB R2026b. Sign in with your licensed MathWorks account, download the installer and select MATLAB. [MathWorks Downloads](https://www.mathworks.com/downloads/)
2. Download the app ZIP and extract it. In MATLAB, set the current folder to **SMS-LAOS app**, which contains `SMS_LAOS_app.m`. [Download SMS-LAOS app ZIP](https://raw.githubusercontent.com/SimonSun1st/SMS_LAOS/Initial-upload-of-MATLAB-analysis-script/downloads/SMS-LAOS%20app.zip)
3. Run the following command in the MATLAB Command Window.

```matlab
SMS_LAOS_app
```

Click **Load synthetic demo**. The preview should show about **1 Hz** and **50% strain amplitude**. Leave all three methods checked and click **Analyze selected**. The example should finish with a **Finished** row. Select that row and open each method tab to inspect the same file.

All three methods run with MATLAB alone. To install the optional **Signal Processing Toolbox** for other work, open **Add-Ons** in the R2026b left sidebar, search for the toolbox, select the MathWorks product and click **Install** using a license that includes it. Run `ver` to list installed products. [MathWorks add-on guide](https://www.mathworks.com/help/matlab/matlab_env/get-add-ons.html)

## Load and check the measurements

Choose **Load data** to select files or **Add folder** to import a batch. The **Folder** label above the file list shows the selected file’s source folder. When files come from several folders, the label includes a count of the other folders. Hover over it to see their paths. The app accepts DAT, CSV, TXT, TSV, XLS and XLSX. Each file needs numeric time, strain and stress channels. For the waveform preview, provide at least ten finite rows with strictly increasing timestamps.

| Channel | Default column and unit | Other supported units |
| --- | --- | --- |
| Time | 1, seconds | ms, µs, min, h |
| Strain | 2, percent | Decimal, millistrain, microstrain |
| Stress | 3, Pa | kPa, MPa, mPa, bar, psi, dyn/cm² |

In **Data & units**, match the columns, units, header rows, delimiter or spreadsheet sheet to the acquisition. With percent strain, a value of `10` means 10% strain. The equivalent decimal value is `0.10`. Settings apply to every loaded file, so process different layouts or unit conventions in separate batches.

For a file arranged as time (ms), stress (kPa), strain (%), enter column numbers **1, 3, 2** for time, strain and stress, and choose **ms, Percent (%), kPa**.

Inspect the measured waveforms and the stress–strain loop before analysis. The preview calculates numerical strain rate from strain and the original timestamps. It estimates frequency from the strain signal and reports angular frequency as ω = 2πf. FT, SD and SPP each select their own analysis window. If a frequency or modulus looks unexpected, first check the time unit and the strain and stress scales.

## Run a file or a batch

Check the required methods, adjust each method on its own tab, then click **Analyze selected** for highlighted files or **Analyze all** for the whole list. The file list shows the active file and method. **Stop** preserves completed results and takes effect between method calculations.

| State | What to do |
| --- | --- |
| **Waiting** or **Running** | The row shows which file and method are active. The progress bar advances after each checked method completes. |
| **Finished** | All checked methods completed without an automatic quality warning. Open a method tab to view the result. |
| **Review (SPP)**, **Review (FT, SD)**, etc. | Calculation completed. Click the row to read the actual warnings for the named methods in the left sidebar. |
| **Partial** or **Stale** | Some checked results are missing or a setting or source has changed. Select the file and run **Analyze selected**. |
| **Error** or **Input error** | Inspect the message for the failed method or the input preview, correct the cause and retry. |

## FT-LAOS

FT-LAOS detects the fundamental strain frequency, selects the requested cycles and computes strain and stress spectra. The numeric table reports the first and third stress harmonics.

| Output | Meaning |
| --- | --- |
| I₁, I₃ (Pa) | Amplitudes of the stress FFT at the fundamental and third harmonic. I₃/I₁ gives the relative third-harmonic amplitude. |
| δ₁, δ₃ (rad) | Stress phase relative to the fundamental strain phase. For order three the reference is three times the fundamental strain phase. |
| G′₁, G″₁, G′₃, G″₃ (Pa) | Elastic and viscous Fourier coefficients for each reported harmonic, normalized by the fundamental strain amplitude. |

The default cycle selection trims **three periods at each end** and uses complete periods from the remaining interval. Alternatively choose the **last N cycles** (default N = 5). If the record is short, reduce the trim counts or use fewer final cycles. Frequency search is unrestricted by default. If the dominant peak is outside the known drive-frequency band, enable the frequency limits and enter the expected band (initial settings 0.01–10 Hz). The alternating odd-harmonic sign option is on by default and changes the signs of both third-order Fourier coefficients. Record this setting when comparing third-order results between analyses.

## Stress decomposition

SD has its own cycle selection, frequency search and sign setting, with the same initial defaults as FT-LAOS. For a direct comparison, match these settings on both tabs. SD reconstructs elastic stress from strain and viscous stress from strain rate using the first and third Chebyshev terms. The sum gives reconstructed stress. The residual is selected, mean-centered measured stress minus reconstructed stress.

| Quantity | Definition or interpretation |
| --- | --- |
| Elastic coefficients | e₁ = G′₁ and e₃ = −G′₃, in Pa. The ratio e₃/e₁ compares third- and first-order elastic contributions. |
| Viscous coefficients | v₁ = G″₁/ω and v₃ = G″₃/ω, in Pa·s. The ratio v₃/v₁ compares the viscous contributions. |
| Strain stiffening, S | G′ₘ = e₁ − 3e₃ and G′ₗ = e₁ + e₃ are the minimum-strain and large-strain moduli. S = (G′ₗ − G′ₘ)/G′ₗ. Positive S indicates intracycle stiffening and negative S indicates softening when the denominator is positive. |
| Shear thickening, T | η′ₘ = v₁ − 3v₃ and η′ₗ = v₁ + v₃ are the minimum-rate and large-rate viscosities. T = (η′ₗ − η′ₘ)/η′ₗ. Positive T indicates intracycle thickening and negative T indicates thinning when the denominator is positive. |

The reconstruction uses T₁(x) = x and T₃(x) = 4x³ − 3x. For elastic stress, x is strain divided by the fundamental strain amplitude γ₀. For viscous stress, x is strain rate divided by ωγ₀. The implementation clips both normalized coordinates to [−1, 1].

Use the raw and reconstructed loops to see where the two-term reconstruction misses measured stress. A **reconstruction RMS/I₁ above 0.10** triggers a review warning. Inspect the selected cycles, harmonic spectrum and sampling. Higher harmonics, the selected frequency or noise in the numerical strain rate can all affect this residual. Ratios with a zero denominator are reported as NaN.

## SPP

SPP fits local planes to measured stress as a function of strain and normalized strain rate (strain rate divided by ω). The slopes give the transient storage and loss moduli, G′ₜ and G″ₜ (Pa). The local model is σ ≈ G′ₜ γ + G″ₜ (γ̇/ω) + σd, where σd is the fitted stress intercept. The two analysis modes answer different questions.

| SPP mode | Selection and results |
| --- | --- |
| **Average response** | The default **Stable final cycles** policy tests consecutive eligible cycles at the end of the record. The initial settings require at least five cycles, with 5% bulk and 25% significant-harmonic tolerances. The harmonic inclusion floor is 0.1% of I₁. A passing window supplies the phase-averaged response and local moduli. |
| **Cycle evolution** | Follows the response cycle by cycle using the original time order. Local fits use contiguous data and mask points with insufficient support. Use this mode to examine a changing response across the record. |

If SPP reports **no stable final cycles**, open **Stationarity** for the candidate windows and limiting metric, then **Cycle metrics** for individual cycles. The per-cycle diagnostics remain available and the stable-cycle average is empty. Use manual cycle selection when you want an average for a specified interval. For sharp features in local moduli, inspect the fit-window and smoothing sensitivity views before assigning physical significance. The harmonic maximum order controls the reported harmonic descriptors.

## Export results

Under **Export → Export content**, choose **Analysis results**, **Lissajous plots** or **Results and plots**. The page shows the settings for that choice. Click **Export…** and choose a parent folder. During writing, the page displays the current operation and percentage. **Cancel export** stops after the active operation and discards the unfinished package. **Workspace snapshot** saves a PNG of a chosen app tab.

**Analysis results** includes current results for the checked methods across all files, including completed results with warnings. The default **Fast** package skips native SD figures and Excel workbooks. Select **Full** when you need them.

| Output location | Contents |
| --- | --- |
| `FT_LAOS/` | Batch `summary.csv`, per-file harmonic and spectrum CSVs and MATLAB results. |
| `Stress_decomposition/` | Summary table and per-file MAT results. **Full** adds Excel, selected-cycle CSVs and native PNG/FIG plots. **Fast** saves the lighter package. **Decomposed curve CSV** independently exports measured, elastic, viscous, reconstructed and residual stresses for replotting. |
| `SPP/` | Per-file MAT results, cycle and harmonic tables. Average or evolution phase traces and sensitivity tables are included when available. |
| `Waveforms/`, `Lissajous/` | Optional exports include converted waveforms, Lissajous figures for the selected strains, and the samples used in each plot. |
| Export root | `analysis_status.csv`, `settings_snapshot.json` and `manifest.json`. |

### Lissajous figures at selected strains

1. Set **Export content** to **Lissajous plots** or **Results and plots**. The file checklist opens under **Strains to export**. Tick the rows you want, for example the files near 5%, 10% and 20%. Each row shows its measured amplitude and filename. You can select individual replicates even when their amplitudes coincide. Alternatively, **Target amplitude and tolerance** selects all matches in a range (10% ± 0.1 percentage points includes 9.9% to 10.1%).
2. Under **Lissajous plots**, check the figures you need. To compare measured and decomposed stress, run **Stress decomposition** on the chosen files and select these three plots:

   | Plot | Horizontal axis | Vertical axis |
   | --- | --- | --- |
   | **Total stress vs strain** | Strain (%) | Measured total stress (Pa) |
   | **Elastic stress vs strain** | Strain (%) | Reconstructed elastic stress (Pa) |
   | **Viscous stress vs strain rate** | Physical strain rate (s⁻¹) | Reconstructed viscous stress (Pa) |

   **Total stress vs strain rate** is also available. If either component is selected, all curves for each file use the same SD samples, mean-centered strain and measured total stress. With only total-stress plots selected, the app uses the measured waveform preview and retains its offsets. These plots can be exported before analysis.
3. Under **Axis scale**, choose **Physical units**, **Normalised** or **Physical and normalised**. The app calculates each reference separately for each file over the time window being plotted. Strain and strain rate each use their own peak absolute value. Total, elastic and viscous stress all use the peak absolute **measured total stress**, preserving the relative sizes of the components. For normalised exports, the CSV includes the dimensionless coordinates alongside the dimensional data, and `manifest.json` records the reference values. A zero reference requires another window or physical units.
4. Choose **Separate figures per file** for one set per selected file or **Overlay matched files** for one overlay per plot type. Select the entire available window or its last N cycles. PNG is selected by default. Vector PDF and editable MATLAB FIG are optional. Click **Export…**.

The figure CSV contains the samples used for plotting. For component plots, `_decomposition_curves.csv` records SD elapsed time, acquisition time, strain, strain rate, and the total, elastic and viscous stresses.

## Method references

- Fourier-transform rheology. Wilhelm, Maring & Spiess (1998). [Rheologica Acta](https://doi.org/10.1007/s003970050126)
- Elastic and viscous stress decomposition. Cho et al. (2005). [Journal of Rheology](https://doi.org/10.1122/1.1895801)
- Chebyshev coefficients and intracycle measures. Ewoldt, Hosoi & McKinley (2008). [Journal of Rheology](https://doi.org/10.1122/1.2970095)
- Transient moduli and SPP. Rogers (2017). [Rheologica Acta](https://doi.org/10.1007/s00397-017-1008-1)
