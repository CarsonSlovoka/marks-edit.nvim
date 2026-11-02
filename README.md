# Marks-edit

可以直接用以下的方式來設定書籤

```vim
:call setpos("'D", [bufadd(expand('~/Downloads/')), 1, 1, 0])
```

但是要輸入的有點多, 而且修改不直覺

本插件可提供完整的`marks`的buffer, 提供編輯, 並且保存後即可套件

## 安裝

```lua
vim.pack.add({ "https://github.com/CarsonSlovoka/mark-edit.nvim" })
-- vim.cmd.packadd("mark-edit.nvim")
require("marks-edit")
```


## 使用

```vim
:Marks                 " 開啟清單；改字母、行、欄、路徑後 :w 套用；刪除整行會刪除該書籤。
:Mark D ~/Downloads/   " 是不切換視窗的快速設定指令（第 1 行、第 1 欄）
```

> [!NOTE] :w 只更新 Neovim 書籤，不會寫入目標檔案；跨工作階段保存沿用原本的 ShaDa 設定
