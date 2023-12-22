// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {GPv2SafeERC20} from "./GPv2SafeERC20.sol";

contract FeeBase {
  using GPv2SafeERC20 for IERC20;

  uint256 public pct100;
  uint256 public rewardFeeRate;
  address public rewardFeeDestination;

  event RewardFeeChanged(uint256 _old, uint256 _new);
  event RewardAddressChanged(address _old, address _new);
  event RewardFeeCharged(uint256 initialAmount, uint256 feeAmount, address feeDestination);

  function initializeFeeBase(uint256 _rewardFeeRate, address _rewardFeeDestination) internal {
    pct100 = 100000000000;
    rewardFeeRate = _rewardFeeRate;
    rewardFeeDestination = _rewardFeeDestination;
  }

  function _setRewardFeeAddress(address _new) internal {
    emit RewardAddressChanged(rewardFeeDestination, _new);
    rewardFeeDestination = _new;
  }

  function _setRewardFeeRate(uint256 _new) internal {
    require(_new >= 0, 'fee is not >= 0%');
    require(_new < pct100, 'fee is not < 100%');

    emit RewardFeeChanged(rewardFeeRate, _new);
    rewardFeeRate = _new;
  }

  function _chargeFee(IERC20 token, uint256 earnings) internal {
    if (earnings == 0) return;

    // pay out fees to governance
    uint256 feeToCharge = (earnings * rewardFeeRate) / pct100;
    if (feeToCharge > 0 && rewardFeeDestination != address(0)) {
      token.safeTransfer(rewardFeeDestination, feeToCharge);
      emit RewardFeeCharged(earnings, feeToCharge, rewardFeeDestination);
    }
  }
}

