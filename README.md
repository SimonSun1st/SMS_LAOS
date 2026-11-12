# SMS-LAOS

SMS-LAOS is a MATLAB app for large-amplitude oscillatory shear (LAOS) data. It supports Fourier-transform LAOS (FT-LAOS), stress decomposition (SD) and sequence of physical processes (SPP) analysis. [中文说明](README_ZH.md)

## Start

Tested with MATLAB R2026b and Signal Processing Toolbox. Open the project folder in MATLAB and run

```matlab
launch_SMS_LAOS
```

## Analyze data

1. Choose **Load data** for individual files or **Add folder** for a batch. Supported formats are DAT, CSV, TXT, TSV, XLS and XLSX.
2. In **Data & units**, set the time, strain and stress columns and their units. The defaults are columns 1–3 in seconds, percent strain and Pa. These settings apply to all loaded files. Check the waveforms, strain rate and estimated frequency in the preview.
3. Check the methods you need, adjust their settings on the corresponding tabs, then choose **Analyze selected** or **Analyze all**.
4. The file list shows progress. **Finished** means all checked methods completed without a quality warning. A label such as **Review (SPP)** names the method that raised a warning. Click the row to read the reason.

## Export

On **Export**, choose **Export results** to save current results for the checked methods across all loaded files.

For a Lissajous plot at a specific strain, enter **Target strain amplitude (%)** and **Tolerance (percentage points)**. For example, a target of 10% with a tolerance of 0.1 matches measured amplitudes from 9.9% to 10.1%. Choose PNG, PDF or MATLAB FIG, then click **Export Lissajous only**. This uses the measured waveforms and can be done before running any analysis method.
