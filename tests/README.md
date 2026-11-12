# SMS-LAOS tests

In MATLAB, open the SMS-LAOS repository folder and run the following commands to check the file list and its review details.

```matlab
addpath('tests')
review = test_sms_laos_review();
assert(review.Passed)
```

All suites listed below generate their own inputs. None requires access to an experimental data set.

| Test | Coverage |
| --- | --- |
| `test_sms_laos_review` | Method names in the file list, warning text when selecting a row, and updates when switching files or changing the checked methods. |
| `test_merged_laos_batch` | A 48-file sweep, live progress, stopping and resuming work, repeated filenames, and malformed or missing input. |
| `test_merged_laos_revision` | Independent FT and SD settings, shared units, the five analysis and export tabs, and invalidation after changes. |
| `test_merged_laos_units` | Seven input-unit combinations, numerical agreement with the reference routines, and a cycle-trimming boundary case. |
| `test_merged_laos_export` | Method-specific exports and their saved results. |
| `test_merged_laos_preview_export` | Measured waveforms, strain rate, and Lissajous exports. |

The revision and export suites accept a new output directory as an argument, for example `report = test_merged_laos_revision(tempname);`. Check `report.Passed` for their overall result.
