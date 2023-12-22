//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

interface ICurve2PoolSsovPut {
    function deposit(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (bool);

    function depositMultiple(
        uint256[] memory strikeIndices,
        uint256[] memory amounts,
        address user
    ) external returns (bool);

    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (uint256 premium, uint256 totalFee);

    function calculatePremium(uint256 strike, uint256 amount)
        external
        view
        returns (uint256);

    function calculatePurchaseFees(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) external view returns (uint256);

    function getEpochStrikes(uint256 epoch)
        external
        view
        returns (uint256[] memory);

    function getEpochStrikeTokens(uint256 epoch)
        external
        view
        returns (address[] memory);

    function getUserEpochDeposits(uint256 epoch, address user)
        external
        view
        returns (uint256[] memory);

    function settle(
        uint256 strikeIndex,
        uint256 amount,
        uint256 epoch
    ) external returns (uint256);

    function withdraw(uint256 epoch, uint256 strikeIndex)
        external
        returns (uint256[2] memory);

    function addToContractWhitelist(address _contract) external returns (bool);

    function baseToken() external view returns (address);

    function currentEpoch() external view returns (uint256);

    function getUsdPrice() external view returns (uint256);

    function getLpPrice() external view returns (uint256);

    function calculatePnl(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) external pure returns (uint256);

    function settlementPrices(uint256 epoch) external view returns (uint256);

    function epochStrikes(uint256 epoch, uint256 index)
        external
        view
        returns (uint256);
}

