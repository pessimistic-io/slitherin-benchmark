// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IFactorLeverageVault {

    function isRegisteredUpgrade(
        address baseImplementation,
        address upgradeImplementation
    ) external view returns (bool);

    function registerUpgrade(address baseImplementation, address upgradeImplementation) external;

    function createPosition(address asset, address debt) external returns (uint256 id, address strategy);

    function assets(address) external view returns (address);

    function leverageFee() external view returns (uint256);

    function debts(address) external view returns (address);

    function claimRewardFee() external view returns (uint256);

    function version() external pure returns (string memory);

    function feeRecipient() external view returns (address);

    function FEE_SCALE() external view returns (uint256);

    function positions(uint256) external view returns (address);

    function tokenURI(uint256 id) external view returns (string memory);

    function burnPosition(uint256 positionId) external;
}

