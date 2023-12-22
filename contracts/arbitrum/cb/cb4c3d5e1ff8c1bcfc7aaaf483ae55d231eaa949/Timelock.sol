/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./IERC20.sol";

/**
 * @title Timelock
 * @author Consensus party
 * @notice A contract that restricts access to certain methods based on roles and time delays.
 */
contract Timelock is AccessControl {
  enum Status {
    Pending,
    Executed,
    Cancelled
  }

  struct Description {
    uint256 id;
    uint256 createdAt;
    uint256 doneAt;
    Status status;
  }

  struct CallResult {
    bool success;
    bytes returnData;
  }

  /// @dev Emitted when a call is scheduled.
  /// @param id The ID of the scheduled call.
  /// @param callHash The hash of the scheduled call.
  /// @param targets The addresses of the contracts to be called.
  /// @param values The values to be passed to the contracts.
  /// @param calldatas The data to be passed to the contracts.
  event CallScheduled(
    uint256 indexed id, bytes32 indexed callHash, address[] targets, uint256[] values, bytes[] calldatas
  );

  /// @dev Emitted when a scheduled call is executed.
  /// @param id The ID of the executed call.
  /// @param callHash The hash of the executed call.
  /// @param results The results of the executed call.
  event CallExecuted(uint256 indexed id, bytes32 indexed callHash, CallResult[] results);

  /// @dev Emitted when a scheduled call is canceled.
  /// @param id The ID of the canceled call.
  event CallCanceled(uint256 indexed id);

  /// @dev Emitted when the delay time between scheduling and execution is changed.
  /// @param newDuration The new duration of the delay time.
  event DelayTimeChanged(uint256 newDuration);

  /// @dev The keccak256 hash of scheduler's role.
  bytes32 public constant SCHEDULER_ROLE = keccak256("SCHEDULER_ROLE");
  /// @dev The keccak256 hash of executor's role.
  bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  /// @dev keccak256("Schedule(address[] targets,uint256[] values,bytes[] calldatas)").
  bytes32 private constant _SCHEDULE_TYPE_HASH = 0x19e5e0ffbb5f3f5b0e340f9ba338e6bd20059e9d891034da857e3e1322e73832;

  /// @dev The minimum delay (in seconds) between scheduling and executing a schedule.
  uint256 public minDelay;
  /// @dev An array of all schedule hashes that have been scheduled.
  bytes32[] public callHashes;
  /// @dev A mapping of schedule hashes to their corresponding descriptions and schedules.
  mapping(bytes32 => Description) public schedules;

  constructor(address scheduler, address executor, uint256 _minDelay) {
    _grantRole(SCHEDULER_ROLE, scheduler);
    _grantRole(EXECUTOR_ROLE, executor);
    _grantRole(DEFAULT_ADMIN_ROLE, address(this));

    minDelay = _minDelay;
    emit DelayTimeChanged(_minDelay);
  }

  /**
   * @dev Sets the minimum delay (in seconds) between scheduling and executing a schedule.
   *
   * Emits a {DelayTimeChanged} event.
   *
   * Requirements:
   *
   * - only accepts self-call.
   *
   * @param _minDelay the minimum delay to update.
   *
   */
  function setMinDelay(uint256 _minDelay) external {
    require(msg.sender == address(this), "TimelockController: only self-call");
    minDelay = _minDelay;
    emit DelayTimeChanged(_minDelay);
  }

  /**
   * @dev Schedules to make calls in the future.
   *
   * Emits a {CallScheduled} event .
   *
   * Requirements:
   *
   * - the method caller must have `SCHEDULER_ROLE`.
   * - the input array is valid.
   *
   * @param targets The addresses of the contracts to be called.
   * @param values The values to be passed to the contracts.
   * @param calldatas The data to be passed to the contracts.
   *
   */
  function schedule(address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    external
    onlyRole(SCHEDULER_ROLE)
  {
    require(
      targets.length > 0 && targets.length == values.length && targets.length == calldatas.length,
      "Timelock: array length"
    );
    uint256 id = callHashes.length;
    bytes32 callHash = getCallHash(targets, values, calldatas);

    schedules[callHash] = Description(id, block.timestamp, 0, Status.Pending);
    callHashes.push(callHash);

    emit CallScheduled(id, callHash, targets, values, calldatas);
  }

  /**
   * @dev Executes the scheduled call.
   *
   * Emits a {CallExecuted} event.
   *
   * Requirements:
   *
   * - the method caller must have the `EXECUTOR_ROLE`.
   * - the scheduled call ID must exist.
   * - the provided call parameters match the scheduled call parameters.
   * - the scheduled call has not been executed or cancelled.
   * - the scheduled call is not currently locked.
   *
   * @param id The ID of the scheduled call.
   * @param targets The addresses of the contracts to be called.
   * @param values The values to be passed to the contracts.
   * @param calldatas The data to be passed to the contracts.
   *
   */
  function exec(uint256 id, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    external
    onlyRole(EXECUTOR_ROLE)
  {
    bytes32 computedHash = getCallHash(targets, values, calldatas);
    require(id < callHashes.length, "Timelock: invalid id");
    bytes32 callHash = callHashes[id];
    require(callHash == computedHash, "Timelock: invalid hash");
    Description storage s = schedules[callHash];
    require(s.status == Status.Pending, "Timelock: must pending");

    require(block.timestamp - s.createdAt > minDelay, "Timelock: locking");
    s.doneAt = block.timestamp;
    s.status = Status.Executed;

    CallResult[] memory results = new CallResult[](targets.length);
    for (uint256 i; i < targets.length; i++) {
      (results[i].success, results[i].returnData) = targets[i].call{value: values[i]}(calldatas[i]);
    }

    emit CallExecuted(id, callHash, results);
  }

  /**
   * @dev Cancels a scheduled call.
   *
   * Emits a {CallCanceled} event.
   *
   * Requirements:
   *
   * - the method caller must have the `SCHEDULER_ROLE`.
   * - the scheduled call ID must exist.
   * - the provided call parameters match the scheduled call parameters.
   * - the scheduled call has not been executed or cancelled.
   *
   * @param id The ID of the scheduled call.
   * @param targets The addresses of the contracts to be called.
   * @param values The values to be passed to the contracts.
   * @param calldatas The data to be passed to the contracts.
   *
   */
  function cancel(uint256 id, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    external
    onlyRole(SCHEDULER_ROLE)
  {
    bytes32 computedHash = getCallHash(targets, values, calldatas);
    require(id < callHashes.length, "Timelock: invalid id");
    bytes32 callHash = callHashes[id];
    require(callHash == computedHash, "Timelock: invalid hash");
    Description storage s = schedules[callHash];
    require(s.status == Status.Pending, "Timelock: must pending");
    s.doneAt = block.timestamp;
    s.status = Status.Cancelled;
    emit CallCanceled(id);
  }

  /**
   * @dev Returns the call hash for a scheduled call.
   *
   * The call hash is generated by hashing together the addresses of the contracts to be called,
   * the values to be passed to the contracts, and the data to be passed to the contracts.
   *
   * @param targets The addresses of the contracts to be called.
   * @param values The values to be passed to the contracts.
   * @param calldatas The data to be passed to the contracts.
   *
   * @return The call hash for the specified call.
   */
  function getCallHash(address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    public
    pure
    returns (bytes32)
  {
    bytes32 targetsHash;
    bytes32 valuesHash;
    bytes32 calldatasHash;

    bytes32[] memory calldataHashList = new bytes32[](calldatas.length);
    for (uint256 _i; _i < calldataHashList.length; _i++) {
      calldataHashList[_i] = keccak256(calldatas[_i]);
    }

    assembly {
      targetsHash := keccak256(add(targets, 0x20), mul(mload(targets), 0x20))
      valuesHash := keccak256(add(values, 0x20), mul(mload(values), 0x20))
      calldatasHash := keccak256(add(calldataHashList, 0x20), mul(mload(calldataHashList), 0x20))
    }

    return keccak256(abi.encode(_SCHEDULE_TYPE_HASH, targetsHash, valuesHash, calldatasHash));
  }
}

/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

