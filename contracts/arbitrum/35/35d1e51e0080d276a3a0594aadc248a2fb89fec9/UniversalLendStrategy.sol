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
pragma solidity ^0.8.0;

import { StratManagerUpgradeable } from "./StratManagerUpgradeable.sol";
import "./DynamicFeeManager.sol";
import "./ISwapRouter.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./ERC20_IERC20.sol";

/// @title Universal base strategy for simple lending
/// @author belbix
abstract contract UniversalLendStrategy is StratManagerUpgradeable, DynamicFeeManager {
  using SafeERC20 for IERC20;

  /// ******************************************************
  ///                Constants and variables
  /// ******************************************************
  uint private constant _DUST = 10_000;

  uint internal localBalance;
  uint public lastHw;
  uint public rewardRatio;
  address public constant univ3Router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
  address public underlying;
  address[] public rewardTokens;
  /// ******************************************************
  ///                    Initialization
  /// ******************************************************

  /// @notice Initialize contract after setup it as proxy implementation
  function initializeLendStrategy(
    address _underlying,
    address[] memory _rewardTokens,
    address[] memory _addresses
  ) public initializer {
    __Ownable_init_unchained();
    __Pausable_init_unchained();
    __DynamicFeeManager_init();
    __StratManager_init_unchained(_addresses[0], _addresses[1], _addresses[2], _addresses[3], _addresses[4]);

    for (uint i = 0; i < _rewardTokens.length; i++) {
      rewardTokens.push(_rewardTokens[i]);
    }
    underlying = _underlying;
    rewardRatio = 50;
  }

  /// @dev Set new reward tokens
  function setRewardTokens(address[] memory rts, uint24[] memory _poolFees) external onlyManager {
    delete rewardTokens;
    for (uint i = 0; i < rts.length; i++) {
      rewardTokens.push(rts[i]);
    }
  }

  function setRewardRatioToFirstFeeRecepient(uint _rewardRatio) external onlyManager {
    rewardRatio = _rewardRatio;
  }

  function earn() external onlyManager {
    _doHardWork();
  }

  /// @dev Deposit to pool and increase local balance
  function _simpleDepositToPool(uint amount) internal virtual;

  /// @dev Refresh rates and return actual deposited balance in underlying tokens
  function _rewardPoolBalance() internal virtual returns (uint);

  /// @dev Perform only withdraw action, without changing local balance
  function _withdrawFromPoolWithoutChangeLocalBalance(uint amount, uint poolBalance) internal virtual returns (bool withdrewAll);

  /// @dev Withdraw all and set localBalance to zero
  function _withdrawAllFromPool() internal virtual;

  /// @dev Claim all possible rewards to the current contract
  function _claimReward() internal virtual;

 
  function depositToPool(uint256 amount) internal {
    amount = IERC20(underlying).balanceOf(address(this)) < amount ? IERC20(underlying).balanceOf(address(this)) : amount;
    if (amount > 0) {
      _simpleDepositToPool(amount);
    }
  }

  /// @dev Withdraw underlying from the pool
  function withdrawAndClaimFromPool(uint256 amount_) internal {
    uint poolBalance = _doHardWork();

    bool withdrewAll = _withdrawFromPoolWithoutChangeLocalBalance(amount_, poolBalance);

    if (withdrewAll) {
      localBalance = 0;
    } else {
      localBalance > amount_ ? localBalance -= amount_ : localBalance = 0;
    }
  }

  /// @dev Exit from external project without caring about rewards, for emergency cases only
  function emergencyWithdrawFromPool() internal {
    _withdrawAllFromPool();
  }

  function liquidateReward() internal {
    // noop
  }

  function _claimAndTransferReward() internal {
    _claimReward();
    address[] memory rts = rewardTokens;
    for (uint i; i < rts.length; ++i) {
      address rt = rts[i];
      uint amount = IERC20(rt).balanceOf(address(this));
      uint rewardAmount1 = amount * rewardRatio / 100;
      uint rewardAmount2 = amount - rewardAmount1;
      if (rewardAmount1 > _DUST && rewardAmount2 > _DUST) {
        IERC20(rt).transfer(feeRecipient1, rewardAmount1);
        IERC20(rt).transfer(feeRecipient2, rewardAmount2);
      }
    }
  }

  function _doHardWork() internal returns (uint poolBalance) {
    poolBalance = _rewardPoolBalance();

    uint _lastHw = lastHw;
    if (_lastHw != 0 && (block.timestamp - _lastHw) < 12 hours) {
      return poolBalance;
    }
    lastHw = block.timestamp;

    _claimAndTransferReward();
  }

  function _approveIfNeeds(address token, uint amount, address spender) internal {
    if (IERC20(token).allowance(address(this), spender) < amount) {
      IERC20(token).safeApprove(spender, 0);
      IERC20(token).safeApprove(spender, type(uint).max);
    }
  }

  // function swap(address _inputToken, address _outputToken, uint256 _amount) internal {
  //     ISwapRouter(univ3Router).exactInputSingle(
  //       ISwapRouter.ExactInputSingleParams({
  //         tokenIn: _inputToken,
  //         tokenOut: _outputToken,
  //         fee: swapPoolFees[_inputToken],
  //         recipient: address(this),
  //         amountIn: _amount,
  //         amountOutMinimum: 0,
  //         sqrtPriceLimitX96: 0
  //       })
  //     );
  // }
}
