// contracts/behaviors/TaxableToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./BehaviorSwapableToken.sol";
import "./console.sol";

contract BehaviorTaxedTradingToken is BehaviorSwapableToken {
    bool public taxingEnabled = true;
    uint256 public buyTaxPercent = 0;
    uint256 public sellTaxPercent = 0;
    mapping(address => bool) private addressesWalletsExcludedFromTaxing;

    constructor() {
        setTaxingExcludedWalletAddress(address(0), true);
        setTaxingExcludedWalletAddress(address(0xdead), true);
        setTaxingExcludedWalletAddress(msg.sender, true);
        setTaxingExcludedWalletAddress(address(this), true);
    }

    function enableDisableTransactionTaxing(bool _enabled) public onlyOwner {
        taxingEnabled = _enabled;
    }

    function setTaxingExcludedWalletAddress(address _address, bool _isExcluded) public onlyOwner {
        addressesWalletsExcludedFromTaxing[_address] = _isExcluded;
    }

    function setTaxes(uint256 _buyTaxPercent, uint256 _sellTaxPercent) public onlyOwner {
        require(_buyTaxPercent >= 0 && _buyTaxPercent <= 100, "Buy tax percent out of limits");
        require(_sellTaxPercent >= 0 && _sellTaxPercent <= 100, "Sell tax percent out of limits");
        buyTaxPercent = _buyTaxPercent;
        sellTaxPercent = _sellTaxPercent;
    }

    function _taxableTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual returns (uint256 amount, uint256 tax, bool isPurchase, bool isSell, bool isExcluded) {
        isExcluded =
            taxingEnabled == false ||
            addressesWalletsExcludedFromTaxing[_to] ||
            addressesWalletsExcludedFromTaxing[_from];
        isPurchase = tradingContractsAddresses[_from];
        isSell = tradingContractsAddresses[_to];

        if (buyTaxPercent > 0 && isPurchase && isExcluded == false) {
            tax = (_amount * buyTaxPercent) / 100;
            amount = _amount - tax;
        } else if (sellTaxPercent > 0 && isSell && isExcluded == false) {
            tax = (_amount * sellTaxPercent) / 100;
            amount = _amount - tax;
        } else {
            tax = 0;
            amount = _amount;
        }
    }
}

