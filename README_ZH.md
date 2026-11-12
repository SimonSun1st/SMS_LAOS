# SMS-LAOS

SMS-LAOS 是用于分析大振幅振荡剪切（LAOS）数据的 MATLAB 应用，支持傅里叶变换分析（FT-LAOS）、应力分解（SD）和物理过程序列分析（SPP）。[English guide](README.md)

## 启动

已在 MATLAB R2026b 和 Signal Processing Toolbox 环境下测试。在 MATLAB 中打开项目文件夹，运行

```matlab
launch_SMS_LAOS
```

## 分析数据

1. 点击 **Load data** 选择文件，或用 **Add folder** 批量导入。支持 DAT、CSV、TXT、TSV、XLS 和 XLSX。
2. 在 **Data & units** 中设置时间、应变和应力的列号及单位。默认依次读取第 1–3 列，单位为秒、百分比应变和 Pa。同一批文件共用这组设置。可在预览区查看波形、应变率和估计频率。
3. 勾选需要的方法，在对应标签页调整参数，再点击 **Analyze selected** 分析选中的文件，或点击 **Analyze all** 分析全部文件。
4. 左侧文件列表显示进度。**Finished** 表示所选方法均已完成且没有触发质量警告。**Review (SPP)** 等状态会在括号中列出需要复核的方法，单击该行即可查看具体原因。

## 导出

在 **Export** 页点击 **Export results**，可按当前勾选的方法导出整批文件的有效结果。

要导出指定应变幅值的李萨如图，在 **Target strain amplitude (%)** 中输入目标幅值，在 **Tolerance (percentage points)** 中输入容差。例如，目标为 10%、容差为 0.1 个百分点时，会匹配实测幅值在 9.9% 至 10.1% 之间的文件。选择 PNG、PDF 或 MATLAB FIG，再点击 **Export Lissajous only**。图形直接使用实测波形，可在运行分析方法之前导出。
