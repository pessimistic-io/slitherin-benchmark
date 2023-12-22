// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./EnumerableSet.sol";
import "./Dev.sol";

abstract contract Fee is Dev {
    using EnumerableSet for EnumerableSet.AddressSet;
    address internal blackholdAddress =
        address(0x000000000000000000000000000000000000dEaD);
    address public jackpotAddress = address(0);
    address public luckyAddress = address(0);

    // buy fees
    uint256 public buyDevFee = 0;
    uint256 public buyLiquidityFee = 10;
    uint256 public buyJackpotFee = 40;

    // sell fees
    uint256 public sellBlackFee = 0;
    uint256 public sellDevFee = 10;
    uint256 public sellLiquidityFee = 10;
    uint256 public sellJackpotFee = 40;
    uint256 public sellBonusFee = 30;
    uint256 public sellLuckyFee = 10;

    EnumerableSet.AddressSet private excludedFromFee;

    function _calcPercent(
        uint256 amount,
        uint256 procedureFeePercent
    ) internal pure returns (uint256) {
        return (amount * procedureFeePercent) / (10 ** 3);
    }

    function _calcPercent2(
        uint256 amount,
        uint256 procedureFeePercent,
        uint256 totalPercent
    ) internal pure returns (uint256) {
        return (amount * procedureFeePercent) / totalPercent;
    }

    function setFeeAddress(
        address _jackpotAddress,
        address _luckyAddress
    ) external onlyManger {
        jackpotAddress = _jackpotAddress;
        luckyAddress = _luckyAddress;
    }

    function addExcludeFromFee(address account) external onlyManger {
        excludedFromFee.add(account);
    }

    function _addExcludeFromFee(address account) internal {
        excludedFromFee.add(account);
    }

    function removeExcludeFromFee(
        address[] memory accounts
    ) external onlyManger {
        for (uint256 i = 0; i < accounts.length; i++) {
            excludedFromFee.remove(accounts[i]);
        }
    }

    function isExcludeFromFee(address account) public view returns (bool) {
        return excludedFromFee.contains(account);
    }

    function _buyTotalFee() internal view returns (uint256) {
        return buyLiquidityFee + buyJackpotFee + buyDevFee;
    }

    function _sellTotalFee() internal view returns (uint256) {
        return
            sellBlackFee +
            sellLiquidityFee +
            sellJackpotFee +
            sellBonusFee +
            sellLuckyFee +
            sellDevFee;
    }
}

