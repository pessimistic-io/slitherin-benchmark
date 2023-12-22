// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IComptroller {
    function closeFactorMantissa() external view returns (uint);

    function closeFactor() external view returns (uint);

    function enterMarkets(address[] memory) external;

    function enterMarkets(address[] memory, address) external;

    function enterMarkets(address, address) external;

    function exitMarket(address cTokenAddress) external returns (uint256);

    function exitMarkets(address[] memory) external returns (uint256);

    // function mintAllowed(address dToken, address minter) external returns (uint256);

    function mintAllowed(address dToken, address minter, uint) external returns (bool, string memory);

    // function redeemAllowed(address jToken, address redeemer, uint256 redeemTokens) external returns (uint256);

    function redeemAllowed(address jToken, address redeemer, uint256 redeemTokens) external returns (uint);

    function allMarkets() external view returns (address[] memory);

    function getAllMarkets() external view returns (address[] memory);

    function getMarketList() external view returns (address[] memory);

    function getAlliTokens() external view returns (address[] memory);

    function isBorrowPaused(address) external view returns (bool);

    function isMintPaused(address) external view returns (bool);

    function isPauseGuardian(address) external view returns (bool);

    function borrowGuardianPaused(address) external view returns (bool);

    function mintGuardianPaused(address) external view returns (bool);

    function guardianPaused(address) external view returns (bool);

    function pTokenBorrowGuardianPaused(address) external view returns (bool);

    function pTokenMintGuardianPaused(address) external view returns (bool);

    function isDeprecated(address) external view returns (bool);

    function borrowAllowed(address, address, uint) external view returns (uint);

    // function markets(address) external view returns (bool, uint256, bool);

    function markets(address) external view returns (bool, uint256);

    function tokenConfigs(address) external view returns (bool, bool, bool, bool, bool);

    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);

    // function getAccountLiquidity(address account, bool) external view returns (uint256, uint256, uint256);

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint);

    function oracle() external view returns (address);

    function admin() external view returns (address);

    function owner() external view returns (address);

    function liquidationIncentiveMantissa() external view returns (uint);
}

