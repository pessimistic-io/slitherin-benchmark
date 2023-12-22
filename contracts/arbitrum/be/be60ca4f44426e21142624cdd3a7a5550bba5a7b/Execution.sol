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

    function _enter(
        bool mintShares
    ) internal returns (uint256) {
        uint256 liquidityBefore = totalLiquidity();
        _enterLogic();
        uint256 liquidityAfter = totalLiquidity();
        if (liquidityBefore >= liquidityAfter) {
            revert EnterFailed();
        }

        uint256 shares = _sharesFromLiquidityDelta(
            liquidityBefore,
            liquidityAfter
        );
        if (mintShares) {
            _issueShares(shares);
        }
        return shares;
    }

    function _exit(uint256 shares) internal {
        uint256 liquidity = _toLiquidity(shares);
        _withdrawShares(shares);
        _exitLogic(liquidity);
    }

    function _reinvest() internal returns (uint256 shares) {
        shares = _enter(false);
        uint256 fee = (shares * performanceFee) / 1e4;
        _accrueFee(fee, treasury);
    }

    function _accrueFee(uint256 feeAmount, address recipient) internal virtual;

    function _claimRewardsLogic() internal virtual;

    function _enterLogic() internal virtual;

    function _exitLogic(uint256 liquidity) internal virtual;
}

