defmodule Pooly.WorkerSupervisor do
  use Supervisor

  def start_link(pool_server, {_, _, _} = mfa) do
    Supervisor.start_link(__MODULE__, [pool_server, mfa])
  end

  def init([pool_server, {module, function, arguments}]) do
    Process.link(pool_server)

    worker_opts = [restart: :permanent, shutdown: 5_000, function: function]
    children = [worker(module, arguments, worker_opts)]
    opts = [strategy: :simple_one_for_one, max_restarts: 5, max_seconds: 5]

    supervise(children, opts)
  end
end
