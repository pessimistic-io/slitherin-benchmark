// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IPool} from "./IPool.sol";
import {IERC20} from "./IERC20.sol";

contract AavePoolAdapter {
  /// @notice AavePool contract for deposit
  IPool public aavePool;

  constructor(address _aavePool) {
    aavePool = IPool(_aavePool);
  }

  /// @notice Supply assets to the Aave pool
  /// @param _asset Address of the token to deposit
  /// @param _amount Amount of tokens to deposit
  /// @param _onBehalfOf Address of the user
  /// @param _referralCode Referral code for Aave
  function _supply(address _asset, uint256 _amount, address _onBehalfOf, uint16 _referralCode) internal returns (bool) {
    require(_amount > 0, "Zero Amount");

    // Increasing the allowance
    if (IERC20(_asset).allowance(address(this), address(aavePool)) < _amount) {
      IERC20(_asset).approve(address(aavePool), type(uint256).max);
    }

    aavePool.supply(_asset, _amount, _onBehalfOf, _referralCode);

    return true;
  }
}

