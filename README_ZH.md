# SMS-LAOS app 使用指南

SMS-LAOS app 将大振幅振荡剪切（LAOS）的三种分析放在同一个 MATLAB 界面中。**FT-LAOS** 给出不同谐波的应力幅值和相位，**Stress decomposition**（SD）重建弹性与黏性应力并计算周期内非线性指标，**SPP**（物理过程序列分析）追踪一个周期内及相邻周期间的局部响应。单个文件或整批文件都可以只运行所需的方法。[English guide](README.md)

图形界面程序位于 [SMS-LAOS app 文件夹](SMS-LAOS%20app/)。原版 MATLAB 脚本分别附有 [v1 手册](SMS_LAOS_README.md)和 [v2 手册](SMS_LAOS_README_v2.md)。

## 下载与安装

1. **安装 MATLAB**。本应用已在 MATLAB R2026b 上测试。如果尚未安装，用已关联许可证的 MathWorks 账号下载安装程序，并在产品列表中选择 **MATLAB**。[MathWorks 下载页](https://www.mathworks.com/downloads/)
2. **下载并完整解压 App**。在 MATLAB 中将包含 `SMS_LAOS_app.m` 的 **SMS-LAOS app** 文件夹设为当前文件夹。[下载 SMS-LAOS app ZIP](https://raw.githubusercontent.com/SimonSun1st/SMS_LAOS/Initial-upload-of-MATLAB-analysis-script/downloads/SMS-LAOS%20app.zip)
3. 在 MATLAB 命令窗口运行

```matlab
SMS_LAOS_app
```

第一次使用时点击 **Load synthetic demo**。预览应显示约 **1 Hz** 和 **50% 应变幅值**。保持三个方法均已勾选，点击 **Analyze selected**，示例的文件状态应变为 **Finished**。

**Signal Processing Toolbox 为可选工具箱**。上述三个方法均可用基础 MATLAB 运行。如果其他工作需要该工具箱，在 R2026b 左侧的 **Add-Ons** 中搜索 **Signal Processing Toolbox**，选择 MathWorks 发布的产品并点击 **Install**。许可证需包含该产品。运行 `ver` 可以查看已安装的产品。[MathWorks 安装说明](https://www.mathworks.com/help/matlab/matlab_env/get-add-ons.html)

## 输入文件、单位与波形预览

用 **Load data** 导入一个或多个文件，或用 **Add folder** 加载一个文件夹中的数据。文件列表上方的 **Folder** 显示当前选中文件的来源文件夹。混合导入时，名称旁会显示其他文件夹的数量，悬停可查看完整路径。支持 DAT、CSV、TXT、TSV、XLS 和 XLSX。每个文件需包含时间、应变和应力三个数值通道，采样时间应严格递增。在 **Data & units** 设置列号、单位、表头行数、分隔符和 Excel 工作表。默认读取第一个工作表并自动识别文本分隔符。

| 量 | 默认列及单位 | 支持的输入单位 |
| --- | --- | --- |
| 时间 | 第 1 列，s | s、ms、µs、min、h |
| 应变 | 第 2 列，Percent (%) | 百分比、小数应变、毫应变、微应变 |
| 应力 | 第 3 列，Pa | Pa、kPa、MPa、mPa、bar、psi、dyn/cm² |

例如，10% 应变在采集文件中可能写作 `10` 或 `0.10`，两者分别选择 **Percent (%)** 和 **Decimal**。应力若以 kPa 记录，应选择 **kPa**。单位与列映射作用于整批文件，格式不同的文件可分批处理。计算统一使用秒、小数应变和 Pa。

例如，文件按时间（ms）、应力（kPa）、应变（%）排列时，时间、应变、应力的列号应依次填 **1、3、2**，单位依次选 **ms、Percent (%)、kPa**。

点击文件行可查看应变、应力、应变率和实测李萨如曲线。预览按采样时间对实测应变作数值微分得到应变率，以应变频谱主峰为初值拟合频率，并给出角频率 ω = 2πf。文件列表中的应变幅值取各完整估计周期半峰峰值的中位数；没有完整估计周期时使用整段记录的半峰峰值。波形幅值随时间变化的文件，应先检查各圈，再用于幅值比较。

## 选择分析方法和周期

在左侧勾选所需方法，在各自的标签页调整参数。**Analyze selected** 处理高亮文件，**Analyze all** 处理文件列表中的全部文件。

### FT-LAOS：查看频谱与谐波

FT-LAOS 从应变的正频率 FFT 峰值确定基频，对选定时间窗去均值，然后从应力频谱提取基频与三倍基频的分量。结果页显示应变频谱、应力频谱、数值表和质量提示。

- **Trim ends** 默认从记录首尾各去掉 3 个周期，再使用剩余区间中的完整周期。**Last N cycles** 使用末尾指定数量的周期，初始值为 5。若记录较短，可减小裁剪数，或选用文件实际包含的圈数。
- 频率搜索默认覆盖可用的正频段。如果检测到的基频与施加频率不符，可启用 **Restrict frequency search** 并设置上下限。预设范围为 0.01–10 Hz，单位可切换为 Hz 或 rad/s。
- `I1` 和 `I3` 为一阶和三阶应力谐波幅值，单位为 Pa。`I3/I1` 给出三阶谐波相对于基波的强度。`delta1`、`delta3` 的单位为 rad，分别以应变基波相位及该相位的三倍为参照。`G′1`、`G″1`、`G′3`、`G″3` 是所选符号约定下的弹性与黏性傅里叶系数，单位为 Pa。

### Stress decomposition：分解应力与周期内非线性

SD 有自己的周期选择、频率搜索和 **Alternating odd-harmonic sign** 设置。若要将分解结果与 FT 数值逐项比较，应在两个标签页选用相同的周期范围、频率搜索范围和符号约定。默认启用交替奇次谐波符号，此时一阶傅里叶系数保留原符号，三阶傅里叶系数乘以 −1。

分解使用一阶和三阶切比雪夫项。按本应用约定，弹性系数为 `e1 = G′1` 和 `e3 = −G′3`（Pa），黏性系数为 `v1 = G″1/ω` 和 `v3 = G″3/ω`（Pa·s）。程序以归一化应变重建弹性应力，以归一化应变率重建黏性应力，两项相加得到重建总应力。残差为同一分析窗内去均值的实测应力减去重建总应力。较大残差时，可对照未纳入重建的高次谐波、所选周期、基频与应变率噪声。

| 指标 | 算法与读法 |
| --- | --- |
| `e3/e1`、`v3/v1` | 三阶弹性、黏性切比雪夫项相对于各自一阶项的比值。跨样品比较时应使用一致的符号约定。 |
| 周期内应变硬化比 `S` | 最小应变切线模量 `G′M = e1 − 3e3`，大应变割线模量 `G′L = e1 + e3`，`S = (G′L − G′M)/G′L`。当大应变模量为正时，正值对应周期内应变硬化，负值对应软化。 |
| 周期内剪切增稠比 `T` | 最小速率切线黏度 `η′M = v1 − 3v3`，大速率割线黏度 `η′L = v1 + v3`，`T = (η′L − η′M)/η′L`。当大速率黏度为正时，正值对应周期内剪切增稠，负值对应剪切变稀。 |

重建使用 T₁(x) = x 和 T₃(x) = 4x³ − 3x。对弹性项，x 为应变除以基波应变幅值 γ₀；对黏性项，x 为应变率除以 ωγ₀。计算时将归一化坐标限制在 [−1, 1] 范围内。

这两个比值表征选定振荡周期内的响应。若分母接近零，应结合对应模量、黏度和重建曲线判断；分母等于零时结果记为 `NaN`。

### SPP：周期平均与逐周期演化

SPP 直接使用实测应力。局部平面模型为 σ ≈ G′ₜ γ + G″ₜ (γ̇/ω) + σd，其中 σd 是拟合得到的应力截距。在周期内不同相位上估计局部储能、损耗模量 `G′t` 和 `G″t`；它们随时间或相位变化，可与 FT-LAOS 的整窗谐波系数分别查看。**Input frequency** 留空时自动估计，也可选 Hz 或 rad/s 后输入已知频率。

- **Average response** 默认采用 **Stable final cycles**。程序从最后一个连续有效周期段中选取通过稳定性筛选的最长末段，按输入相位对齐并平均。默认至少 5 圈，整体稳定性容差为 5%，显著复谐波系数的变化容差为 25%，显著性下限为 `I1` 的 0.1%。若末段未达标，平均曲线留空。**Stationarity** 和 **Cycle metrics** 保留筛选原因及逐圈结果。已有明确实验依据的分析区间可通过 **Manual selection** 指定圈号或范围。
- **Cycle evolution** 保留有效完整周期的顺序，适合考察应力幅值、谐波比、逐圈输入功及局部模量随加载时间的变化。切换 **Cycle number** 和 **Elapsed seconds** 可从不同横坐标检查同一记录。在信号缺口或局部拟合支撑不足的位置，有效性掩码会影响可用的模量数据。拟合窗口、平滑设置及相应灵敏度结果可用于检查局部特征对处理参数的依赖。

## 批量进度与复核

| 左侧文件状态 | 含义和操作 |
| --- | --- |
| **Waiting**、**Running: …** | 等待处理，或正在执行所示方法。进度条按完成的方法数更新。 |
| **Finished** | 勾选的方法均已完成，未触发程序的自动质量提示。 |
| **Review (SPP)**、**Review (FT, SD)** 等 | 计算已完成，括号中列出了触发质量提示的方法。单击该行，在左栏查看该文件的具体原因。 |
| **Partial**、**Stale** | 仅部分方法完成，或设置、源数据改变后旧结果已过期。选中相应文件，确认设置并点击 **Analyze selected**。 |
| **Input error**、**Error** | 输入预览或方法计算失败。查看 **Data & units** 的报错或对应方法的诊断。 |

例如，FT 或 SD 的提示中若出现 `Reconstruction RMS/I1`，表示重建残差的均方根相对于一阶应力幅值的大小；默认超过 0.10 会提示复核。若显示 **Review (SPP)**，先查看具体警告，再决定检查末段稳定性或局部拟合的有效性。批量分析时可点击 **Stop**，程序会在当前方法结束后停止，已完成的结果保留。

## 导出结果与指定应变幅值的李萨如图

在 **Export → Export content** 选择 **Analysis results**（分析结果）、**Lissajous plots**（李萨如图）或 **Results and plots**（两者一起），页面随选择显示对应设置。点击 **Export…** 后选择保存位置。写文件时可以查看当前步骤和百分比，也可以点 **Cancel export**。取消会在当前操作结束后生效，并清理未完成的结果包。选择 **Workspace snapshot** 可保存指定页面的 PNG 截图。

**Analysis results** 导出所有文件中已勾选方法的有效结果，包括带有质量提示的结果。默认的 **Fast** 包适合导出数据。需要 SD 原生图和 Excel 工作簿时选择 **Full**。

| 输出位置 | 主要内容 |
| --- | --- |
| `FT_LAOS/` | `summary.csv` 汇总频率、所用圈数、谐波和模量；每个文件另有谐波表、频谱 CSV 和 MAT 结果。 |
| `Stress_decomposition/` | 数值汇总、完整 MAT 结果和质量记录。**Full** 增加 Excel、选定周期 CSV 和 PNG/FIG 图；**Fast** 适合批量导出数值。分解曲线 CSV 可单独勾选。 |
| `SPP/` | 逐圈指标、谐波表、完整 MAT 结果，以及可用的平均或逐周期相位数据、灵敏度结果。 |
| `Waveforms/`、`Lissajous/` | 可选的实测波形、数值应变率，以及目标应变下的图形与对应绘图数据。 |
| 导出根目录 | `analysis_status.csv` 记录逐文件状态，`settings_snapshot.json` 保存设置，`manifest.json` 列出导出内容。 |

### 勾选应变幅值并导出李萨如图

1. 在 **Export content** 选择 **Lissajous plots** 或 **Results and plots**，打开 **Strains to export** 下方的文件勾选表。按表中显示的实测应变幅值和文件名勾选所需行，例如只选接近 5%、10% 和 20% 的三个文件。即使两个文件的幅值相同，也可以只选其中一个。如果要导出一个范围内的全部文件，选择 **Target amplitude and tolerance**。例如，目标 10%、容差 0.1 个百分点会匹配 9.9% 至 10.1%。
2. 在 **Lissajous plots** 勾选需要的图。若要比较总应力及其分量，先对所选文件运行 **Stress decomposition**，然后勾选以下三项：

   | 图形 | 横轴 | 纵轴 |
   | --- | --- | --- |
   | **Total stress vs strain** | 应变（%） | 实测总应力（Pa） |
   | **Elastic stress vs strain** | 应变（%） | 重建的弹性应力（Pa） |
   | **Viscous stress vs strain rate** | 实际应变率（s⁻¹） | 重建的黏性应力（Pa） |

   也可选择 **Total stress vs strain rate**。只要勾选弹性或黏性分量，同一文件的各张图就使用相同的 SD 采样点，应变和实测总应力按该分析窗口去均值。只勾选总应力图时，使用保留原始偏置的波形预览，可在运行分析方法前导出。
3. 在 **Axis scale** 选择 **Physical units**（物理单位）、**Normalised**（归一化）或 **Physical and normalised**（两种都导出）。每个文件都按本次绘图窗口计算参考值：应变和应变率分别除以各自的最大绝对值，总应力、弹性应力和黏性应力统一除以**实测总应力的最大绝对值**，保留各应力分量的相对大小。归一化 CSV 同时保留有量纲的原值，参考值记录在 `manifest.json`。若参考值为零，可改选绘图窗口或物理单位。
4. 选择 **Separate figures per file** 可为每个勾选文件分别出图，选择 **Overlay matched files** 可按图形类型叠加。选择完整窗口或最后 N 圈，再点 **Export…**。默认导出 PNG，也可勾选矢量 PDF 和可编辑 MATLAB FIG。

配套 CSV 保存实际绘图点。分量图的 `_decomposition_curves.csv` 同时记录 SD 窗口内的相对时间、原采集时间、应变、应变率，以及总应力、弹性应力和黏性应力。

## 方法文献

- 傅里叶变换流变学。Wilhelm、Maring 与 Spiess（1998）。[Rheologica Acta](https://doi.org/10.1007/s003970050126)
- 弹性与黏性应力分解。Cho 等（2005）。[Journal of Rheology](https://doi.org/10.1122/1.1895801)
- 切比雪夫系数与周期内指标。Ewoldt、Hosoi 与 McKinley（2008）。[Journal of Rheology](https://doi.org/10.1122/1.2970095)
- 瞬态模量与 SPP。Rogers（2017）。[Rheologica Acta](https://doi.org/10.1007/s00397-017-1008-1)
