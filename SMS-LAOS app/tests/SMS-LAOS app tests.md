# SMS-LAOS app tests

In MATLAB, set the current folder to the extracted `SMS-LAOS app` folder and run the following commands to check the file list and its review details.

```matlab
addpath('tests')
review = SMS_LAOS_app_test_review();
assert(review.Passed)
```

All suites listed below generate their own inputs. None requires access to an experimental data set.

| Test | Coverage |
| --- | --- |
| `SMS_LAOS_app_test_review` | Method names in the file list, warning text when selecting a row, and updates when switching files or changing the checked methods. |
| `SMS_LAOS_app_test_batch` | A 48-file sweep, live progress, stopping and resuming work, repeated filenames, and malformed or missing input. |
| `SMS_LAOS_app_test_workflow` | Independent FT and SD settings, shared units, the five analysis and export tabs, and invalidation after changes. |
| `SMS_LAOS_app_test_units` | Seven input-unit combinations, numerical agreement with the reference routines, and a cycle-trimming boundary case. |
| `SMS_LAOS_app_test_export` | Method-specific exports and their saved results. |
| `SMS_LAOS_app_test_preview_export` | Measured waveforms, strain rate, and Lissajous exports. |
| `SMS_LAOS_app_test_lissajous_components` | Reopens individual and overlay figures, compares their lines and CSVs with the measured and decomposed arrays, and checks exact file selections and missing or stale SD results. |

The workflow and export suites accept a new output directory as an argument, for example `report = SMS_LAOS_app_test_workflow(tempname);`. Check `report.Passed` for their overall result.
