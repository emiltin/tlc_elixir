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
  def precalculate_states(%TrafficProgram{length: length, groups: groups} = program) do
    0..(length - 1)
    |> Enum.reduce(%{}, fn cycle_time, acc ->
      group_states = Enum.reduce(groups, %{}, fn group, group_acc ->
        state = find_state_for_group(program, cycle_time, group)
        Map.put(group_acc, group, state)
      end)
      Map.put(acc, cycle_time, group_states)
    end)
  end

  @doc """
  Updates the program state for the next cycle.
  """
  def update_program(program) do
    # Save the current cycle time to check for wait points
    previous_cycle_time = program.current_cycle_time

    # Increment base cycle time without wrapping
    base_cycle_time = program.base_cycle_time + 1

    # Apply wait points if we're advancing from a wait point cycle time
    program = apply_wait_points(program, previous_cycle_time)

    # Calculate new cycle time based on current offset
    cycle_time = rem(base_cycle_time + program.offset, program.length)

    # Update base and current cycle time
    program = %{program |
      base_cycle_time: rem(base_cycle_time, program.length),
      current_cycle_time: cycle_time
    }

    # Apply skip points immediately if current cycle time matches a skip point
    program = apply_skip_points(program)

    # Recalculate cycle time after applying skip points
    cycle_time = rem(program.base_cycle_time + program.offset, program.length)
    %{program | current_cycle_time: cycle_time}
  end

  @doc """
  Applies skip points if the current cycle time matches a skip point and offset is below target.
  Made public for testing purposes.
  """
  def apply_skip_points(program) do
    cycle_time = program.current_cycle_time
    skip_amount = program.skips["#{cycle_time}"]

    # Only apply skip points if offset is below target
    if skip_amount && program.offset < program.target_offset do
      # Apply the skip immediately
      %{program | offset: program.offset + skip_amount}
    else
      program
    end
  end

  @doc """
  Applies wait points when advancing from a wait point cycle time.
  """
  def apply_wait_points(program, previous_cycle_time) do
    wait_amount = program.waits["#{previous_cycle_time}"]

    # Check if we need to reduce offset (current > target)
    if wait_amount && program.offset > program.target_offset do
      # Calculate how much we need to decrease the offset
      decrease_needed = program.offset - program.target_offset
      # If the required decrease is smaller than the wait duration,
      # just decrease by the required amount, otherwise decrease by the full wait amount
      decrease_amount = min(decrease_needed, wait_amount)
      # Decrease the offset by the determined amount
      %{program | offset: program.offset - decrease_amount}
    else
      program
    end
  end

  @doc """
  Adjusts the offset towards the target offset.
  """
  def adjust_offset_towards_target(program) do
    # If target is already reached, no adjustment needed
    if program.offset == program.target_offset do
      program
    else
      program
    end
  end

  # The following functions are no longer used but kept for reference
  # They have been replaced by the new skip/wait point implementation

  # defp update_states(%TrafficProgram{length: length, base_cycle_time: base_time, offset: offset, target_offset: target_offset, skips: skips, waits: waits} = program) do
  #   # Check if we need to adjust the offset
  #   {next_base_time, new_offset} = adjust_offset(base_time, offset, target_offset, length, skips, waits)

  #   # Calculate the effective cycle time after offset adjustment
  #   effective_cycle_time = rem(next_base_time + new_offset, length)

  #   # Return the updated program state
  #   %TrafficProgram{program | base_cycle_time: next_base_time, current_cycle_time: effective_cycle_time, offset: new_offset}
  # end

  # # Private function to adjust offset
  # # Adjusts the offset towards the target offset using skip and wait points.
  # defp adjust_offset(base_time, offset, target_offset, length, skips, waits) do
  #   # Calculate next base cycle time (always advances by 1)
  #   next_base_time = rem(base_time + 1, length)

  #   # Calculate current effective cycle time (for checking skip/wait points)
  #   current_effective_time = rem(base_time + offset, length)
  #   current_effective_time_key = to_string(current_effective_time)

  #   # Return early if no adjustment needed
  #   if offset == target_offset do
  #     {next_base_time, offset}
  #   else
  #     # Calculate the difference between current and target offset
  #     offset_diff = target_offset - offset

  #     # Determine if we need to adjust offset
  #     new_offset = cond do
  #       # When target > offset: INCREASE the offset at skip points
  #       offset_diff > 0 ->
  #         # Check if current effective cycle time is a skip point
  #         case Map.get(skips, current_effective_time_key) do
  #           nil ->
  #             # No skip point, keep same offset
  #             offset
  #           skip_amount when is_integer(skip_amount) ->
  #             # Per spec: Skip points always skip the full duration
  #             # This increases the offset by the full skip amount
  #             offset + skip_amount
  #         end

  #       # When target < offset: DECREASE the offset at wait points
  #       offset_diff < 0 ->
  #         # Check if current effective cycle time is a wait point
  #         case Map.get(waits, current_effective_time_key) do
  #           nil ->
  #             # No wait point, keep same offset
  #             offset
  #           wait_amount when is_integer(wait_amount) ->
  #             # Per spec: Wait points can do partial waits

  #             # Calculate how much we need to decrease the offset
  #             decrease_needed = abs(offset_diff)

  #             # If the required decrease is smaller than the wait duration,
  #             # just decrease by the required amount, otherwise decrease
  #             # by the full wait amount
  #             decrease_amount = min(decrease_needed, wait_amount)

  #             # Decrease the offset by the determined amount
  #             offset - decrease_amount
  #         end

  #       # Offsets are equal, no adjustment needed
  #       true ->
  #         offset
  #     end

  #     # Return the new base time and adjusted offset
  #     {next_base_time, new_offset}
  #   end
  # end

  # Determine the state for a signal group at the given cycle time.
  def find_state_for_group(%TrafficProgram{states: states, groups: groups}, cycle_time, group) do
    # Find all offsets in states that are less than or equal to the current cycle_time.
    valid_offsets =
      states
      |> Map.keys()
      |> Enum.filter(fn offset -> offset <= cycle_time end)

    # No defined states before or at the current cycle time
    if valid_offsets == [] do
      # If no valid states defined before this time, look for the next defined state
      next_offsets =
        states
        |> Map.keys()
        |> Enum.filter(fn offset -> offset > cycle_time end)
        |> Enum.sort()

      # Use the next state, or default to "-" if no states defined
      state_key = case next_offsets do
        [] -> 0  # Default to first cycle time if no states defined
        [next | _] -> next  # Use the first defined state after current time
      end

      state_str = Map.get(states, state_key, "")

      group_index = Enum.find_index(groups, &(&1 == group)) || 0
      String.at(state_str, group_index) || "-"
    else
      # Choose the maximum offset (i.e. the last defined state before or at cycle_time).
      state_key = Enum.max(valid_offsets)
      state_str = Map.get(states, state_key, "")

      # Determine the index of the group in the groups list.
      group_index = Enum.find_index(groups, &(&1 == group)) || 0

      # Return the character at the group's index (or "-" if none available).
      String.at(state_str, group_index) || "-"
    end
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

  # Get the current states based on the cycle time using precalculated states
  def get_current_states(%TrafficProgram{current_cycle_time: cycle_time, precalculated_states: states}) do
    # Use the precalculated states for the current cycle time
    Map.get(states, cycle_time, %{})
  end

  # Convert current states to a string representation
  def get_current_states_string(%TrafficProgram{} = program) do
    # Get the current states for all groups
    states = get_current_states(program)

    # Convert the states map to a string in the order of the groups
    program.groups
    |> Enum.map(fn group -> Map.get(states, group, "-") end)
    |> Enum.join("")
  end
end
