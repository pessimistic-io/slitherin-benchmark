// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./ERC20.sol";
import "./Ownable.sol";

import "./IStake.sol";
import "./IOREO.sol";

contract Stake is IStake, Ownable {

  /// @notice oreo token
  IOREO public oreo;

  constructor(
    IOREO _oreo
  ) public {
    oreo = _oreo;
  }

  /// @notice Safe OREO transfer function, just in case if rounding error causes pool to not have enough OREOs.
  /// @param _to The address to transfer OREO to
  /// @param _amount The amount to transfer to
  function safeOreoTransfer(address _to, uint256 _amount) external override onlyOwner {
    uint256 oreoBal = oreo.balanceOf(address(this));
    if (_amount > oreoBal) {
      oreo.transfer(_to, oreoBal);
    } else {
      oreo.transfer(_to, _amount);
    }
  }
}
