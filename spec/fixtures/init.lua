--- Builders for fake `$PYENV_ROOT` trees and project directories.
---
--- These create *real* directories, files, and symlinks under a temp path rather
--- than mocking the filesystem, because virtualenv classification depends on
--- genuine symlink behaviour (pyenv-virtualenv puts the real directory at
--- `versions/<py>/envs/<name>` and a symlink at `versions/<name>`). A mocked
--- filesystem would happily pass tests that break on a real pyenv install.
local M = {}

local uv = vim.uv

---Directories created during the current test, torn down by `M.cleanup()`.
---@type string[]
local created = {}

---@param path string
local function mkdirp(path)
  vim.fn.mkdir(path, "p")
end

---@param path string
---@param contents string
local function write(path, contents)
  mkdirp(vim.fs.dirname(path))
  local fd = assert(uv.fs_open(path, "w", tonumber("644", 8)))
  assert(uv.fs_write(fd, contents))
  assert(uv.fs_close(fd))
end

---Create a unique temp directory and register it for cleanup.
---@param label string?
---@return string
function M.tmpdir(label)
  local dir = vim.fn.tempname() .. (label and ("-" .. label) or "")
  mkdirp(dir)
  table.insert(created, dir)
  -- Canonicalise: on macOS the temp dir sits under /var, which is itself a
  -- symlink to /private/var. Handing back the unresolved path would make every
  -- path comparison against resolved code output fail for no real reason.
  return uv.fs_realpath(dir) or dir
end

---Write an executable stub that behaves enough like a Python interpreter for
---`vim.fn.executable()` checks and `--version` probes.
---@param path string
---@param version string
local function write_python_stub(path, version)
  write(path, ("#!/bin/sh\necho 'Python %s'\n"):format(version))
  assert(uv.fs_chmod(path, tonumber("755", 8)))
end

---Populate a version prefix: `<prefix>/bin/{python,python3}`.
---@param prefix string
---@param version string
local function make_prefix(prefix, version)
  mkdirp(prefix .. "/bin")
  write_python_stub(prefix .. "/bin/python", version)
  write_python_stub(prefix .. "/bin/python3", version)
end

---@class fixtures.PyenvRootOpts
---@field versions string[]?                  plain installed versions, e.g. { "3.12.4" }
---@field virtualenvs table<string,string[]>? map of python version -> virtualenv names
---@field global string?                      contents of `$PYENV_ROOT/version`
---@field shims boolean?                      create a `shims/` dir (default true)

---Build a fake `$PYENV_ROOT`.
---@param opts fixtures.PyenvRootOpts?
---@return string root absolute path to the fake PYENV_ROOT
function M.pyenv_root(opts)
  opts = opts or {}
  local root = M.tmpdir("pyenv-root")

  mkdirp(root .. "/versions")

  for _, version in ipairs(opts.versions or {}) do
    make_prefix(root .. "/versions/" .. version, version)
  end

  -- pyenv-virtualenv layout: real dir under `<py>/envs/<name>`, symlink at top level.
  for python_version, names in pairs(opts.virtualenvs or {}) do
    local base = root .. "/versions/" .. python_version
    if vim.fn.isdirectory(base) == 0 then
      make_prefix(base, python_version)
    end
    for _, name in ipairs(names) do
      local real = base .. "/envs/" .. name
      make_prefix(real, python_version)
      write(real .. "/pyvenv.cfg", ("home = %s/bin\nversion = %s\n"):format(base, python_version))
      assert(uv.fs_symlink(real, root .. "/versions/" .. name))
    end
  end

  if opts.global then
    write(root .. "/version", opts.global .. "\n")
  end

  if opts.shims ~= false then
    mkdirp(root .. "/shims")
    write(root .. "/shims/python", '#!/usr/bin/env bash\nexec pyenv exec python "$@"\n')
    assert(uv.fs_chmod(root .. "/shims/python", tonumber("755", 8)))
  end

  return root
end

---Build a project directory from a map of relative path -> file contents.
---Directories are created as needed. A `.venv` key of `true` creates a working
---virtualenv layout instead of a file.
---@param files table<string, string|boolean>?
---@return string dir absolute path to the project root
function M.project(files)
  local dir = M.tmpdir("project")
  for rel, contents in pairs(files or {}) do
    if contents == true then
      -- shorthand: build a venv-shaped directory (e.g. [".venv"] = true)
      make_prefix(dir .. "/" .. rel, "3.12.4")
      write(dir .. "/" .. rel .. "/pyvenv.cfg", "version = 3.12.4\n")
    else
      write(dir .. "/" .. rel, contents --[[@as string]])
    end
  end
  return dir
end

---Remove everything created since the last cleanup. Call from `after_each`.
function M.cleanup()
  for _, dir in ipairs(created) do
    vim.fn.delete(dir, "rf")
  end
  created = {}
end

return M
