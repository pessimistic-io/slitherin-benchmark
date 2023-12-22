// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.6;

import "./SafeERC20.sol";
import "./LowGasSafeMath.sol";

import "./ILiquidCVaultV6.sol";
import "./IStargateRouter.sol";
import "./IStrategyStargateStaking.sol";


contract LiquidCZapStargate {
    using LowGasSafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for ILiquidCVaultV6;

    uint256 public constant minimumAmount = 1000;
    address public stargateRouter;

    constructor(address _stargateRouter) {
        stargateRouter = _stargateRouter;
    }

    receive() external payable {}

    function LiquidCIn (address liquidCVault, uint256 tokenAmountOutMin, address tokenIn, uint256 tokenInAmount) external {
        require(tokenInAmount >= minimumAmount, 'LiquidC: Insignificant input amount');
        require(IERC20(tokenIn).allowance(msg.sender, address(this)) >= tokenInAmount, 'LiquidC: Input token is not approved');

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
        uint256 depositBal = IERC20(tokenIn).balanceOf(address(this));

        ILiquidCVaultV6 vault = ILiquidCVaultV6(liquidCVault);
        IStrategyStargateStaking strategy = IStrategyStargateStaking(vault.strategy());
        uint256 poolID = strategy.routerPoolId();
        address lpToken = vault.want();

        _approveTokenIfNeeded(tokenIn, stargateRouter);
        IStargateRouter(stargateRouter).addLiquidity(poolID, depositBal, address(this));

        _approveTokenIfNeeded(address(lpToken), address(liquidCVault));
        uint256 amountLiquidity = IERC20(lpToken).balanceOf(address(this));
        
        vault.deposit(amountLiquidity);

        vault.safeTransfer(msg.sender, vault.balanceOf(address(this)));
    }

    function LiquidCOut (address liquidCVault, uint256 withdrawAmount) public {
        ILiquidCVaultV6 vault = ILiquidCVaultV6(liquidCVault);
        IStrategyStargateStaking strategy = IStrategyStargateStaking(vault.strategy());
        uint16 poolID = uint16(strategy.routerPoolId());
        address lpToken = vault.want();

        IERC20(liquidCVault).safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);

        uint256 amountLiquidity = IERC20(lpToken).balanceOf(address(this));
        IStargateRouter(stargateRouter).instantRedeemLocal(poolID, amountLiquidity, msg.sender);
    }

    function LiquidCOutAndSwap (address liquidCVault, uint256 withdrawAmount, address desiredToken, uint256 desiredTokenOutMin) external {
        LiquidCOut(liquidCVault, withdrawAmount);
    }

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }
}

