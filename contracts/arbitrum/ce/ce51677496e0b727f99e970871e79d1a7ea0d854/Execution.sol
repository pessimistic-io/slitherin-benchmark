// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {Constants} from "./Constants.sol";

abstract contract Execution is SharedLiquidity {
    using SafeERC20 for IERC20;

    struct ExecutionConstructorParams {
        address incentiveVault;
        address treasury;
        uint256 fixedFee;
        uint256 performanceFee;
    }

    address public immutable INCENTIVE_VAULT;
    address public immutable TREASURY;
    uint256 public immutable PERFORMANCE_FEE;
    uint256 public immutable FIXED_FEE;
    bool public killed;

    event Entered(uint256 liquidityDelta);
    event EmergencyExited();

    error EnterFailed();
    error ExitFailed();
    error NotImplemented();
    error Killed();
    error NotKilled();

    modifier alive() {
        if (killed) revert Killed();
        _;
    }

    constructor(ExecutionConstructorParams memory params) {
        INCENTIVE_VAULT = params.incentiveVault;
        TREASURY = params.treasury;
        PERFORMANCE_FEE = params.performanceFee;
        FIXED_FEE = params.fixedFee;
    }

    function claimRewards() external {
        _claimRewardsLogic();
    }

    function emergencyExit() external alive {
        // TODO: add role
        _emergencyExitLogic();

        killed = true;
        emit EmergencyExited();
    }

    function _enter(
        uint256 minLiquidityDelta
    ) internal alive returns (uint256 newShares) {
        uint256 liquidityBefore = totalLiquidity();
        _enterLogic();
        uint256 liquidityAfter = totalLiquidity();
        if (
            liquidityBefore >= liquidityAfter ||
            (liquidityAfter - liquidityBefore) < minLiquidityDelta
        ) {
            revert EnterFailed();
        }
        emit Entered(liquidityAfter - liquidityBefore);

        return _sharesFromLiquidityDelta(liquidityBefore, liquidityAfter);
    }

    function _exit(uint256 shares) internal alive {
        // TODO: check min token out
        uint256 liquidity = _toLiquidity(shares);
        _exitLogic(liquidity);
    }

    function _withdrawAfterEmergencyExit(
        address recipient,
        uint256 shares,
        uint256 totalShares,
        address[] memory tokens
    ) internal {
        if (!killed) revert NotKilled();

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = IERC20(tokens[i]).balanceOf(address(this));
            if (tokenBalance > 0) {
                IERC20(tokens[i]).safeTransfer(
                    recipient,
                    (tokenBalance * shares) / totalShares
                );
            }
        }
    }

    function _enterLogic() internal virtual;

    function _exitLogic(uint256 liquidity) internal virtual;

    function _claimRewardsLogic() internal virtual;

    function _emergencyExitLogic() internal virtual {
        revert NotImplemented();
    }

    function _withdrawLiquidityLogic(
        address to,
        uint256 liquidity
    ) internal virtual;

    function _calculateFixedFeeAmount(
        uint256 shares
    ) internal view returns (uint256 performanceFeeAmount) {
        return (shares * FIXED_FEE) / Constants.BPS;
    }

    function _calculatePerformanceFeeAmount(
        uint256 shares
    ) internal view returns (uint256 performanceFeeAmount) {
        return (shares * PERFORMANCE_FEE) / Constants.BPS;
    }
}

