defmodule Procrastinator do
  @moduledoc """
  A behavior module for batching/procrastinating work.

  One procrastinator is defined per app. In the future this may change, but the
  original use was to aggregate results coming from multiple processes, so the
  underlying GenServer is assigned a name through the `name/0` callback, and so
  there will exist one instance per defined module that uses Procrastinator.

  The Procrastinator has a bucket, to which data can be added using the `push/1`
  method. If this causes the bucket to be full, `process/1` is called on the
  bucket. If this causes the bucket to overflow (eg, if the size of the bucket
  is measured in bytes), the current bucket will be processed and the data that
  was pushed will start the new bucket. If the bucket is not full, it won't do
  anything until `timeout/0` is reached, at which point it will process whatever
  is in the bucket.

  ## Example

  Assume you have thousands of processes all doing some work, and when each one
  is done you need to save the data to a third party service. This third party
  service can't handle saving all of that work one at a time, but it also can't
  handle saving one giant batch full of thousands of results. So we define a
  Procrastinator to batch the result sets into reasonable sizes.

      defmodule SaveToThirdParty do
        use Procrastinator

        @max_items 20
        @max_bytes 1024 * 256

        def process(bucket) do
          ThirdPartyApi.save_batch(bucket)
        end

        def timeout, do: 60_000

        def name, do: :save_to_third_party

        def status(bucket) do
          case length(bucket) do
            bucket_length when bucket_length == @max_items -> :full
            bucket_length when bucket_length > @max_items -> :overflow
            _ -> check_size(bucket)
          end
        end

        defp check_size(bucket) do
          case byte_size(Poison.encode!(bucket)) > @max_bytes do
            false -> :continue
            true when length(data) == 1 -> :full
            _ -> :overflow
          end
        end

      SaveToThirdParty.start_link
      SaveToThirdParty.push(1)

  In this scenario, the processes can be slow, so we want to wait a minute
  before sending a batch to give it a chance to fill up all the way. The volume
  of processes ensures that the timeout won't be reached until most of them
  have already finished and just the stragglers are running.

  The maximum number of items the api can handle at a time is 20. On top of
  this, the maximum payload size we want to send over the wire is 256kb. To
  handle this, we use the `status/1` callback. If the length of `data` (the
  bucket) equals 20, we send back `:full`. If it is over 20, we send
  `:overflow`. In this example that can't happen, but it's here for
  completeness. Otherwise we check the size in bytes of the bucket, and follow
  the same logic: if the byte size is less than 256kb, we return `:continue`. If
  it's equal to it we return `:full`, and otherwise we return `:overflow`.

  This all ensures that the third party service never receives a batch bigger
  than in can handle. It also ensures that _most of the time_ it will receive a
  batch exactly equal to what it can handle.

  ## Starting
  The Procrastinator given in the example can be started using the `start_link`
  function. It can also be added as a worker to a supervision tree, for example:

      children = [
        supervisor(YourApp.Endpoint, []),
        worker(YourApp.SaveToThirdParty, [])
      ]

      opts = [strategy: :one_for_one, name: YourApp.Supervisor]
      Supervisor.start_link(children, opts)
  """
  @doc """
  The name to register the procrastinator to.
  """
  @callback name :: atom

  @doc """
  Returns the timeout of the Procrastinator. This determines how long it will
  wait since last receiving data before it processes it. This timeout resets
  every time data is received.
  """
  @callback timeout :: integer

  @doc """
  Invoked when attempting to push data into the bucket. It will be given the
  current bucket with the new data prepended to it. Depending on the state of
  that bucket, it should return :overflow, :full, or :continue.

  ## Args
    * `bucket` - list containing all the data in the current bucket with the
      data that is trying to be inserted at the head.

  ## Returns
    * `:continue` - the Procrastinator will continue Procrastinating until
      `timeout/0` is reached.
    * `:full` - `process/1` will be called with the bucket that was passed to
      `status/1`, and the Procrastinator will be given a new, empty bucket.
    * `:overflow` - `process/1` will be called with the Procrastinator's current
      bucket, and will be given a new bucket containing the new data.
  """
  @callback status(bucket :: [any]) :: :overflow | :full | :continue

  @doc """
  Invoked when status of bucket is `:overflow` or `:full`. In the case that the
  status is `:full`, the entire bucket will be passed in, in the case of an
  `:overflow`, the entire bucket without the most recently pushed data will be
  used. Once data is given to `process/1` it is no longer in the bucket, there
  are no mechanisms to recover that data if it is lost in `process/1`.

  ## Args
    * `bucket` - a list containing data sets passed to `push/1`
  """
  @callback process(bucket :: [any]) :: any

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Procrastinator
      use GenServer

      ## Client API
      @doc """
      Starts the procrastinator.
      """
      def start_link do
        GenServer.start_link(
          __MODULE__,
          nil,
          name: name()
        )
      end

      @doc """
      Pushes data onto the Procrastinator's bucket. Depending on what is
      returned from `status/1`, this data will either end up sitting in the
      bucket or be processed.
      """
      def push(data, _type \\ :cast)
      def push(data, :cast), do: GenServer.cast(name(), {:push, data})
      def push(data, :call), do: GenServer.call(name(), {:push, data})

      @doc """
      Returns the current bucket. This is mostly just for testing; it will
      reset the timeout every time you call it so use it wisely.
      """
      def get, do: GenServer.call(name(), :get)

      ## Server Callbacks

      @doc false
      def init(_) do
        schedule_timeout()
        {:ok, []}
      end

      defp schedule_timeout() do
        Process.send_after(self(), :timeout, timeout())
      end

      @doc false
      def handle_cast({:push, data}, bucket) do
        new_state = [data | bucket]

        case status(new_state) do
          :overflow ->
            process_bucket(bucket)
            {:noreply, [data], timeout()}

          :full ->
            process_bucket(new_state)
            {:noreply, []}

          :continue ->
            {:noreply, new_state, timeout()}
        end
      end

      @doc false
      def handle_call({:push, data}, _from, bucket) do
        new_state = [data | bucket]

        case status(new_state) do
          :overflow ->
            process_bucket(bucket)
            {:reply, [data], [data], timeout()}

          :full ->
            process_bucket(new_state)
            {:reply, [], []}

          :continue ->
            {:reply, new_state, new_state, timeout()}
        end
      end

      @doc false
      def handle_call(:get, _, data), do: {:reply, data, data, timeout()}

      @doc false
      def handle_info(:timeout, bucket) do
        process_bucket(bucket)
        schedule_timeout()
        {:noreply, []}
      end

      @doc false
      defp process_bucket(bucket) do
        bucket
        |> Enum.reverse()
        |> process()
      end
    end
  end
end
