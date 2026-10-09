# PilotTest3：三个脚本直接输出版 v1.1.0

用本包三个 .m 文件替换原来的同名脚本。继续使用你原来的 PilotTest3 config_paths.m、subject_P3_*_infos.m、EEGLAB、load_xdf 和步态检测函数。不使用上一版带 p3_bids_stage 的 config_paths.m。本包没有迁移、临时目录整理或发布步骤，保存函数直接写入最终目录。

默认输出容器为 C:\2026SSArbeit\data\PilotTest3_BIDS。需要改位置时，修改前两个脚本开头的 derivativesContainer；任务二可通过 opt.outputRoot 指定同一容器。原始数据路径仍由原来的 config_paths.m 配置。

运行顺序：

```matlab
emg_processing_pipeline_all_sessions
plot_existing_session_gait_cycles
outDir = task2_mode_characterisation( ...
    'C:\2026SSArbeit\data\PilotTest3_BIDS\derivatives\p3emgprep-v110\sub-Pilot33');
```

目录示例：

```text
PilotTest3_BIDS/derivatives/
  p3emgprep-v110/
    dataset_description.json
    sub-Pilot33/ses-day2Exo1aquaplus/emg/
      sub-Pilot33_ses-day2Exo1aquaplus_task-Default_run-001_desc-CleanEpochedWithEvents_emg.set
      sub-Pilot33_ses-day2Exo1aquaplus_task-Default_run-001_desc-timewarped_emg.mat
      ...
    sub-Pilot33/ses-day2Exo1aquaplus/figures/
  p3gaitcomparison-v110/
    dataset_description.json
    sub-Pilot33/figures/
  p3modecharacterisation<TIMESTAMP>-v110/
    dataset_description.json
    reports/
      desc-modeSummary_table.tsv
      desc-modecharacterisation_data.mat
      desc-modecharacterisation_figure.png
      desc-modecharacterisation_figure.fig
      ...
```

day 和条件组合为 session 标签，避免 day1/day2 同名条件冲突。比较图跨条件，因此放在受试者级 figures，并在 desc 中记录 day。任务二可汇总多个受试者、day 和条件，因此完整汇总存于该次分析的 reports；表中保留 Subject、Day、Run、Condition。每个处理流程生成 dataset_description.json，数据来源另存 provenance.json。SET 所需 FDT 由 EEGLAB 在同一目录直接保存。

预处理和对比图使用固定目录；重复相同选择会覆盖对应文件。任务二每次创建新目录。选择部分 session 重新预处理时，其他 session 的旧结果仍保留，后续脚本可能同时读取它们。不要混用不同预处理参数；更改参数后应对目标比较的全部条件重新运行，或使用新的输出容器。

保留原信号处理、筛选和指标计算逻辑。模式为 eco(+)、sport(++)、boost(+++) assistive；transparent(0)；aqua(-)、aquaplus(--) resistive。任务二仍读取未经每条件峰值归一化的 envelope epochs，按相同受试者/day/run 的 NoExoPre 归一化指标。

本包采用 BIDS Derivatives 目录、实体和描述元数据约定；MAT、FIG、TSV 指标表和图形是自定义分析产物，并非声称已有官方 EMG 衍生数据 schema 或已通过官方验证器。TSV 为 MATLAB 原生表导出，保留其缺失值表示。没有转换或修改原始 XDF/BDF，也没有改动 PilotTest2。

当前环境没有 MATLAB/EEGLAB，无法执行真实数据测试。请先运行一个 session 检查输出，再运行包含 NoExoPre 的全部条件。
