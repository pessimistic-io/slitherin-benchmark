// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IProtectionPool {
    function pauseProtectionPool(bool _paused) external;

    function providedLiquidity(uint256 _amount, address _provider) external;

    function removedLiquidity(uint256 _amount, address _provider)
        external
        returns (uint256);

    function getTotalCovered() external view returns (uint256);

    function getTotalActiveCovered() external view returns (uint256);

    function updateWhenBuy() external;

    function removedLiquidityWhenClaimed(uint256 _amount, address _to) external;

    function getLatestPrice() external returns (uint256);

    function updateStakedSupply(bool isStake, uint256 amount) external;

    function stakedSupply() external view returns (uint256);
}

