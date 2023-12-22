// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IERC20.sol";
import "./BehaviorSwapableToken.sol";
import "./console.sol";

contract BehaviorSafetyLimitsToken is BehaviorSwapableToken {
    bool private safetyLimitsEnabled = true;
    mapping(address => bool) private addressesWalletsExcludedFromSafetyLimits;

    uint256 public maxTransactionSize;
    uint256 public maxWalletSize;

    constructor() {
        setSafetyLimitsExcludedWalletAddress(address(0), true);
        setSafetyLimitsExcludedWalletAddress(address(0xdead), true);
        setSafetyLimitsExcludedWalletAddress(address(this), true);
        setSafetyLimitsExcludedWalletAddress(msg.sender, true);
    }

    function enableDisableSafetyLimits(bool _enabled) public onlyOwner {
        safetyLimitsEnabled = _enabled;
    }

    function setSafetyLimitsExcludedWalletAddress(address _address, bool _isExcluded) public onlyOwner {
        addressesWalletsExcludedFromSafetyLimits[_address] = _isExcluded;
    }

    function setMaximumTradeSize(uint256 _size) external onlyOwner {
        uint256 totalSupply = IERC20(address(this)).totalSupply();
        require(_size >= ((totalSupply * 1) / 1000), "setMaximumTradeSize can't be lower than 0.1%");
        maxTransactionSize = _size;
    }

    function setMaximumWalletSize(uint256 _size) external onlyOwner {
        uint256 totalSupply = IERC20(address(this)).totalSupply();
        require(_size >= ((totalSupply * 5) / 1000), "setMaximumTradeSize can't be lower than 0.5%");
        maxWalletSize = _size;
    }

    function _transferCheckLimits(address _from, address _to, uint256 _amount) internal view {
        if (!safetyLimitsEnabled) return;

        bool isExcluded = addressesWalletsExcludedFromSafetyLimits[_to] ||
            addressesWalletsExcludedFromSafetyLimits[_from];
        bool isPurchase = tradingContractsAddresses[_from];
        bool isSell = tradingContractsAddresses[_to];

        if (isExcluded || (!isPurchase && !isSell)) return;

        if (isPurchase) {
            uint256 balance = IERC20(address(this)).balanceOf(_to);

            require(
                maxTransactionSize == 0 || _amount <= maxTransactionSize,
                "Buy size exceeded maximum size configured in maxTransactionSize"
            );
            require(
                maxWalletSize == 0 || (_amount + balance <= maxWalletSize),
                "Purchase will exceed max wallet amount"
            );
        }

        if (isSell) {
            require(
                maxTransactionSize == 0 || _amount <= maxTransactionSize,
                "Sell size exceeded maximu size configured in maxTransactionSize"
            );
        }
    }
}

