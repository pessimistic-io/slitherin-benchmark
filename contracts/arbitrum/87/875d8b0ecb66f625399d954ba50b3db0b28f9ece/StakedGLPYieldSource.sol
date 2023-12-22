// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";

import {IYieldSource} from "./IYieldSource.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";

/// @title Yield Source contract for Staked GLP
/// @author Y2K Finance
/// @dev This is for reward management by LP staking, not yield bearing asset
///      Owner of this contract is always SIV
contract StakedGLPYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    /// @notice Fee + Staked GLP token
    IERC20 public immutable override sourceToken;

    /// @notice Output token: WETH
    IERC20 public immutable override yieldToken;

    /// @notice GMX Reward Router
    IRewardRouterV2 public immutable rewardRouter;

    /// @notice Swap router
    IUniswapV2Router02 public swapRouter;

    /**
     * @notice Contract constructor
     * @param _sGLP Fee + Staked GLP
     * @param _weth WETH token
     * @param _rewardRouter Reward router contract
     * @param _swapRouter Swap router contract
     */
    constructor(
        address _sGLP,
        address _weth,
        address _rewardRouter,
        address _swapRouter
    ) {
        require(_sGLP != address(0), "sGLP: zero address");
        require(_weth != address(0), "WETH: zero address");
        require(_rewardRouter != address(0), "GMX router: zero address");
        require(_swapRouter != address(0), "Swap router: zero address");

        sourceToken = IERC20(_sGLP);
        yieldToken = IERC20(_weth);
        rewardRouter = IRewardRouterV2(_rewardRouter);
        swapRouter = IUniswapV2Router02(_swapRouter);
    }

    /**
     * @notice Total deposited lp token
     */
    function totalDeposit() external view override returns (uint256) {
        return sourceToken.balanceOf(address(this));
    }

    /**
     * @notice Returns pending yield
     */
    function pendingYield() public view override returns (uint256) {
        // WETH rewards
        IRewardTracker feeGlpTracker = IRewardTracker(
            rewardRouter.feeGlpTracker()
        );
        IRewardTracker feeGmxTracker = IRewardTracker(
            rewardRouter.feeGmxTracker()
        );
        return
            feeGlpTracker.claimable(address(this)) +
            feeGmxTracker.claimable(address(this)) +
            yieldToken.balanceOf(address(this));
    }

    /**
     * @notice Returns expected token from yield
     */
    function pendingYieldInToken(
        address outToken
    ) public view override returns (uint256 amountOut) {
        uint256 amountIn = pendingYield();
        if (outToken == address(yieldToken)) {
            return amountIn;
        }
        if (amountIn > 0) {
            address[] memory path = new address[](2);
            path[0] = address(yieldToken);
            path[1] = outToken;
            uint256[] memory amounts = swapRouter.getAmountsOut(amountIn, path);
            amountOut = amounts[amounts.length - 1];
        }
    }

    /**
     * @notice Stake sGLP tokens
     */
    function deposit(uint256 amount) external override onlyOwner {
        sourceToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraw lp tokens
     */
    function withdraw(
        uint256 amount,
        bool claim,
        address to
    ) external override onlyOwner {
        if (claim) _harvest();

        uint256 balance = sourceToken.balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        sourceToken.safeTransfer(to, amount);
    }

    /**
     * @notice Claim rewards and convert
     */
    function claimAndConvert(
        address outToken,
        uint256 amount
    )
        external
        override
        onlyOwner
        returns (uint256 yieldAmount, uint256 actualOut)
    {
        // harvest by withdraw
        _harvest();

        uint256 balance = yieldToken.balanceOf(address(this));
        // if available reward in reward tracker is not enough
        if (amount > balance) { amount = balance; }

        if (amount > 0) {
            if (outToken == address(yieldToken)) {
                yieldToken.transfer(msg.sender, amount);
                actualOut = amount;
            } else {
                // swap yield into outToken
                yieldToken.safeApprove(address(swapRouter), amount);
                address[] memory path = new address[](2);
                path[0] = address(yieldToken);
                path[1] = outToken;
                uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
                    amount,
                    0,
                    path,
                    msg.sender,
                    block.timestamp
                );
                actualOut = amounts[amounts.length - 1];
            }
        }

        yieldAmount = _transferYield();
    }

    /**
     * @notice Harvest rewards
     */
    function _harvest() internal returns (uint256 amount) {
        uint256 before = yieldToken.balanceOf(address(this));
        rewardRouter.claimFees();
        amount = yieldToken.balanceOf(address(this)) - before;
        rewardRouter.compound();
    }

    /**
     * @notice Transfer all yield tokens to vault
     */
    function _transferYield() internal returns (uint256 amount) {
        amount = yieldToken.balanceOf(address(this));
        yieldToken.safeTransfer(msg.sender, amount);
    }
}

