// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IFactorLeverageVault {
    function isRegisteredUpgrade(
        address baseImplementation,
        address upgradeImplementation
    ) external view returns (bool);

    function registerUpgrade(address baseImplementation, address upgradeImplementation) external;

    function createPosition(address asset, address debt) external returns (uint256 id, address vault);

    function assets(address) external view returns (address);

    function asset() external view returns (address);

    function debtToken() external view returns (address);

    function assetBalance() external view returns (uint256);

    function debtBalance() external view returns (uint256);

    function leverageFee() external view returns (uint256);

    function debts(address) external view returns (address);

    function claimRewardFee() external view returns (uint256);

    function version() external view returns (string memory);

    function feeRecipient() external view returns (address);

    function FEE_SCALE() external view returns (uint256);

    function positions(uint256) external view returns (address);

    function initialize(uint256, address, address, address, address, address) external;

    function tokenURI(uint256 id) external view returns (string memory);
}

