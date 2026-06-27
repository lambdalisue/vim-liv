vim9script
# liv.std.process Vim companion (autoload). Vim-only: Neovim uses the native
# _nvim backend and never sources this. Auto-sourced on first reference to
# liv#std#process#Start (etc.), so the Lua leaf no longer :sources it explicitly.
#
# Vim's if_lua cannot represent a job/channel value (vim.call("job_start", ...)
# returns nil to Lua), so the job lives entirely here: held by a numeric id, with
# write/close/stop driven by that id. The registry is a SCRIPT-LOCAL var, so a
# vendored copy at a different autoload path (e.g. mate#vendor#liv#std#process#)
# gets its OWN isolated registry and cannot collide with another liv's. The
# exit_cb dispatches to the Lua callback and then drops the registry entry.
# Vim 9 script (NOT legacy).

var registry = {jobs: {}, exits: {}, counter: 0}

# Exit handler bound per job via a partial carrying its id. Runs in vimscript
# context, so it can safely drop the registry entry before dispatching to Lua.
def OnExit(id: string, _job: any, status: number)
  const ExitCb = get(registry.exits, id, v:null)
  Drop(id)
  if type(ExitCb) == v:t_func
    ExitCb(status)
  endif
enddef

# Start `cmd` (a list) with line-mode stdout/stderr. OutCb is a Funcref (a Lua
# function) taking (channel, msg); ErrCb/ExitCb are Funcrefs or v:null. cwd is a
# string or v:null; env is a dict or v:null and EXTENDS the parent environment.
# Returns the id.
export def Start(cmd: list<string>, OutCb: any, ErrCb: any, ExitCb: any, cwd: any, env: any): string
  registry.counter += 1
  const id = string(registry.counter)
  var opts: dict<any> = {out_mode: 'nl', err_mode: 'nl'}
  opts.out_cb = OutCb
  if type(ErrCb) == v:t_func
    opts.err_cb = ErrCb
  endif
  if type(cwd) == v:t_string
    opts.cwd = cwd
  endif
  if type(env) == v:t_dict
    opts.env = env
  endif
  registry.exits[id] = ExitCb
  opts.exit_cb = function(OnExit, [id])
  const job = job_start(cmd, opts)
  if job_status(job) ==# 'fail'
    remove(registry.exits, id)
    throw 'liv.std.process.open: failed to start command'
  endif
  registry.jobs[id] = job
  return id
enddef

# Write raw bytes to the job's stdin.
export def Send(id: string, data: string)
  ch_sendraw(registry.jobs[id], data)
enddef

# Close the job's stdin (signal EOF); does not stop the process.
export def CloseIn(id: string)
  ch_close_in(registry.jobs[id])
enddef

# Stop the job.
export def Stop(id: string)
  if has_key(registry.jobs, id)
    job_stop(registry.jobs[id])
  endif
enddef

# Drop a finished/stopped job and its exit callback from the registry.
def Drop(id: string)
  if has_key(registry.jobs, id)
    remove(registry.jobs, id)
  endif
  if has_key(registry.exits, id)
    remove(registry.exits, id)
  endif
enddef
