# Omni Robotics R&D Project 使用规范

> GitHub Project：`Omni Robotics R&D`
> URL：https://github.com/users/YanYaoyuan/projects/3
> 重排基线：2026-08-26

## 字段

| 字段 | 值/规则 |
| --- | --- |
| Status | Backlog、Todo、In Progress、In Review、Blocked、Done |
| Priority | P0、P1、P2、P3；表示当前交付优先级，不只是技术严重度 |
| Area | SLAM、Navigation、Docking、Perception、Edge Agent、Cloud、Hardware |
| Iteration | 2026 W35、W36、W37；没有真实容量的工作保持空值 |
| Owner | 唯一主责显示值；开始前必须把 A/B/C 占位替换为真实姓名 |
| Deadline | 已进入当前 Iteration 的承诺项设为该周最后一天；Backlog 不设置 |
| Estimate | Fibonacci SP；当前 Iteration 单项最大 8，Backlog 的 13 SP 项排期前必须拆分 |

Iteration 日期按 `Asia/Shanghai`：W35 为 2026-08-24～08-30，W36 为 08-31～09-06，W37 为 09-07～09-13。

GitHub `Assignees` 表示实际账号执行人，自定义 `Owner` 是唯一主责的可读显示；主 Assignee 必须与 Owner 同一人。Project 的源 Issue/PR 标题为权威标题，CLI 偶发的内建 Title 缓存不得覆盖源内容。

## 状态语义

| Status | 进入条件 | 退出证据 |
| --- | --- | --- |
| Backlog | 已记录但未承诺近期容量 | 被选入 Iteration 并明确 Owner/AC |
| Todo | 已进入 Iteration，依赖已满足，可立即开始 | Owner 开始实现 |
| In Progress | 正在设计、编码或执行测试 | 创建 PR 或确认 blocked |
| In Review | PR/ADR/设计等待评审 | 合并、要求修改或 blocked |
| Blocked | 有明确外部依赖且当前无法继续 | blocker 解除并回到 Todo/In Progress |
| Done | 验收标准和证据全部满足 | 不再返工；新问题建新 Issue |

“发现了问题”不等于 `Todo`；“影响大”也不等于必须塞入当前 Iteration。

## 三人容量

- 每位开发者每个 Iteration 只承担一个主要交付 Issue；
- 当前 Iteration 的单个 Issue 最大 8 SP；Backlog 超过 8 SP 的事项在排期前拆为接口/core/ROS integration/hardware validation；
- 每周团队计划容量为 24 SP，Review 和临时故障从各自容量内消化；
- W35–W37 只排整机架构/运动安全、Mission C++、Docking C++ 三条主线；
- Cloud、App、算法增强和量产硬化默认 Backlog，除非它直接阻断上述链路。

## 当前 Iteration 模板

| Iteration | 主线 A | 主线 B | 主线 C |
| --- | --- | --- | --- |
| W35 | `PORT-01` 整机架构与接口冻结 | `MIS-01` C++ skeleton/golden | `DOCK-01` 硬件合同/skeleton |
| W36 | `BR-01` typed authority | `MIS-04` core/storage | `DOCK-04` core/safety |
| W37 | `READY-01` TF/定位/Planner gate | `MIS-02` async ROS RC | `DOCK-02` Matrix ROS RC |

Owner 使用负责人 A/B/C 占位，待三位真实成员确认后一次替换；任何事项进入 In Progress 前必须已绑定真实 Owner/Assignee。未列入表格的旧 Issue默认回到 Backlog，并清空 Iteration/Deadline。

## Issue 编写规则

标题格式：

```text
[KEY][P0] 中文动词开头的可交付标题
```

正文至少包含：

```markdown
## 背景
说明用户影响和当前证据。

## 范围
明确本 Issue 做什么、不做什么。

## 验收标准
- [ ] 可观测、可复现的结果
- [ ] 自动化测试/真机证据
- [ ] 文档与兼容影响

## 依赖
- blocked by / blocks

## 验证平台
- x86 / Matrix / Orin / S100 / Dog / VBot
```

代码缺陷如果已被 C++ 重写 Epic 完整覆盖，保留为 Epic checklist 或 Backlog evidence，不再作为当前 Iteration 的并行任务。

## 建议视图

1. **当前三人计划**：过滤 Iteration 非空，按 Iteration、Owner 分组。
2. **三条主线**：过滤 Key 为 PORT/BR/READY/MIS/DOCK，并结合当前 Iteration。
3. **阻断项**：Status=Blocked，按 Priority 排序。
4. **真实机器狗**：Area=Hardware，按依赖顺序。
5. **Backlog 评审**：Iteration 为空，按 Priority/Area 分组。
6. **Release Gate**：只放 bringup、联合 CI、Matrix/HIL/真机和 BOM Issue。

## 维护节奏

- 周一：确认三位负责人本周唯一主要交付；
- 每日：只更新 Status/blocker，不进行大规模重新估算；
- 周五：附测试/PR/日志证据，满足 AC 才 Done；
- Iteration 结束：未完成项重新评估，不自动滚入下一周；
- 架构/IDL 变更先合 `omni_navi` ADR/接口仓，再更新消费仓 Issue。
