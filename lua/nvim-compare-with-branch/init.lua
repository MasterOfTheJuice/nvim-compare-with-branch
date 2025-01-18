local M = {}

-- Utility to create a floating window
default_config = {
  relative = "editor",
  width = math.floor(vim.o.columns * 0.8),
  height = math.floor(vim.o.lines * 0.8),
  row = math.floor(vim.o.lines * 0.1),
  col = math.floor(vim.o.columns * 0.1),
  style = "minimal",
  border = "rounded",
}

local function create_floating_window(content)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  local win = vim.api.nvim_open_win(buf, true, default_config)
  return buf, win
end

local function create_branch_selection_window(branches, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, branches)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.floor(vim.o.columns * 0.4),
    height = #branches + 2,
    row = math.floor((vim.o.lines - (#branches + 2)) / 2),
    col = math.floor((vim.o.columns - math.floor(vim.o.columns * 0.4)) / 2),
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "<cmd>lua require'buffer_git_diff'.on_branch_selected()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_var(buf, "branches", branches)
  vim.api.nvim_buf_set_var(buf, "callback", callback)

  return buf, win
end

function M.on_branch_selected()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local branches = vim.api.nvim_buf_get_var(buf, "branches")
  local callback = vim.api.nvim_buf_get_var(buf, "callback")

  local selected_branch = branches[cursor[1]]
  if callback and selected_branch then
    vim.api.nvim_win_close(0, true)
    callback(selected_branch)
  else
    vim.notify("Invalid selection.", vim.log.levels.ERROR)
  end
end

-- Run git command and return output
local function run_git_command(cmd)
  local handle = io.popen(cmd)
  if handle == nil then return nil end
  local result = handle:read("*a")
  handle:close()
  return vim.split(result, "\n")
end

-- Prompt the user to select a Git branch
local function select_git_branch(callback)
  local branches = run_git_command("git branch --all --format='%(refname:short)'")
  if not branches or #branches == 0 then
    vim.notify("No branches found in the repository.", vim.log.levels.ERROR)
    return nil
  end

  create_branch_selection_window(branches, callback)
end

-- Show diff for the active buffer
local function compare_with_branch()
  -- Get current file path
  local file_path = vim.fn.expand("%")
  if file_path == nil or file_path == "" then
    vim.notify("No file in the current buffer.", vim.log.levels.ERROR)
    return
  end

  -- Prompt for branch selection
  select_git_branch(function(selected_branch)
    -- Get git version of the file from the selected branch
    local git_content = run_git_command("git show " .. selected_branch .. ":" .. file_path)
    if not git_content or #git_content == 0 then
      vim.notify("File not found in the selected branch: " .. selected_branch, vim.log.levels.ERROR)
      return
    end

    -- Read the current file content
    local file_content = {}
    for line in io.lines(file_path) do
      table.insert(file_content, line)
    end

    -- Perform side-by-side diff
    local diff_command = string.format(
      "diff -u <(echo '%s') <(echo '%s')",
      table.concat(git_content, "\n"),
      table.concat(file_content, "\n")
    )
    local diff_output = run_git_command(diff_command)

    if not diff_output or #diff_output == 0 then
      vim.notify("No differences found.", vim.log.levels.INFO)
      return
    end

    -- Show diff in a floating window
    create_floating_window(diff_output)
  end)
end

-- Plugin setup
function M.setup()
  vim.api.nvim_create_user_command(
    "CompareWithBranch",
    function()
      compare_with_branch()
    end,
    { desc = "Show git diff for the active buffer with a selected branch" }
  )

  vim.api.nvim_set_keymap(
    "n",
    "<leader>gd",
    ":CompareWithBranch<CR>",
    { noremap = true, silent = true, desc = "Show git diff for the active buffer" }
  )
end

return M
