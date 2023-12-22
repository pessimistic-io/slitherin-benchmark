// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {Logic} from "./Logic.sol";
import {Constants} from "./Constants.sol";

abstract contract Execution is SharedLiquidity, Ownable {
    using SafeERC20 for IERC20;

    struct ExecutionConstructorParams {
        address logic;
        address incentiveVault;
        address treasury;
        uint256 fixedFee;
        uint256 performanceFee;
    }

    address public immutable LOGIC;
    address public immutable INCENTIVE_VAULT;
    address public immutable TREASURY;
    uint256 public immutable PERFORMANCE_FEE;
    uint256 public immutable FIXED_FEE;
    bool public killed;

    event Entered(uint256 liquidityDelta);
    event EmergencyExited();

    error EnterFailed();
    error ExitFailed();
    error Killed();
    error NotKilled();

    modifier alive() {
        if (killed) revert Killed();
        _;
    }

    constructor(ExecutionConstructorParams memory params) Ownable(msg.sender) {
        LOGIC = params.logic;
        INCENTIVE_VAULT = params.incentiveVault;
        TREASURY = params.treasury;
        PERFORMANCE_FEE = params.performanceFee;
        FIXED_FEE = params.fixedFee;
    }

    function claimRewards() external {
        _logic(abi.encodeCall(Logic.claimRewards, (INCENTIVE_VAULT)));
    }

    function emergencyExit() external alive onlyOwner {
        _logic(abi.encodeCall(Logic.emergencyExit, ()));

        killed = true;
        emit EmergencyExited();
    }

    function totalLiquidity() public view override returns (uint256) {
        return Logic(LOGIC).accountLiquidity(address(this));
    }

    function _enter(
        uint256 minLiquidityDelta
    ) internal alive returns (uint256 newShares) {
        uint256 liquidityBefore = totalLiquidity();
        _logic(abi.encodeCall(Logic.enter, ()));
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

    function _exit(
        uint256 shares,
        address[] memory tokens,
        uint256[] memory minDeltas
    ) internal alive {
        uint256 n = tokens.length;
        for (uint256 i = 0; i < n; i++) {
            minDeltas[i] += IERC20(tokens[i]).balanceOf(address(this));
        }

        uint256 liquidity = _toLiquidity(shares);
        _logic(abi.encodeCall(Logic.exit, (liquidity)));

        for (uint256 i = 0; i < n; i++) {
            if (IERC20(tokens[i]).balanceOf(address(this)) < minDeltas[i]) {
                revert ExitFailed();
            }
        }
    }

    function _withdrawLiquidity(address recipient, uint256 amount) internal {
        _logic(abi.encodeCall(Logic.withdrawLiquidity, (recipient, amount)));
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

    function _logic(bytes memory call) internal returns (bytes memory data) {
        bool success;
        (success, data) = LOGIC.delegatecall(call);

        if (!success) {
            assembly {
                revert(add(data, 32), mload(data))
            }
        }
    }

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

