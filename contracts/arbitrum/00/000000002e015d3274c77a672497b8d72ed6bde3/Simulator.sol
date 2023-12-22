// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import { ISimulator } from "./ISimulator.sol";

/**
 * @title Simulation Adapter
 * @author Sam Bugs
 * @notice This contracts allows to simulate calls to several contracts, all in one RPC request. It works similarly to a
 *         multicall, but the state is not modified in each subcall.
 * @dev Please note that we are using `CALL` to execute all subcalls, so the `msg.sender` WILL change
 */
contract Simulator is ISimulator {
  /// @notice An error that contains a simulation's result
  error SimulatedCall(SimulationResult result);

  /// @inheritdoc ISimulator
  function simulate(Call[] calldata _calls) external payable returns (SimulationResult[] memory _results) {
    _results = new SimulationResult[](_calls.length);
    for (uint256 i = 0; i < _calls.length; i++) {
      _results[i] = _simulate(_calls[i]);
    }
    return _results;
  }

  /**
   * @notice Executes a simulation and returns the result
   * @param _call The call to simulate
   * @return _simulationResult The simulation's result
   */
  function _simulate(Call calldata _call) internal returns (SimulationResult memory _simulationResult) {
    (bool _success, bytes memory _result) =
    // solhint-disable-next-line avoid-low-level-calls
     address(this).delegatecall(abi.encodeWithSelector(this.simulateAndRevert.selector, _call));
    require(!_success, "WTF? Should have failed!");
    // Move pointer to ignore selector
    // solhint-disable-next-line no-inline-assembly
    assembly {
      _result := add(_result, 0x04)
    }
    (_simulationResult) = abi.decode(_result, (SimulationResult));
  }

  /**
   * @notice Executes a call agains this contract and reverts with the result
   * @dev This is meant to be used internally, do not call!
   * @param _call The call to simulate
   */
  function simulateAndRevert(Call calldata _call) external payable {
    uint256 _gasAtStart = gasleft();
    // solhint-disable-next-line avoid-low-level-calls
    (bool _success, bytes memory _result) = _call.target.call{ value: _call.value }(_call.callData);
    uint256 _gasSpent = _gasAtStart - gasleft();
    revert SimulatedCall(SimulationResult({ success: _success, result: _result, gasSpent: _gasSpent }));
  }
}

