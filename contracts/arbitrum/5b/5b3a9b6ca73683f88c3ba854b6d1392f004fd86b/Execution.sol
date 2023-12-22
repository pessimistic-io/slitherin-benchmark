// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {SharedLiquidity} from "./SharedLiquidity.sol";

abstract contract Execution is SharedLiquidity {
    struct ExecutionConstructorParams {
        address incentiveVault;
        address treasury;
        uint256 fixedFee;
        uint256 performanceFee;
    }

    error EnterFailed();
    error ExitFailed();

    address public immutable incentiveVault;
    address public immutable treasury;
    uint256 public immutable performanceFee;
    uint256 public immutable fixedFee;

    constructor(ExecutionConstructorParams memory params) {
        incentiveVault = params.incentiveVault;
        treasury = params.treasury;
        fixedFee = params.fixedFee;
        performanceFee = params.performanceFee;
    }

    function claimRewards() external {
        _claimRewardsLogic();
    }

    function _enter(uint256 minLiquidityDelta) internal returns (uint256) {
        uint256 liquidityBefore = totalLiquidity();
        _enterLogic();
        uint256 liquidityAfter = totalLiquidity();
        if (
            liquidityBefore >= liquidityAfter ||
            (liquidityAfter - liquidityBefore) < minLiquidityDelta
        ) {
            revert EnterFailed();
        }
        return _sharesFromLiquidityDelta(liquidityBefore, liquidityAfter);
    }

    function _exit(uint256 shares) internal {
        uint256 liquidity = _toLiquidity(shares);
        _withdrawShares(shares);
        _exitLogic(liquidity);
    }

    function _calculatePerformanceFeeAmount(
        uint256 shares
    ) internal view returns (uint256) {
        return (shares * performanceFee) / 1e4;
    }

    function _claimRewardsLogic() internal virtual;

    function _enterLogic() internal virtual;

    function _exitLogic(uint256 liquidity) internal virtual;

    function _withdrawLiquidityLogic(
        address to,
        uint256 liquidity
    ) internal virtual;
}

