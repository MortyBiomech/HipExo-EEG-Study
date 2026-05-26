# Collaboration Guide

This document explains how to work with this repository as a team.
Please read it carefully before making any changes to the codebase.

---

## 1. Initial Setup

### 1.1 Clone the repository

```bash
git clone https://github.com/MortyBiomech/HipExo-EEG-Study.git
cd HipExo-EEG-Study
```

### 1.2 Set up your local config

The file `config/study_config.m` is not tracked by git because it contains
local paths that differ per machine. Copy the template and fill in your paths:

```bash
cp config/study_config_template.m config/study_config.m
```

Then open `config/study_config.m` and set `config.data_root` to wherever
you store the data on your local machine or the shared network drive.
**Never commit `study_config.m` to git.**


---

## 2. Branch Structure

```
main          <- stable pipeline only - never work here directly
  |
  └── dev     <- integration branch - your pull requests go here
        |
        └── feature/xxx   <- your personal working branch
```

**You will only ever work on `feature/` branches.**
You cannot push directly to `main` or `dev` - GitHub will reject it.

---

## 3. Daily Workflow

### Step 1 - Always start by updating dev

```bash
git checkout dev
git pull origin dev
```

### Step 2 - Create your feature branch from dev

```bash
git checkout -b feature/your-descriptive-name
```

Name your branch clearly, for example:

- `feature/stage3-ersp-analysis-<YOUR_NAME>`
- `feature/stage2-amica-preprocessing-<YOUR_NAME>`
- `feature/utils-bad-channel-detection-<YOUR_NAME>`

### Step 3 - Work on your code

Make changes, test them, then commit regularly with meaningful messages:

```bash
git add filename.m
git commit -m "Add ERSP computation for stage 3 epoching"
```

Good commit messages:

```
✅ Add ERSP computation for stage 3 epoching
✅ Fix hysteresis threshold in detect_gait_events
✅ Update study_config_template with new subject list
```

Bad commit messages:

```
❌ fix
❌ changes
❌ update stuff
❌ asdfgh
```

### Step 4 - Keep your branch up to date with dev

If others have merged changes into `dev` while you were working,
bring those changes into your branch to avoid conflicts later:

```bash
git checkout dev
git pull origin dev
git checkout feature/your-descriptive-name
git merge dev
```

Resolve any conflicts, then continue working.

### Step 5 - Push your branch to GitHub

```bash
git push origin feature/your-descriptive-name
```

### Step 6 - Open a Pull Request

1. Go to the repository on GitHub
2. Click **"Compare & pull request"** next to your branch
3. Set the base branch to **`dev`** (not `main`)
4. Write a short description of what you changed and why
5. Request a review from Morteza
6. Wait for approval before merging

---

## 4. Code Standards

### Every function must have a header comment

```matlab
function output = my_function(input1, input2)
% MY_FUNCTION  One-line description of what this does.
%
% Inputs:
%   input1  - description
%   input2  - description
%
% Output:
%   output  - description
```

### General rules

- No hardcoded paths - use `config.data_root` from `study_config.m`
- No hardcoded subject numbers or condition names - use `config.subjects`
  and `config.conditions`
- Test your code on at least one subject before opening a pull request
- Delete your feature branch after it has been merged

---

## 5. Data Rules

- **Never commit data files to git** - no `.xdf`, `.set`, `.fdt`, `.mat`
- Data is stored on the shared network drive - ask Morteza for access
- If you accidentally stage a data file, remove it before committing:

```bash
git reset HEAD filename.mat
```

- If you accidentally committed a large file, tell Morteza immediately
  before pushing - it is much easier to fix before it reaches GitHub

---

## 6. Asking for Help

If something is unclear or broken:

1. First check if the issue is in your local `study_config.m`
2. Check the existing issues on GitHub - someone may have had the same problem
3. If it is a new problem, open a GitHub Issue with:
   - What you were trying to do
   - What error message you got (copy the full error, not a screenshot)
   - Which file and line number the error points to

---

## 7. Quick Reference

| Action | Command |
|--------|---------|
| Update dev | `git checkout dev && git pull` |
| New branch | `git checkout -b feature/name` |
| Stage file | `git add filename.m` |
| Commit | `git commit -m "descriptive message"` |
| Push branch | `git push origin feature/name` |
| Merge dev into your branch | `git merge dev` |
| Check status | `git status` |
| See history | `git log --oneline` |

---

*For questions about the pipeline itself, contact Morteza.
For questions about git, check https://docs.github.com or open a GitHub Issue.*
