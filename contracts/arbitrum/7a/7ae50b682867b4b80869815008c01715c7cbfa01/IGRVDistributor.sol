// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./Constant.sol";

interface IGRVDistributor {
    /* ========== EVENTS ========== */
    event SetCore(address core);
    event SetPriceCalculator(address priceCalculator);
    event SetEcoScore(address ecoScore);
    event SetTaxTreasury(address treasury);
    event GRVDistributionSpeedUpdated(address indexed gToken, uint256 supplySpeed, uint256 borrowSpeed);
    event GRVClaimed(address indexed user, uint256 amount);
    event GRVCompound(
        address indexed account,
        uint256 amount,
        uint256 adjustedValue,
        uint256 taxAmount,
        uint256 expiry
    );
    event SetDashboard(address dashboard);
    event SetLendPoolLoan(address lendPoolLoan);

    function approve(address _spender, uint256 amount) external returns (bool);

    function accruedGRV(address[] calldata markets, address account) external view returns (uint256);

    function distributionInfoOf(address market) external view returns (Constant.DistributionInfo memory);

    function accountDistributionInfoOf(
        address market,
        address account
    ) external view returns (Constant.DistributionAccountInfo memory);

    function apyDistributionOf(address market, address account) external view returns (Constant.DistributionAPY memory);

    function boostedRatioOf(
        address market,
        address account
    ) external view returns (uint256 boostedSupplyRatio, uint256 boostedBorrowRatio);

    function notifySupplyUpdated(address market, address user) external;

    function notifyBorrowUpdated(address market, address user) external;

    function notifyTransferred(address gToken, address sender, address receiver) external;

    function claimGRV(address[] calldata markets, address account) external;

    function compound(address[] calldata markets, address account) external;

    function firstDeposit(address[] calldata markets, address account, uint256 expiry) external;

    function kick(address user) external;
    function kicks(address[] calldata users) external;

    function updateAccountBoostedInfo(address user) external;
    function updateAccountBoostedInfos(address[] calldata users) external;

    function getTaxTreasury() external view returns (address);

    function getPreEcoBoostedInfo(
        address market,
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view returns (uint256 boostedSupply, uint256 boostedBorrow);
}

