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

import "./ERC20_IERC20.sol";
import "./UniversalLendStrategy.sol";
import "./IAave3Pool.sol";
import "./IAave3Token.sol";
import "./IRewardsController.sol";
import "./console.sol";
/// @title Contract for AAVEv3 strategy implementation, a bit simplified comparing with v1
/// @author dvpublic
abstract contract Aave3StrategyBaseV2 is UniversalLendStrategy {
  using SafeERC20 for IERC20;

  /// ******************************************************
  ///                Constants and variables
  /// ******************************************************

  /// @notice Strategy type for statistical purposes
  IRewardsController internal constant _AAVE_INCENTIVES = IRewardsController(0x929EC64c34a17401F460460D4B9390518E5B473e);
  IAave3Pool constant public AAVE_V3_POOL_ARB = IAave3Pool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
  event Withdrawn(address _underlying, uint256 _liquidity);


  /// ******************************************************
  ///                    Initialization
  /// ******************************************************

  /// @notice Initialize contract after setup it as proxy implementation
  function initializeStrategy(
    address _underlying,
    address[] memory _rewardTokens,
    address[] memory _addresses
  ) public initializer {
    UniversalLendStrategy.initializeLendStrategy(
      _underlying,
      _rewardTokens,
      _addresses
    );

    require(_aToken().UNDERLYING_ASSET_ADDRESS() == _underlying, "wrong underlying");
  }

  function withdraw(address to, uint256 amount) external onlyManager returns (uint256) {
    uint256 poolBalance = _rewardPoolBalance();
    bool withdrewAll = _withdrawFromPoolWithoutChangeLocalBalance(amount, poolBalance);

    if (withdrewAll) {
      uint256 tokBal = IERC20(underlying).balanceOf(address(this));
      IERC20(underlying).safeTransfer(to, tokBal);
      emit Withdrawn(underlying, tokBal);
    } else {
      IERC20(underlying).safeTransfer(to, amount);
      emit Withdrawn(underlying, amount);
    }
  }

  function withdrawToVault(uint256 amount) external onlyManager returns (uint256) {
    uint256 poolBalance = _rewardPoolBalance();
    bool withdrewAll = _withdrawFromPoolWithoutChangeLocalBalance(amount, poolBalance);

    if (withdrewAll) {
      uint256 tokBal = IERC20(underlying).balanceOf(address(this));
      IERC20(underlying).safeTransfer(vault, tokBal);
      emit Withdrawn(underlying, tokBal);
    } else {
      IERC20(underlying).safeTransfer(vault, amount);
      emit Withdrawn(underlying, amount);
    }

  }

  function withdrawAll(address to) external onlyManager returns (uint256) {
    _withdrawAllFromPool();
    uint256 tokBal = IERC20(underlying).balanceOf(address(this));
    IERC20(underlying).safeTransfer(to, tokBal);
  }

  /// ******************************************************
  ///                    Views
  /// ******************************************************

  function _rewardPoolBalance() internal view override returns (uint256) {
    uint normalizedIncome = AAVE_V3_POOL_ARB.getReserveNormalizedIncome(underlying);
    return (0.5e27 + _aToken().scaledBalanceOf(address(this)) * normalizedIncome) / 1e27;
  }

  function investedUnderlyingBalance() external view returns (uint256) {
    return _rewardPoolBalance();
  }

  function readyToClaim() external view returns (uint256[] memory) {
    return new uint[](rewardTokens.length);
  }

  function poolTotalAmount() external view returns (uint256) {
    return _aToken().totalSupply();
  }

  function _simpleDepositToPool(uint amount) internal override {
    address u = underlying;
    _approveIfNeeds(u, amount, address(AAVE_V3_POOL_ARB));
    AAVE_V3_POOL_ARB.supply(u, amount, address(this), 0);
    localBalance += amount;
  }

  function investAllUnderlying() external {
    uint uBalance = IERC20(underlying).balanceOf(address(this));
    if (uBalance > 0) {
      depositToPool(uBalance);
    }
  }

  function _withdrawFromPoolWithoutChangeLocalBalance(uint amount, uint poolBalance) internal override returns (bool withdrewAll) {
    if (amount < poolBalance) {
      AAVE_V3_POOL_ARB.withdraw(underlying, amount, address(this));
      return false;
    } else {
      AAVE_V3_POOL_ARB.withdraw(
        underlying,
        type(uint256).max, // withdraw all, see https://docs.aave.com/developers/core-contracts/pool#withdraw
        address(this)
      );
      return true;
    }
  }

  function _withdrawAllFromPool() internal override {
    AAVE_V3_POOL_ARB.withdraw(
      underlying,
      type(uint256).max, // withdraw all, see https://docs.aave.com/developers/core-contracts/pool#withdraw
      address(this)
    );
    localBalance = 0;
  }

  /// @dev Claim all possible rewards to the current contract
  function _claimReward() internal override {
    address[] memory _assets = new address[](1);
    _assets[0] = address(_aToken());
    _AAVE_INCENTIVES.claimAllRewardsToSelf(_assets);
  }

  /// ******************************************************
  ///                       Utils
  /// ******************************************************
  function _aToken() internal view returns (IAave3Token) {
    return IAave3Token(AAVE_V3_POOL_ARB.getReserveData(underlying).aTokenAddress);
  }
}
