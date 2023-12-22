// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IFactorLeverageVault {
    function isRegisteredUpgrade(
        address baseImplementation,
        address upgradeImplementation
    ) external view returns (bool);

    function assets(address) external view returns (address);

    function leverageFee() external view returns (uint256);

    function debts(address) external view returns (address);

    function claimRewardFee() external view returns (uint256);

    function feeRecipient() external view returns (address);

    function FEE_SCALE() external view returns (uint256);
}
