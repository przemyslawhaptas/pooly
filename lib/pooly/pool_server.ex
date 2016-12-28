defmodule Pooly.PoolServer do
  use GenServer
  import Supervisor.Spec

  defmodule State do
    defstruct [
      pool_sup: nil,
      worker_sup: nil,
      monitors: nil,
      size: nil,
      workers: nil,
      name: nil,
      mfa: nil
    ]
  end

  ## API

  def start_link(pool_sup, pool_config) do
    GenServer.start_link(__MODULE__, [pool_sup, pool_config], name: server_name(pool_config[:name]))
  end

  def checkout(pool_name) do
    GenServer.call(server_name(pool_name), :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(server_name(pool_name), {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(server_name(pool_name), :status)
  end

  ## Callbacks

  def init([pool_sup, pool_config]) when is_pid(pool_sup) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    do_init(pool_config, %State{pool_sup: pool_sup, monitors: monitors})
  end

  def handle_call(:checkout, {from_pid, _ref}, %{workers: available_workers, monitors: monitors} = state) do
    case available_workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}
      [] ->
        {:reply, :noproc, state}
    end
  end

  def handle_call(:status, _from, %{workers: workers, monitors: monitors} = state) do
    {:reply, {length(workers), :ets.info(monitors, :size)}, state}
  end

  def handle_cast({:checkin, worker}, %{workers: workers, monitors: monitors} = state) do
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        {:noreply, %{state | workers: [pid | workers]}}
      [] ->
        {:noreply, state}
    end
  end

  def handle_info(:start_worker_supervisor, state = %{pool_sup: pool_sup, name: name, mfa: mfa, size: size}) do
    {:ok, worker_sup} = Supervisor.start_child(pool_sup, supervisor_spec(name, mfa))
    workers = prepopulate(size, worker_sup)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  # Handle consumer crash
  def handle_info({:DOWN, ref, _, _, _}, state = %{monitors: monitors, workers: workers}) do
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid | workers]}
        {:noreply, new_state}
      [[]] ->
        {:noreply, state}
    end
  end

  # Handle worker supervisor crash
  def handle_info({:EXIT, worker_sup, reason}, state = %{worker_sup: worker_sup}) do
    {:stop, reason, state}
  end

  # Handle worker crash
  ## def handle_info({:EXIT, pid, _reason}, state = %{monitors: monitors, workers: workers, pool_sup: pool_sup}) do ## This is what was in the book
  def handle_info({:EXIT, pid, _reason}, state = %{monitors: monitors, workers: workers, worker_sup: worker_sup}) do ##
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        ## new_state = %{state | workers: [new_worker(pool_sup) | workers]} ## This is what was in the book
        new_state = %{state | workers: [new_worker(worker_sup) | workers]}
        {:noreply, new_state}
      [[]] ->
        {:noreply, state}
    end
  end

  ## Helper functions
  defp server_name(pool_name) do
    :"#{pool_name}Server"
  end

  defp do_init([{:name, name} | config_tail], state) do
    do_init(config_tail, %{state | name: name})
  end
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

  defp supervisor_spec(name, mfa) do
    opts = [id: name <> "WorkerSupervisor", restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [self, mfa], opts)
  end

  defp prepopulate(size, sup) do
    do_prepopulate(size, sup, [])
  end

  defp do_prepopulate(size, sup, workers) when size > 0 do
    do_prepopulate(size - 1, sup, [new_worker(sup) | workers])
  end
  defp do_prepopulate(_size, _sup, workers) do
    workers
  end

  defp new_worker(sup) do
    {:ok, worker} = Supervisor.start_child(sup, [[]])

    worker
  end
end
