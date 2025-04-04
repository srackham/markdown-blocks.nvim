-- Place in ~/.config/nvim/init.lua or preferably in a dedicated lua file
-- e.g., lua/custom/markdown_breaks.lua and require it: require('custom.markdown_breaks')

-- Module initialisation
local M = {}

-- Helper function to get visual selection range safely
local function get_visual_selection_range()
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  if start_line <= 0 or end_line < start_line then
    vim.notify("Error: Invalid visual selection.", vim.log.levels.ERROR)
    return nil, nil
  end
  return start_line, end_line
end

-- Function to add markdown line breaks to a range
-- Adds the specified break_str to the end of each line in the range.
---@param start_line number Starting line number (1-based)
---@param end_line number Ending line number (1-based)
---@param break_str string|nil The string to append as a line break (defaults to ' \\')
function M.markdown_add_line_breaks(start_line, end_line, break_str)
  break_str = break_str or ' \\' -- Default break is space + backslash

  -- Escape characters special to Vim's substitute command replacement part
  -- Most importantly: \ -> \\
  -- Using # as delimiter avoids issues with / in break_str (like <br/>)
  local vim_escaped_break_str = string.gsub(break_str, '\\', '\\\\')
  vim_escaped_break_str = string.gsub(vim_escaped_break_str, '#', '\\#') -- Escape delimiter

  local range = string.format("%d,%d", start_line, end_line)
  local cmd = string.format(":%ss#$#%s#g", range, vim_escaped_break_str)

  vim.cmd("silent " .. cmd)
end

-- Function to REMOVE known markdown line breaks and trailing whitespace from a range
-- Removes ' \', '<br>', '  ' (or more spaces) from the end of lines.
---@param start_line number Starting line number (1-based)
---@param end_line number Ending line number (1-based)
function M.markdown_remove_line_breaks(start_line, end_line)
  local range = string.format("%d,%d", start_line, end_line)

  -- Use # as delimiter for substitute commands to avoid issues with '/' in <br>
  -- 1. Remove specific break markers (' \' and '<br>') from the end of the line
  vim.cmd(string.format("silent :%ss# \\\\$##g", range)) -- Remove ' \' at EOL
  vim.cmd(string.format("silent :%ss#<br>$##g", range))  -- Remove '<br>' at EOL

  -- 2. Remove ALL remaining trailing whitespace (handles '  ' and any leftovers)
  --    \s\+ means one or more whitespace characters
  --    Need \\s\\+ in Lua string to get \s\+ for Vim regex
  vim.cmd(string.format("silent :%ss#\\s\\+$##g", range))
end

-- Toggle function - Decides whether to add or remove based on the first line
-- This function will be called by the keymap
---@param break_str_to_add string|nil Optional break string to use when adding (defaults to ' \\')
function M.toggle_markdown_line_break(break_str_to_add)
  local start_line, end_line = get_visual_selection_range()
  if not start_line then return end -- Error handled in helper

  -- Get the content of the first selected line
  local first_line_content = vim.api.nvim_buf_get_lines(0, start_line - 1, start_line, false)[1]

  local needs_removal = false
  if first_line_content then
    -- Check if the first line ends with any of the known break patterns
    -- Using Lua patterns:
    -- [ ]\\$  : space followed by backslash at the end
    -- <br>$   : <br> at the end
    -- %s%s$   : two or more whitespace characters at the end (%s matches whitespace)
    if string.match(first_line_content, [[\ \\$]]) or -- Space + Backslash
        string.match(first_line_content, "<br>$") or  -- <br> tag
        string.match(first_line_content, "%s%s+$")    -- Two or more spaces/whitespace chars
    then
      needs_removal = true
    end
  end

  local message = ""
  if needs_removal then
    M.markdown_remove_line_breaks(start_line, end_line)
    message = "Removed Markdown line breaks and trailing whitespace."
  else
    -- Use the provided break string or the default (' \\') within add function
    M.markdown_add_line_breaks(start_line, end_line, break_str_to_add)
    local added_break = break_str_to_add or ' \\'
    message = string.format("Added Markdown line break ('%s').", added_break)
  end

  -- Optional: Visual feedback (re-select, then deselect after delay)
  vim.cmd("normal! gv")        -- Re-select the previous visual area
  vim.defer_fn(function()
    vim.cmd("normal! <Esc>")   -- Exit visual mode
    vim.notify(message, vim.log.levels.INFO, { title = "Markdown Breaks" })
  end, 50)                     -- Adjust delay if needed
end

-- Create the visual mode mapping to call the toggle function
-- It will use the default break (' \\') when adding.
vim.keymap.set('v', '<Leader>mb', '<Cmd>lua toggle_markdown_line_break()<CR>', {
  noremap = true,
  silent = true, -- Suppress echoing the <Cmd> part
  desc = "Toggle Markdown backslash/br/space breaks"
})

-- Example of how you could map another key to add a *different* break type:
-- vim.keymap.set('v', '<Leader>mB', function() toggle_markdown_line_break('<br>') end, {
--   noremap = true,
--   silent = true,
--   desc = "Toggle Markdown <br>/space breaks"
-- })

print("Markdown line break toggle mapping(s) loaded.")

return M
