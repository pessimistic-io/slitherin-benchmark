// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./BehaviorTaxedTradingToken.sol";
import "./BehaviorUniswapableV2Token.sol";
import "./BehaviorSafetyLimitsToken.sol";
import "./BehaviorSafetyMethods.sol";
import "./console.sol";

contract AnylToken is
    ERC20,
    BehaviorTaxedTradingToken,
    BehaviorUniswapableV2Token,
    BehaviorUniswapableV2,
    BehaviorSafetyLimitsToken,
    BehaviorSafetyMethods
{
    bool private internalSwapping = false;

    address public treasuryDevRewards;

    constructor(
        address _addressRouter
    )
        ERC20(unicode"ArbNewYearLottery", "ANYL")
        BehaviorUniswapableV2Token(_addressRouter)
        BehaviorUniswapableV2(_addressRouter, address(this))
    {
        _mint(msg.sender, 100_000_000 * 10 ** 18);
        maxTransactionSize = 1_000_000 * 10 ** 18;
        maxWalletSize = maxTransactionSize * 4;
        buyTaxPercent = 5;
        sellTaxPercent = 10;
    }

    function configureTreasury(address _treasuryDevRewards) public onlyOwner {
        treasuryDevRewards = _treasuryDevRewards;
    }

    function enableAllBehaviors() public onlyOwner {
        enableDisableSafetyLimits(true);
        enableDisableTransactionTaxing(true);
    }

    function disableAllBehaviors() public onlyOwner {
        enableDisableSafetyLimits(false);
        enableDisableTransactionTaxing(false);
    }

    function _transfer(address _from, address _to, uint256 _amount) internal virtual override {
        if (internalSwapping == false) {
            _transferCheckLimits(_from, _to, _amount);

            (uint256 amount, uint256 tax, bool isPurchase, , bool isExcluded) = _taxableTransfer(_from, _to, _amount);
            if (tax > 0) _internalTransfer(_from, address(this), tax);
            if (isExcluded == false) _internalHandleTaxes(isPurchase);
            _amount = amount;
        }

        _internalTransfer(_from, _to, _amount);
    }

    function _internalHandleTaxes(bool isPurchase) internal {
        uint256 balanceToken = IERC20(address(this)).balanceOf(address(this));

        if (balanceToken > 1_000 * 10 ** 18) {
            internalSwapping = true;
            if (treasuryDevRewards != address(0)) {
                if (isPurchase == false) _swapTokensForEth(balanceToken, 0, treasuryDevRewards);
            }
            internalSwapping = false;
        }
    }

    function _internalTransfer(address from, address to, uint256 amount) internal {
        super._transfer(from, to, amount);
    }

    function createLiquidityTokenAndEth(uint256 _amountTokens) public payable onlyOwner {
        uint256 amountETH = msg.value;
        ERC20(addressManagedToken).transferFrom(msg.sender, address(this), _amountTokens);
        _addTokensToLiquidityETH(_amountTokens, amountETH);
    }
}

