// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IEpoch.sol";

interface ITreasury is IEpoch {
    function getMainTokenPrice() external view returns (uint256);

    function getMainTokenUpdatedPrice() external view returns (uint256);

    function getDollarPrice() external view returns (uint256);

    function getPegTokenPrice(address _token) external view returns (uint256);

    function getPegTokenUpdatedPrice(address _token)
    external
    view
    returns (uint256);

    function getMainTokenLockedBalance() external view returns (uint256);

    function getMainTokenCirculatingSupply() external view returns (uint256);

    function getNextExpansionRate() external view returns (uint256);

    function getNextExpansionAmount() external view returns (uint256);

    function getPegTokenExpansionRate(address) external view returns (uint256);

    function getPegTokenExpansionAmount(address)
    external
    view
    returns (uint256);

    function previousEpochMainTokenPrice() external view returns (uint256);

    function boardroom() external view returns (address);

    function boardroomSharedPercent() external view returns (uint256);

    function daoFund() external view returns (address);

    function daoFundSharedPercent() external view returns (uint256);

    function marketingFund() external view returns (address);

    function marketingFundSharedPercent() external view returns (uint256);

    function insuranceFund() external view returns (address);

    function insuranceFundSharedPercent() external view returns (uint256);

    function getBondDiscountRate() external view returns (uint256);

    function getBondPremiumRate() external view returns (uint256);

    function buyBonds(uint256 amount, uint256 targetPrice) external;

    function redeemBonds(uint256 amount, uint256 targetPrice) external;
}
