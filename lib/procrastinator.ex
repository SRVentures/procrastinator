defmodule Procrastinator do
  @moduledoc """
  Batches Tasks
  """
  use GenServer

  @callback process([any]) :: any
  @callback timeout :: integer
  @callback status([any]) :: :overflow | :full | :continue
  @callback name :: atom

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Procrastinator

      ## Client API
      def start_link do
        GenServer.start_link(
          __MODULE__,
          nil,
          name: name
        )
      end

      def push(data), do: GenServer.cast(name, {:push, data})

      def get, do: GenServer.call(name, :get)

      ## Server Callbacks

      def init(_), do: {:ok, []}

      def handle_cast({:push, data}, bucket) do
        case status([data | bucket]) do
          :overflow ->
            process_bucket(bucket)
            {:noreply, [data], timeout}
          :full ->
            process_bucket([data | bucket])
            {:noreply, []}
          :continue -> {:noreply, [data | bucket], timeout}
        end
      end

      def handle_call(:get, _, data), do: {:reply, data, data, timeout}

      def handle_info(:timeout, bucket) do
        process_bucket(bucket)
        {:noreply, []}
      end

      defp process_bucket(bucket) do
        bucket
        |> Enum.reverse
        |> process
      end
    end
  end
end
