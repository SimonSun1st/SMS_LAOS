# SMS-LAOS 中文使用说明

SMS-LAOS 是用于分析大振幅振荡剪切（LAOS）实验数据的英文 MATLAB 应用。可对单个文件或整批文件运行傅里叶变换分析（FT-LAOS）、应力分解（SD）和物理过程序列分析（SPP）。每种方法有独立的设置和结果，所有导出选项集中在 **Export**。[English user guide](README.md)

## 启动与流程

需要 MATLAB R2026b 和 Signal Processing Toolbox。将包含 `launch_SMS_LAOS.m` 的文件夹设为 MATLAB 当前文件夹，在命令行运行

```matlab
app = launch_SMS_LAOS;
```

要先试用，可点击 **Load synthetic demo**，保持勾选全部三种方法，再点 **Analyze selected**。已有脚本仍可通过 `launch_merged_laos_analysis` 启动应用。

1. Load data / Add folder 导入文件；移除列表或 Clear 不删除原文件。
2. 在 Data & units 设置原始数据的单位、列号、表头、分隔符和 Excel sheet；查看波形、数值应变率、估计频率及原始 Lissajous。
3. 按需勾选 FT-LAOS、Stress decomposition、SPP，在各自标签页设置分析参数。
4. Analyze selected 处理高亮文件，Analyze all 处理全部文件；查看状态和诊断。
5. 在 Export 统一选择输出内容并导出。通常导出当前整个列表内符合条件的结果，不仅是高亮文件。

批量导入时，状态栏显示进度，优先显示选中文件的波形。文件列表出现后按 **Stop**，程序会在当前文件操作结束时停止，保留已完成的预览。点选标为 **Queued** 的行即可查看该文件，也可以用 **Load data** 重新选择同一批文件，继续准备其余预览。分析期间按 **Stop** 会保留已完成的方法结果。

批量分析时，文件列表滚动到 **Running** 行，显示正在运行的方法。每处理完一个方法，进度条就前进一步。一个文件的所有已勾选方法处理完毕后，文件计数才增加。

| 文件状态 | 含义和操作 |
| --- | --- |
| **Waiting** | 等待分析。 |
| **Finished** | 已勾选的方法均已完成，程序未检出质量警告。 |
| **Review (SPP)** | 计算已完成，SPP 发出质量警告；如有多种方法发出警告，括号内会列出相应方法。单击该行，在左侧方法状态行下方查看该文件的具体原因。较长的提示可滚动查看。 |
| **Error** 或 **Input error** | 计算或输入预览失败，可查看相应方法的诊断或 **Data & units** 上的提示。 |
| **Partial** | 部分方法已有结果，可选择该行并点击 **Analyze selected** 重新分析。 |

例如，如果 SPP 提示连续通过稳定性检查的末段周期不足，可以在 **SPP → Stationarity** 查看稳定性诊断，在 **Cycle metrics** 查看逐周期结果。此时代表性平均周期为空。

## 输入单位与数据映射

必须提供的实测通道是时间、应变和应力；应变率、频率和角频率由程序计算。三种方法和预览使用同一组输入设置。

如果 Finder 能看到 OneDrive 文件，但文件内容还未下载，可右键点击该文件或整个实验文件夹，选择 **Always Keep on This Device（始终保留在此设备上）**。下载完成后，在 **Data & units** 中点击 **Retry preview** 重新读取当前文件。要重试整批文件，可用 **Load data** 重新选择同一批文件。

| 量 | 可选单位 |
| --- | --- |
| 时间 | s、ms、µs（us）、min、h |
| 应变 | percent、decimal、millistrain、microstrain |
| 应力 | Pa、kPa、MPa、mPa、bar、psi、dyn/cm² |

例如 1% 应变分别对应 percent 中的 `1`、decimal 中的 `0.01`、millistrain 中的 `10`、microstrain 中的 `10000`。注意 mPa 和 MPa 区别很大。

Data & units 统一管理 time/strain/stress 列号、跳过表头行数、分隔符、sheet。DAT、CSV、TXT、TSV、XLS、XLSX 均通过这组映射供各方法使用。默认第 1/2/3 列为 time/strain/stress，单位为 s、percent、Pa，显式跳过 0 行并自动识别分隔符。设置适用于整个列表，批次内应使用相同的已声明单位和列布局。

计算前转换为**秒、小数应变、Pa**；频率内部为 Hz，角频率为 rad/s，应变率为 s⁻¹，模量为 Pa，黏度为 Pa·s。部分 SPP 图按轴标签以 kPa 显示。原单位、换算因子、列映射与来源保留在结果和导出元数据中，原始文件只读。

改变单位或列映射后，预览更新，相关旧结果标为 stale，需要重算；恢复完全相同的旧设置可恢复匹配的缓存结果。源文件变化用大小和修改时间检测，不是内容哈希。

## 各方法的设置

**FT-LAOS**：自己的周期范围、频率搜索范围和谐波符号约定。结果区仅保留应变/应力频谱、数值表和质量诊断，移除了谐波幅值与模量柱状图；数值仍在表格和导出中。频率范围可用 Hz 或 rad/s 显示，切换保持物理范围不变；脚本 `freq_min/freq_max` 始终以 Hz 输入。

**Stress decomposition**：自己的周期范围、频率搜索和符号约定，以及弹性/黏性分解、重建残差、Lissajous、Chebyshev 系数、S/T、汇总和诊断。FT 与 SD 仍使用原 SMS v2 数值方程，但设置、所选区间、缓存和过期状态彼此独立。若要比较相同区间，需给两者设置相同周期选择和频率搜索选项。SMS 重建及 S/T 仍只使用第 1、3 次项。

**SPP**：保留 Average response、Cycle evolution、多文件比较、拟合/平滑敏感性、逐周期指标及稳态/质量诊断。导入和导出设置不再放在此方法页。手动频率可选 Hz/rad/s，空白为自动估计；切换单位保持物理频率，脚本 `Omega` 始终以 rad/s 输入。

SPP 稳定末段平均找不到通过筛选的末段时保持 average 为空，只导出诊断，不自动回退。逐周期演化不强制闭合、不跨缺口拟合，支撑不足的边缘被屏蔽。SPP 直接使用实测应力，不使用 SMS 的第 1/3 次重构曲线替代，也不自动删除偶次分量。筛选容差为工程诊断参数，不是置信区间。

## 预览与分析方法的区别

预览转换单位，但保留实测样本，不做相位平均、平滑或直流扣除。应变率为以秒为时间的 `gradient(strain,time)`；频率由应变 FFT 主峰和实际时间戳上的正弦拟合估计。文件幅值为完整估计周期半峰峰值的中位数，没有完整周期时用全记录半峰峰值。

这些预览量不覆盖各算法自己的频率、导数或选圈方法。SMS 仍保留任意输入列含 NaN 即剔除该行的旧规则，预览/SPP 使用其记录的选定通道和清理规则；额外列缺失可能导致实际使用行数不同。幅值随时间改变的文件应单独检查。

单位转换涉及浮点舍入。若 SMS 的时间截取边界恰好落在采样时间点上，微小舍入差可能使原有截取规则多保留或少保留一个边界样本；数值核心未改动。因此，等价单位验证使用数值容差，不宣称所有输入都能逐位完全一致。

## 全部导出选项集中在 Export

- Analysis output package 的 Full/Fast 控制原生 SD 导出：Full 保留 Excel、所选周期 CSV、PNG/FIG 等完整输出；Fast 减少这些耗时输出，保留汇总和完整 MAT。
- Decomposed curve CSV 独立控制分解曲线。
- FT 导出数值汇总、谐波/频谱 CSV 和完整 MAT；SPP 导出完整结果、逐周期/谐波、可用相位数据、诊断和设置。
- 可选 Waveforms CSV、指定应变 Lissajous、PNG/PDF/FIG 与 Save view 都在此页。

导出设置不改变计算结果，也不会令结果过期。仅纳入当前勾选方法中成功且不过期的结果，每种方法保留自己的设置与数值；失败、未运行和 stale 状态记录在 `analysis_status.csv` / `manifest.json`。不能覆盖已有非空目录。

输出按 `FT_LAOS/`、`Stress_decomposition/`、`SPP/`、可选 `Waveforms/` 和 `Lissajous/` 保存。根目录保存设置快照和导出清单。原始采集文件需另行保存。

## 指定应变下的 Lissajous

输入 Target strain amplitude (%) 或使用 Use selected file amplitude。Tolerance 为绝对应变百分点，例如 10、0.1 匹配 9.9%–10.1%；依据实测幅值，不解析文件名，不在应变等级之间插值。

可选择逐文件图或叠加图、全部数据或最后 N 个估计周期，以及 PNG、矢量 PDF、可编辑 FIG。Export Lissajous only 无需先运行分析方法。

弹性图为总实测应力–实测应变，黏性图为总实测应力–预览数值应变率；CSV 保留确切绘图样本。最后 N 圈由预览频率确定时间窗口，不是相位平均或自动稳定周期；保留实测偏置，不强制闭合。

## 验证

在 MATLAB 的项目文件夹中运行以下命令，可用合成数据检查单位换算、FT/SD 独立设置、五个标签页和导出。测试报告和导出样例会写入 `tempname` 指定的新临时文件夹。

```matlab
addpath('tests');
outputFolder = tempname;
report = test_merged_laos_revision(outputFolder);
assert(report.Passed);
```

## 使用许可

查阅、学术参考和代码使用的具体条件见[许可文件](LICENSE)。
