// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./IControllable.sol";
import "./IController.sol";

/// @title Implement basic functionality for any contract that require strict control
///        V2 is optimised version for less gas consumption
/// @dev Can be used with upgradeable pattern.
///      Require call initializeControllable() in any case.
/// @author belbix
abstract contract ControllableV2 is Initializable, IControllable {

  address internal _controller;
  uint256 internal _createdTimestamp;
  uint256 internal _createdBlock;

  event ContractInitialized(address controller, uint ts, uint block);

  /// @notice Initialize contract after setup it as proxy implementation
  ///         Save block.timestamp in the "created" variable
  /// @dev Use it only once after first logic setup
  /// @param __controller Controller address
  function initializeControllable(address __controller) public initializer {
    _controller = __controller;
    _createdTimestamp = block.timestamp;
    _createdBlock = block.number;
    emit ContractInitialized(__controller, block.timestamp, block.number);
  }

  /// @dev Return true if given address is controller
  function isController(address _value) external override view returns (bool) {
    return _isController(_value);
  }

  function _isController(address _value) internal view returns (bool) {
    return _value == _controller;
  }

  /// @notice Return true if given address is setup as governance in Controller
  function isGovernance(address _value) external override view returns (bool) {
    return _isGovernance(_value);
  }

  function _isGovernance(address _value) internal view returns (bool) {
    return IController(_controller).governance() == _value;
  }

  // ************* SETTERS/GETTERS *******************

  /// @notice Return creation timestamp
  /// @return ts Creation timestamp
  function created() external view override returns (uint256 ts) {
    ts = _createdTimestamp;
  }

  /// @notice Return creation block number
  /// @return ts Creation block number
  function createdBlock() external view returns (uint256 ts) {
    ts = _createdBlock;
  }

  /// @notice Return controller address
  function controller() external view returns (address) {
    return _controller;
  }
}

