local task = require "blink.lib.task"

local emojis

---Include the trigger character when accepting a completion.
---@param context blink.cmp.Context
local function transform(items, context)
  local kind = require("blink.cmp.types").CompletionItemKind.Text

  return vim.tbl_map(function(entry)
    return vim.tbl_deep_extend("force", entry, {
      kind = kind,
      textEdit = {
        newText = entry.textEdit and entry.textEdit.newText
          or entry.insertText
          or entry.label,
        range = {
          start = {
            line = context.cursor[1] - 1,
            character = context.bounds.start_col - 2,
          },
          ["end"] = {
            line = context.cursor[1] - 1,
            character = context.cursor[2],
          },
        },
      },
    })
  end, items)
end

---@param value string|string[]|fun():string[]
---@return fun():string[]
local function as_func(value)
  if type(value) == "string" then
    return function()
      return { value }
    end
  elseif type(value) == "table" then
    return function()
      return value
    end
  elseif type(value) == "function" then
    ---@cast value fun(self: blink_emoji.Source): string[]
    return value
  end

  return function()
    return {}
  end
end

local function keyword_pattern(line, trigger_characters)
  -- Pattern is taken from `cmp-emoji` for similar trigger behavior.
  for _, c in ipairs(trigger_characters) do
    local pattern = [=[\%([[:space:]"'`]\|^\)\zs]=]
      .. c
      .. [=[[[:alnum:]_\-\+]*]=]
      .. c
      .. [=[\?]=]
      .. "$"
    if vim.regex(pattern):match_str(line) then
      return true
    end
  end
  return false
end

---@type blink.cmp.Source
local M = {}

---@class blink_emoji.Config
---@field insert boolean
---@field trigger string|string[]|fun():string[]

---@param opts? blink_emoji.Config
---@return blink.cmp.Source
function M.new(opts)
  local self = setmetatable({}, { __index = M })
  self.config = vim.tbl_deep_extend("keep", opts or {}, {
    insert = true,
    trigger = function()
      return { ":" }
    end,
  })
  self.get_trigger_characters = as_func(self.config.trigger)
  if not emojis then
    emojis = require("blink-emoji.emojis").get()
  end
  return self
end

---@param context blink.cmp.Context
function M:get_completions(context, callback)
  local cancelled = false
  local completion_task = task.new(function(resolve)
    vim.schedule(function()
      if cancelled then
        return
      end

      local cursor_before_line = context.line:sub(1, context.cursor[2])
      if
        not keyword_pattern(cursor_before_line, self:get_trigger_characters())
      then
        callback {
          is_incomplete_forward = false,
          is_incomplete_backward = false,
          items = {},
        }
        resolve()
        return
      end

      callback {
        is_incomplete_forward = true,
        is_incomplete_backward = true,
        items = transform(emojis, context),
      }
      resolve()
    end)

    return function()
      cancelled = true
    end
  end)

  return function()
    completion_task:cancel()
  end
end

---`newText` is used for `ghost_text`, thus it is set to the emoji name in `emojis`.
---Change `newText` to the actual emoji when accepting a completion.
function M:resolve(item, callback)
  local resolved = vim.deepcopy(item)
  if self.config.insert and resolved.textEdit then
    resolved.textEdit.newText = resolved.insertText
  end
  return callback(resolved)
end

return M
