// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IApeRouter02.sol";
import "./IApePair.sol";

abstract contract ApeSwapZapLPMigrator is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IApeRouter02 public immutable apeRouter;

    event LPMigrated(
        IApePair lp,
        IApeRouter02 fromRouter,
        IApeRouter02 toRouter,
        uint256 amount
    );

    constructor(IApeRouter02 router) {
        apeRouter = router;
    }

    /// @notice Zap non APE-LPs to APE-LPs
    /// @param router The non APE-LP router
    /// @param lp LP address to zap
    /// @param amount Amount of LPs to zap
    /// @param amountAMinRemove The minimum amount of token0 to receive after removing liquidity
    /// @param amountBMinRemove The minimum amount of token1 to receive after removing liquidity
    /// @param amountAMinAdd The minimum amount of token0 to add to APE-LP on add liquidity
    /// @param amountBMinAdd The minimum amount of token1 to add to APE-LP on add liquidity
    /// @param deadline Unix timestamp after which the transaction will revert
    function zapLPMigrator(
        IApeRouter02 router,
        IApePair lp,
        uint256 amount,
        uint256 amountAMinRemove,
        uint256 amountBMinRemove,
        uint256 amountAMinAdd,
        uint256 amountBMinAdd,
        uint256 deadline
    ) external nonReentrant {
        address token0 = lp.token0();
        address token1 = lp.token1();

        IERC20(address(lp)).safeTransferFrom(msg.sender, address(this), amount);
        lp.approve(address(router), amount);
        (uint256 amountAReceived, uint256 amountBReceived) = router
            .removeLiquidity(
                token0,
                token1,
                amount,
                amountAMinRemove,
                amountBMinRemove,
                address(this),
                deadline
            );

        IERC20(token0).approve(address(apeRouter), amountAReceived);
        IERC20(token1).approve(address(apeRouter), amountBReceived);
        (uint256 amountASent, uint256 amountBSent, ) = apeRouter.addLiquidity(
            token0,
            token1,
            amountAReceived,
            amountBReceived,
            amountAMinAdd,
            amountBMinAdd,
            msg.sender,
            deadline
        );

        if (amountAReceived - amountASent > 0) {
            IERC20(token0).safeTransfer(
                msg.sender,
                amountAReceived - amountASent
            );
        }
        if (amountBReceived - amountBSent > 0) {
            IERC20(token1).safeTransfer(
                msg.sender,
                amountBReceived - amountBSent
            );
        }

        emit LPMigrated(lp, router, apeRouter, amount);
    }
}

