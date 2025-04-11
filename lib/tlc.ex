defmodule TLC do
  @moduledoc """
  A module to simulate a fixed-time traffic light program.

  This module reads a YAML file defining the fixed-time program and handles the traffic light logic.
  """

  alias __MODULE__.TrafficProgram

  defmodule TrafficProgram do
    @moduledoc "Struct representing the fixed-time traffic program."
    defstruct length: 0,
              offset: 0,
              target_offset: 0,
              groups: [],
              # Map of cycle times to state strings.
              states: %{},
              skips: %{},
              waits: %{},
              switch: [],
              base_cycle_time: 0,  # This only advances by 1 each time step
              current_cycle_time: 0, # Effective cycle time (base + offset)
              # Pre-calculated states for each cycle time and group
              precalculated_states: %{}
  end

  @doc """
  Loads the traffic program from the specified YAML file.
  """
  def load_program(file_path) do
    {:ok, yaml} = YamlElixir.read_from_file(file_path)
    program = %TrafficProgram{
      length: yaml["length"],
      offset: yaml["offset"] || 0,
      target_offset: yaml["offset"] || 0,
      groups: yaml["groups"],
      states: yaml["states"],
      skips: yaml["skips"] || %{},
      waits: yaml["waits"] || %{},
      switch: yaml["switch"] || [],
      base_cycle_time: 0,
      current_cycle_time: 0
    }

    # Pre-calculate all states for the entire cycle
    precalculated_states = precalculate_states(program)
    %{program | precalculated_states: precalculated_states}
  end

  @doc """
  Pre-calculates states for all cycle times and groups for efficient simulation.
  Made public for testing purposes.
  """
  def precalculate_states(%TrafficProgram{length: length, states: states}) do
    0..(length - 1)
    |> Enum.reduce(%{}, fn cycle_time, acc ->
      # Store the complete state string for this cycle time
      state_string = find_state_for_cycle_time(states, cycle_time)
      Map.put(acc, cycle_time, state_string)
    end)
  end

  @doc """
  Updates the program state for the next cycle.
  """
  def update_program(program) do
    # Save the current cycle time to check for wait points
    previous_cycle_time = program.current_cycle_time

    # Increment base cycle time and wrap around when reaching the program length
    base_cycle_time = rem(program.base_cycle_time + 1, program.length)

    # Apply wait points if we're advancing from a wait point cycle time
    program = apply_wait_points(program, previous_cycle_time)

    # Calculate new cycle time based on current offset
    cycle_time = rem(base_cycle_time + program.offset, program.length)

    # Apply skip points immediately if current cycle time matches a skip point
    program = apply_skip_points(%{program | base_cycle_time: base_cycle_time, current_cycle_time: cycle_time})

    # Recalculate cycle time after applying skip points
    cycle_time = rem(program.base_cycle_time + program.offset, program.length)
    %{program | current_cycle_time: cycle_time}
  end

  @doc """
  Applies skip points if the current cycle time matches a skip point and offset is below target.
  Made public for testing purposes.
  """
  def apply_skip_points(%TrafficProgram{current_cycle_time: cycle_time, skips: skips, offset: offset, target_offset: target_offset} = program) do
    if offset < target_offset do
      case Map.get(skips, "#{cycle_time}") do
        nil -> program
        skip_amount -> %{program | offset: offset + skip_amount}
      end
    else
      program
    end
  end

  @doc """
  Applies wait points when advancing from a wait point cycle time.
  """
  def apply_wait_points(%TrafficProgram{offset: offset, target_offset: target_offset, waits: waits} = program, previous_cycle_time) do
    if offset > target_offset do
      case Map.get(waits, "#{previous_cycle_time}") do
        nil -> program
        wait_amount ->
          decrease_amount = min(offset - target_offset, wait_amount)
          %{program | offset: offset - decrease_amount}
      end
    else
      program
    end
  end

  defp find_state_for_cycle_time(states, cycle_time) do
    # Get all defined times in descending order
    times = states |> Map.keys() |> Enum.sort(:desc)

    # Find largest time <= cycle_time or use highest time if none found
    time_to_use = Enum.find(times, fn time -> time <= cycle_time end) ||  List.first(times)

    # Get the state string
    Map.get(states, time_to_use)
  end

  @doc """
  Sets the target offset for the traffic program. This will cause the program to
  gradually adjust to the new offset using skip and wait points.

  Returns the updated program.
  """
  def set_target_offset(%TrafficProgram{} = program, target_offset) do
    normalized_target = rem(target_offset, program.length)
    %TrafficProgram{program | target_offset: normalized_target}
  end

  def get_current_states_string(%TrafficProgram{current_cycle_time: cycle_time, precalculated_states: states}) do
    # Just return the precalculated state string
    Map.get(states, cycle_time, "")
  end
end
