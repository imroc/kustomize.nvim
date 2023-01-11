local utils = require("kustomize.utils")
local scan = require("plenary.scandir")
local path = require("plenary.path")

local M = {}

function M.get_resources(bufNr)
  local q = require("vim.treesitter.query")
  local language_tree = vim.treesitter.get_parser(bufNr)
  local syntax_tree = language_tree:parse()
  local root = syntax_tree[1]:root()

  local query = vim.treesitter.parse_query(
    "yaml",
    [[
(
(document
(block_node
(block_mapping
(block_mapping_pair key: (flow_node) @key_name value:
(block_node
(block_sequence
(block_sequence_item
(flow_node)@resource)))))))
  (#match? @key_name "resources")
) @resource
]]
  )
  local resources = {}
  for _, captures, _ in query:iter_matches(root, bufNr) do
    -- resource is second capture
    table.insert(resources, q.get_node_text(captures[2], bufNr))
  end
  return resources
end

M.list = function()
  local bufName = vim.api.nvim_buf_get_name(0)
  local bufNr = vim.api.nvim_win_get_buf(0)
  local fileName = vim.fs.basename(bufName)

  if not utils.is_kustomization_yaml(fileName) then
    utils.error("buffer is not a kustomization.yaml")
    return
  end

  if not utils.is_treesitter_available(bufNr) then
    utils.error("could not load nvim-treesitter")
    return
  end
  local resources = M.get_resources(bufNr)
  local files = {}
  for _, r in ipairs(resources) do
    table.insert(files, { filename = M.build_paths(r) })
  end
  if next(files) == nil then
    utils.warn("could not find any resources in " .. bufName)
  else
    M.set_list(files)
  end
end

M.set_list = function(items)
  -- TODO: option to configure loc list or qf list
  vim.fn.setqflist({}, " ", { title = "Kustomize", id = "$", items = items })
  vim.cmd.copen()
end

M.build_paths = function(resource)
  local function join_paths(a, b)
    local file = path:new(a, b)
    local absolute = path:new({ file, sep = utils.path_separator() }):absolute()
    return absolute
  end
  if not (utils.is_module_available("plenary")) then
    utils.error("Could not load https://github.com/nvim-lua/plenary.nvim")
    return
  end
  local bufName = vim.api.nvim_buf_get_name(0)
  -- resources are relative to the current kustomization.yaml
  -- so we need to track the current directory to build a valid path
  local dirName = vim.fs.dirname(bufName)
  if path:new(dirName, resource):is_file() or path:new(dirName, resource):is_dir() then
    return join_paths(dirName, resource)
  else
    utils.warn("This is not a valid file or directory: " .. resource)
  end
end

M.print = function()
  if not utils.is_module_available("plenary") then
    utils.error("Could not load https://github.com/nvim-lua/plenary.nvim")
    return
  end
  local bufName = vim.api.nvim_buf_get_name(0)
  local fileName = vim.fs.basename(bufName)
  local resourceList = {}
  if utils.is_kustomization_yaml(fileName) then
    local dirName = vim.fs.dirname(bufName)
    local resources = scan.scan_dir(dirName, { hidden = false, depth = 1, add_dirs = true })
    for _, r in pairs(resources) do
      if not string.find(r, "kustomization") then
        local baseName = vim.fs.basename(r)
        if path:new(r):is_file() then
          table.insert(resourceList, "  - " .. baseName)
        elseif path:new(r):is_dir() then
          table.insert(resourceList, "  - " .. baseName .. "/")
        else
          utils.warn("This is not a valid file or directory: " .. r)
        end
      end
    end
  else
    utils.warn("Buffer is not a kustomization.y(a)ml")
  end
  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_lines(0, row, row, true, resourceList)
end

return M
