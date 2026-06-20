vim9script
# liv.std.process streaming companion (Vim only). Vim's if_lua cannot represent
# a job/channel value -- vim.call("job_start", ...) returns nil to Lua and any
# Lua-held job reference is dead -- so the job must live entirely in vimscript.
# This registry starts a job, holds it by a numeric id, and drives send/close/stop
# by that id. Callbacks (out_cb/err_cb/exit_cb) are Lua functions passed in as
# Funcrefs (Vim auto-converts a Lua function argument and holds the reference
# alive). They are assigned DIRECTLY as job-option fields (a vim9 `=>` lambda that
# wraps and calls a Lua Funcref fails to compile -- E1028), so the Lua callbacks
# take Vim's native signatures: out_cb/err_cb get (channel, msg); exit dispatch is
# done by a named def that first drops the registry entry (a re-entrant call()
# back into vimscript from inside a callback is rejected, so the Lua side cannot
# unlet) and then invokes the Lua exit Funcref with the status. The id is the only
# value that crosses back to Lua; data and args cross as real marshaled arguments,
# never interpolated into a command string. This is Vim 9 script (NOT legacy).

if exists('g:LivProc')
  finish
endif

g:LivProc = {jobs: {}, exits: {}, counter: 0}

# Exit handler bound per job via a partial carrying its id. Runs in vimscript
# context, so it can safely drop the registry entry before dispatching to Lua.
def g:LivProcOnExit(id: string, _job: any, status: number)
  const ExitCb = get(g:LivProc.exits, id, v:null)
  g:LivProcDrop(id)
  if type(ExitCb) == v:t_func
    ExitCb(status)
  endif
enddef

# Start `cmd` (a list) with line-mode stdout/stderr. OutCb is a Funcref (a Lua
# function) taking (channel, msg); ErrCb/ExitCb are Funcrefs or v:null. cwd is a
# string or v:null; env is a dict or v:null and EXTENDS the parent environment.
# Returns the id.
def g:LivProcStart(cmd: list<string>, OutCb: any, ErrCb: any, ExitCb: any, cwd: any, env: any): string
  g:LivProc.counter += 1
  const id = string(g:LivProc.counter)
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
  g:LivProc.exits[id] = ExitCb
  opts.exit_cb = function('g:LivProcOnExit', [id])
  const job = job_start(cmd, opts)
  if job_status(job) ==# 'fail'
    remove(g:LivProc.exits, id)
    throw 'liv.std.process.open: failed to start command'
  endif
  g:LivProc.jobs[id] = job
  return id
enddef

# Write raw bytes to the job's stdin.
def g:LivProcSend(id: string, data: string)
  ch_sendraw(g:LivProc.jobs[id], data)
enddef

# Close the job's stdin (signal EOF); does not stop the process.
def g:LivProcCloseIn(id: string)
  ch_close_in(g:LivProc.jobs[id])
enddef

# Stop the job.
def g:LivProcStop(id: string)
  if has_key(g:LivProc.jobs, id)
    job_stop(g:LivProc.jobs[id])
  endif
enddef

# Drop a finished/stopped job and its exit callback from the registry.
def g:LivProcDrop(id: string)
  if has_key(g:LivProc.jobs, id)
    remove(g:LivProc.jobs, id)
  endif
  if has_key(g:LivProc.exits, id)
    remove(g:LivProc.exits, id)
  endif
enddef
