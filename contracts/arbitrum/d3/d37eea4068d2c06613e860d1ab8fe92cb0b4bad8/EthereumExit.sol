// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./UpgradeableBase.sol";
import "./IRECurveZapper.sol";
import "./ICurveGauge.sol";
import "./CheapSafeCurve.sol";
import "./ICurveStableSwap.sol";

using CheapSafeERC20 for IERC20;
using CheapSafeERC20 for ICurveStableSwap;

contract EthereumExit is UpgradeableBase(1)
{
    error ZeroAmount();

    bool public constant isEthereumExit = true;

    ICurveGauge constant oldGauge = ICurveGauge(0xd3dFD8f308c9e6d88d7C09c9a6575C691c810407);
    ICurveStableSwap constant oldPool = ICurveStableSwap(0xC61557C5d177bd7DC889A3b621eEC333e168f68A);
    ICurveStableSwap constant oldBasePool = ICurveStableSwap(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    IERC20 constant oldBasePoolToken = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    IERC20 constant oldREUSD = IERC20(0x29b41fE7d754B8b43D4060BB43734E436B0b9a33);
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    uint256 constant oldBasePoolUSDCIndex = 1;

    function checkUpgradeBase(address)
        internal
        override
        pure
    {
    }

    function exitGauge()
        public
    {
        uint256 balance = oldGauge.balanceOf(msg.sender);
        if (balance == 0) { revert ZeroAmount(); }
        oldGauge.transferFrom(msg.sender, address(this), balance);
        oldGauge.claim_rewards(msg.sender);
        CheapSafeCurve.safeWithdraw(address(oldGauge), balance, false);
        {
            uint256[2] memory minAmounts;
            minAmounts[0] = 1;
            minAmounts[1] = 1;
            oldPool.remove_liquidity(balance, minAmounts);
        }        
        balance = oldREUSD.balanceOf(address(this));
        require(balance > 0, "No old REUSD");
        oldREUSD.transfer(address(0), balance);
        usdc.transfer(msg.sender, balance / (10 ** 12));

        balance = oldBasePoolToken.balanceOf(address(this));
        require(balance > 0, "No old base pool tokens");
        CheapSafeCurve.safeRemoveLiquidityOneCoin(address(oldBasePool), usdc, oldBasePoolUSDCIndex, balance, 1, msg.sender);
    }

    function exitREUSD()
        public
    {
        uint256 balance = oldREUSD.balanceOf(msg.sender);
        if (balance == 0) { revert ZeroAmount(); }
        oldREUSD.transfer(address(0), balance);
        usdc.transfer(msg.sender, balance / (10 ** 12));
    }
}
