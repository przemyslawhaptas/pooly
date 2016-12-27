defmodule Pooly.Server do
  use GenServer
  import Supervisor.Spec

  defmodule State do
    defstruct sup: nil, size: nil, mfa: nil, worker_sup: nil, workers: nil
  end

  ## API

  def start_link(sup, pool_config) do
    GenServer.start_link(__MODULE__, [sup, pool_config], name: __MODULE__)
  end

  ## Callbacks

  def init([sup, pool_config]) when is_pid(sup) do
    do_init(pool_config, %State{sup: sup})
  end

  def handle_info(:start_worker_supervisor, state = %{sup: sup, mfa: mfa, size: size}) do
    {:ok, worker_sup} = Supervisor.start_child(sup, supervisor_spec(mfa))
    workers = prepopulate(size, worker_sup)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  ## Helper functions

  defp do_init([{:mfa, mfa} | config_tail], state) do
    do_init(config_tail, %{state | mfa: mfa})
  end
  defp do_init([{:size, size} | config_tail], state) do
    do_init(config_tail, %{state | size: size})
  end
  defp do_init([_unhandled | config_tail], state) do
    do_init(config_tail, state)
  end
  defp do_init([], state) do
    send(self, :start_worker_supervisor)
    {:ok, state}
  end

  defp supervisor_spec(mfa) do
    opts = [restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [mfa], opts)
  end
end
