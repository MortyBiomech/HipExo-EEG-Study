# PilotTest3 剩余输出脚本

本包包含 get_4_gait_events.m、task4_step1_check_neck_data.m、task4_step2_neck_coherence_pilot.m。替换当前 PilotTest3 流程中的同名文件；不要覆盖 PilotTest2 独立项目中的文件。

继续使用原来的 PilotTest3 config_paths.m、subject_P3_*_infos.m、EEGLAB、load_xdf 和步态检测依赖。不要使用先前带 p3_bids_stage 的配置。本包每个脚本内置路径函数，没有迁移或发布步骤。

默认输出容器 C:\2026SSArbeit\data\PilotTest3_BIDS。

| 脚本 | 最终目录 |
|---|---|
| get_4_gait_events | derivatives/p3gaitevents/sub-Pilot33/ses-day2条件/emg，以及同级 figures |
| task4_step1_check_neck_data | derivatives/p3neckqc/sub-Pilot33/reports/desc-day2Run001Session |
| task4_step2_neck_coherence_pilot | derivatives/p3neckcoherence/sub-Pilot33/ses-day2条件/eeg |
| Step2 自动生成的对齐输入 | derivatives/p3neckaligned/sub-Pilot33/ses-day2条件/reports/desc-run001Aligned |

上表的 day、subject、condition、run 由实际输入生成；Step1 的报告文件夹名称还包含 sessionFilter，防止不同筛选范围混写。目录无脚本版本号或运行时间戳。BIDSVersion 是规范版本，保留在 dataset_description.json 中。MAT 的 -v7.3 是文件格式选项，不能作为脚本版本删除。

运行方式：

```matlab
% 独立事件脚本仅在需要单独检测事件时运行。
get_4_gait_events

% Step1 -> Step2，直接传输出路径，不需手动寻找报告目录。
[report, overview, walkingReport, qcDir] = ...
    task4_step1_check_neck_data('config_paths.m');
opt = struct('session','NoExoPre','run','001');
out = task4_step2_neck_coherence_pilot(qcDir,opt);
```

EMG 主预处理脚本已经保存 gait event MAT 时，可直接将其提供给 Step2 的 opt.eventsFile，不必为了目录组织重复检测。Step2 接受本包的 gait event MAT/TSV；TSV 同时记录相对 GRF 首样本的 onset 和绝对 XDF 时间 lsl_time，Step2 使用后者，不把 GRF 零点误认为 EEG/EMG 零点。

改输出根目录：独立事件脚本修改开头 derivativesContainer；Step1 在配置中设置 neck_qc.derivativesContainer；Step2 设置 opt.derivativesContainer。应给三者同一个容器路径。

Step1 表格改用 TSV，Step2 同时兼容新 TSV 和旧 CSV。审计表保留既有列名；报告内部的索引文件名保留，通过 file_selection.tsv 对应源文件。对齐缓存保留 aligned_pre.mat / coherence_pre.mat 作为下游接口。报告和缓存属于自定义衍生分析产物，不声称所有内部文件都对应正式 BIDS EMG schema；本次不是原始数据转换，也未执行官方 BIDS validator。

固定目录重跑会覆盖同名自动结果。已有 human_review.tsv、walking_human_review.tsv 不覆盖；重跑后需对照新的检查结果核对这些人工记录。筛选范围变化可能使旧的编号诊断文件残留，以本次 file_selection.tsv 和汇总表为准。

本次保留信号处理、事件检测、相干性计算及 DRAFT 判定逻辑。修改输出目录不代表 Task4 方法学确认、同步验证或清理后比较已经完成。

当前旧文件中，load_emg_data_eeg_structure_V2.m 和 batch_time_warping_and_plotting.m 已使用 derivatives 路径，未在本包中修改。check_steptime.m 没有现成的文件保存调用，本次未增加新输出。subject 信息、config 和 chanlocs 是输入/配置；xdf_to_emg_bids.py 是原始数据转换，不在此次范围。

验证：三个 MATLAB 文件通过 MISS_HIT 静态语法检查；当前环境没有 MATLAB/EEGLAB，尚未执行真实数据测试。
