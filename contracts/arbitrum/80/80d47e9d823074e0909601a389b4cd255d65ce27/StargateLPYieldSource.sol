// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";

import {IYieldSource} from "./IYieldSource.sol";
import {ILPStaking} from "./ILPStaking.sol";

/// @title Yield Source contract for stargate LP
/// @author Y2K Finance
/// @dev This is for reward management by LP staking, not yield bearing asset
///      Owner of this contract is always SIV
contract StargateLPYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    /// @notice LP token
    IERC20 public immutable override sourceToken;

    /// @notice Reward token = STG token
    IERC20 public immutable override yieldToken;

    /// @notice LP staking contract
    ILPStaking public immutable staking;

    /// @notice Uniswap router
    IUniswapV2Router02 public router;

    /// @notice Pool Id
    uint256 public pid;

    /**
     * @notice Contract constructor
     * @param _pid Staking pool id
     * @param _lpToken LP token
     * @param _staking Staking contract
     * @param _router Router for swap
     */
    constructor(
        uint256 _pid,
        address _lpToken,
        address _staking,
        address _router
    ) {
        require(_lpToken != address(0), "LP: zero address");
        require(_staking != address(0), "Staking: zero address");
        require(_router != address(0), "Staking: zero address");

        pid = _pid;
        staking = ILPStaking(_staking);
        sourceToken = IERC20(_lpToken);
        router = IUniswapV2Router02(_router);
        yieldToken = IERC20(staking.stargate());
    }

    /**
     * @notice Returns pending STG yield
     */
    function pendingYield() public view override returns (uint256) {
        uint256 balance = yieldToken.balanceOf(address(this));
        return balance + staking.pendingStargate(pid, address(this));
    }

    /**
     * @notice Returns expected token from yield
     */
    function pendingYieldInToken(address outToken) external view override returns (uint256 amountOut) {
        uint256 amountIn = pendingYield();
        if (amountIn > 0) {
            address[] memory path = new address[](2);
            path[0] = address(yieldToken);
            path[1] = outToken;
            uint256[] memory amounts = router.getAmountsOut(amountIn, path);
            amountOut = amounts[amounts.length - 1];
        }
    }

    /**
     * @notice Total deposited lp token
     */
    function totalDeposit() external view override returns (uint256) {
        return _totalDeposit();
    }

    /**
     * @notice Stake lp tokens
     */
    function deposit(uint256 amount) external override onlyOwner {
        sourceToken.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
    }

    /**
     * @notice Withdraw lp tokens
     * @dev Harvest happens automatically by stargate
     */
    function withdraw(
        uint256 amount,
        bool claim,
        address to
    ) external override onlyOwner {
        staking.withdraw(pid, amount);
        uint256 balance = sourceToken.balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        sourceToken.safeTransfer(to, amount);
        if (!claim) {
            _deposit(amount);
        }
    }

    /**
     * @notice Harvest rewards
     */
    function claimAndConvert(
        address outToken,
        uint256 amount
    ) external override onlyOwner returns (uint256 yieldAmount, uint256 actualOut) {
        // harvest by withdraw
        ILPStaking.UserInfo memory info = staking.userInfo(pid, address(this));
        staking.withdraw(pid, info.amount);

        // redeposit asset
        _deposit(info.amount);

        if (amount > 0) {
            // swap yield into outToken
            yieldToken.safeApprove(address(router), amount);
            address[] memory path = new address[](2);
            path[0] = address(yieldToken);
            path[1] = outToken;
            uint256[] memory amounts = router.swapExactTokensForTokens(amount, 0, path, msg.sender, block.timestamp);
            actualOut = amounts[amounts.length - 1];
        }

        // transfer rest yield
        yieldAmount = _transferYield();
    }

    /**
     * @notice Total deposited lp token
     */
    function _totalDeposit() internal view returns (uint256) {
        ILPStaking.UserInfo memory info = staking.userInfo(pid, address(this));
        return info.amount;
    }

    /**
     * @notice Stake lp token
     */
    function _deposit(uint256 amount) internal {
        sourceToken.safeApprove(address(staking), amount);
        staking.deposit(pid, amount);
    }

    /**
     * @notice Transfer all yield tokens to vault
     */
    function _transferYield() internal returns (uint256 amount) {
        amount = yieldToken.balanceOf(address(this));
        yieldToken.safeTransfer(msg.sender, amount);
    }
}

