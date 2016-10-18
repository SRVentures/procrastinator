defmodule ProcrastinatorTest do
  use ExUnit.Case
  # doctest Procrastinator

  test "Does not process data when not full" do
    defmodule Continue do
      use Procrastinator

      def timeout, do: 1_000
      def name, do: :full
      def status(_), do: :continue
      def process(_), do: :noop
    end

    Continue.start_link
    Continue.push(1)
    assert Continue.get == [1]
  end

  test "Processes the data when it is full" do
    defmodule Full do
      use Procrastinator

      def timeout, do: 1_000
      def name, do: :full
      def status(_), do: :full
      def process(data), do: assert data == [1]
    end

    Full.start_link
    Full.push(1)
    assert Full.get == []
  end

  test "Processes the previous data when it overflows" do
    defmodule Overflow do
      use Procrastinator

      def timeout, do: 1_000
      def name, do: :overflow
      def status(data) when length(data) < 2.5, do: :continue
      def status(_), do: :overflow
      def process(data), do: assert data == [1, 2]
    end

    Overflow.start_link
    Overflow.push(1)
    Overflow.push(2)
    Overflow.push(3)
    assert Overflow.get == [3]
  end

  test "Processes the data when it times out" do
    defmodule Timeout do
      use Procrastinator

      def timeout, do: 100
      def name, do: :timeout
      def status(_), do: :continue
      def process(data), do: assert data == [1]
    end

    Timeout.start_link
    Timeout.push(1)
    :timer.sleep(200)
    assert Timeout.get == []
  end

  test "Resets timeout on every insert" do
    defmodule Timeout2 do
      use Procrastinator

      def timeout, do: 100
      def name, do: :timeout2
      def status(_), do: :continue
      def process(data), do: assert data == [1, 2, 3, 4, 5]
    end

    Timeout2.start_link
    Timeout2.push(1)
    :timer.sleep(50)
    Timeout2.push(2)
    :timer.sleep(50)
    Timeout2.push(3)
    :timer.sleep(50)
    Timeout2.push(4)
    :timer.sleep(50)
    assert Timeout2.get == [4, 3, 2, 1]
    Timeout2.push(5)
    :timer.sleep(200)
    assert Timeout2.get == []
  end
end
