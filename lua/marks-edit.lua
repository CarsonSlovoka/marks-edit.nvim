-- 可編輯的 A-Z 書籤清單；macOS/Linux、Neovim 0.10+，不需要第三方插件
-- 安裝：放到 ~/.config/nvim/plugin/marks-edit.lua，重新啟動 Neovim
-- 暫時載入：:luafile marks-edit.lua
-- :Marks 開啟清單；改字母、行、欄、路徑後 :w 套用；刪除整行會刪除該書籤
-- :Mark D ~/Downloads/ 是不切換視窗的快速設定指令（第 1 行、第 1 欄）
-- :w 只更新 Neovim 書籤，不會寫入目標檔案；跨工作階段保存沿用原本的 ShaDa 設定

local api, fn = vim.api, vim.fn
local editor, baseline, base_dir

local function fail(message)
  error("Marks: " .. message, 0)
end

local function absolute(path, cwd)
  if path:match("^%a[%w+.-]*://") then return path end
  path = vim.fs.normalize(path)
  if path:sub(1, 1) ~= "/" then
    path = cwd .. "/" .. path
  end
  return fn.simplify(path)
end

local function snapshot()
  local marks = {}
  for _, item in ipairs(fn.getmarklist()) do
    local name = item.mark:match("^'([A-Z])$")
    if name and item.pos[2] > 0 then
      local path = item.file or ""
      if item.pos[1] > 0 and api.nvim_buf_is_valid(item.pos[1]) then
        path = api.nvim_buf_get_name(item.pos[1])
      end
      marks[name] = {
        target = path ~= "" and absolute(path, fn.getcwd()) or ("@buffer:" .. item.pos[1]),
        line = item.pos[2],
        col = item.pos[3],
        off = item.pos[4] or 0,
      }
    end
  end
  return marks
end

local function same(a, b)
  if a == nil or b == nil then return a == b end
  return a.target == b.target and a.line == b.line and a.col == b.col
end

local function target_buffer(target)
  local number = target:match("^@buffer:(%d+)$")
  if number then
    number = tonumber(number)
    if number == 0 or not api.nvim_buf_is_valid(number) then
      fail("buffer 已不存在：" .. target)
    end
    return number
  end
  local buf = fn.bufadd(target)
  if buf <= 0 then fail("無法建立 buffer：" .. target) end
  return buf
end

local function assign(name, pos, buf)
  if not pos then
    api.nvim_del_mark(name)
  elseif fn.setpos("'" .. name,
        { buf or target_buffer(pos.target), pos.line, pos.col, pos.off or 0 }) ~= 0 then
    fail("無法設定書籤 " .. name)
  end
end

local function parse(lines)
  local wanted = {}
  for number, text in ipairs(lines) do
    if not text:match("^%s*$") and not text:match("^%s*#") then
      local name, row, col, path = text:match("^%s*([A-Z])%s+(%d+)%s+(%d+)%s+(.+)$")
      if not name then fail("第 " .. number .. " 行格式錯誤；範例：D 1 1 ~/Downloads/") end
      if wanted[name] then fail("第 " .. number .. " 行書籤重複：" .. name) end
      row, col = tonumber(row), tonumber(col)
      if row < 1 or col < 1 or row > 2147483647 or col > 2147483647 then
        fail("第 " .. number .. " 行：行與欄必須是 1 到 2147483647 的整數")
      end
      local target = path:match("^@buffer:%d+$") and path or absolute(path, base_dir)
      wanted[name] = { target = target, line = row, col = col, off = 0 }
      if same(wanted[name], baseline[name]) then wanted[name].off = baseline[name].off end
    end
  end
  return wanted
end

local function save()
  local wanted = parse(api.nvim_buf_get_lines(editor, 0, -1, false))
  local current, changes = snapshot(), {}
  for code = 65, 90 do
    local name = string.char(code)
    if not same(wanted[name], baseline[name]) then
      if not same(current[name], baseline[name]) then
        fail("書籤 " .. name .. " 已在其他地方改變；請 :q! 後重新 :Marks")
      end
      changes[#changes + 1] = { name = name, old = current[name], new = wanted[name] }
    end
  end
  -- 先驗證全部資料、準備 buffer，然後才修改任何書籤。
  for _, change in ipairs(changes) do
    if change.new then change.buf = target_buffer(change.new.target) end
  end
  local applied = {}
  local ok, err = pcall(function()
    for _, change in ipairs(changes) do
      applied[#applied + 1] = change
      assign(change.name, change.new, change.buf)
    end
  end)
  if not ok then
    local rollback_errors = {}
    for index = #applied, 1, -1 do
      local change = applied[index]
      local restored, message = pcall(assign, change.name, change.old)
      if not restored then rollback_errors[#rollback_errors + 1] = tostring(message) end
    end
    if #rollback_errors > 0 then
      fail(tostring(err) .. "；回復部分書籤失敗：" .. table.concat(rollback_errors, "; "))
    end
    fail(tostring(err))
  end
  baseline = wanted
  vim.bo[editor].modified = false
  vim.notify(("已套用 %d 個書籤變更"):format(#changes))
end

local function refresh()
  base_dir, baseline = fn.getcwd(), snapshot()
  local lines = {
    "# A-Z 書籤：修改後 :w 套用；:q! 放棄尚未套用的修改",
    "# 格式：書籤  行  欄  路徑；行、欄從 1 起算，欄以 byte 計算",
    "# 新增一行可建立書籤；刪除整行可刪除書籤；路徑可含空白，不需加引號",
    "# 範例：D 1 1 ~/Downloads/；@buffer:數字 代表無檔名的 buffer",
    "# 相對路徑以開啟清單時的目錄為準：" .. base_dir,
    "",
  }
  for code = 65, 90 do
    local name = string.char(code)
    local pos = baseline[name]
    if pos then
      if pos.target:find("[\r\n]") then fail("含換行字元的路徑無法顯示：" .. name) end
      lines[#lines + 1] = ("%s  %d  %d  %s"):format(name, pos.line, pos.col, pos.target)
    end
  end
  api.nvim_buf_set_lines(editor, 0, -1, false, lines)
  vim.bo[editor].modified = false
end

local function get_registers()
  local regs = {}
  for i = string.byte('A'), string.byte('Z') do
    table.insert(regs, string.char(i))
  end
  return regs
end

api.nvim_create_user_command("Marks", function()
  if not editor or not api.nvim_buf_is_valid(editor) then
    editor = api.nvim_create_buf(false, false)
    vim.bo[editor].buftype = "acwrite"
    vim.bo[editor].bufhidden = "wipe"
    vim.bo[editor].swapfile = false
    vim.bo[editor].modeline = false
    vim.bo[editor].undofile = false
    vim.bo[editor].filetype = "conf"
    api.nvim_buf_set_name(editor, "marks-edit://A-Z/" .. editor)
    api.nvim_create_autocmd("BufWriteCmd", { buffer = editor, callback = save })
    refresh()
  elseif not vim.bo[editor].modified then
    refresh()
  end
  local window = fn.bufwinid(editor)
  if window ~= -1 then
    api.nvim_set_current_win(window)
  else
    vim.cmd("botright split")
    api.nvim_win_set_buf(0, editor)
  end
end, { desc = "編輯 A-Z 書籤，:w 套用", force = true })

api.nvim_create_user_command("Mark", function(opts)
    local name, path = opts.args:match("^([A-Z])%s+(.+)$")
    if not name then
      fail("用法：:Mark D ~/Downloads/")
    end
    assign(name, { target = absolute(path, fn.getcwd()), line = 1, col = 1, off = 0 })
  end,
  {
    nargs = "+",
    desc = "設定大寫書籤：:Mark D ~/Downloads/",
    force = true,
    complete = function(arg_lead, cmd_line)
      local argc = #(vim.split(cmd_line, "%s+")) - 1
      if argc == 1 then
        return get_registers()
      end
      return vim.fn.getcompletion(vim.fn.expand(arg_lead), "file")
    end
  }
)
