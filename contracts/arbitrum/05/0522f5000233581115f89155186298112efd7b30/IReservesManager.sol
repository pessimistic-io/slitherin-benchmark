// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

interface IReservesManager {
    function estimateFees(
        bool _isSelling,
        bool _isBuying,
        uint256 _amount
    ) external returns (uint256, uint256);

    function updateBuyFees(uint256 _burnFee) external;

    function updateSellFees(uint256 _burnFee) external;

    function updateReservesFees(uint256 _reservesFees) external;

    function updateTokenAddress(address _newAddr) external;
}
