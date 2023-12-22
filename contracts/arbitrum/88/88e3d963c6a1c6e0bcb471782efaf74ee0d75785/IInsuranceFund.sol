// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IInsuranceFund {
    /// @param vault The address of the vault
    event VaultChanged(address vault);

    event ClearingHouseChanged(address clearingHouse);

    /// @notice Get settlement token address
    /// @return token The address of settlement token
    function getToken() external view returns (address token);

    /// @notice Get `Vault` address
    /// @return vault The address of `Vault`
    function getVault() external view returns (address vault);

        /// @notice Get `InsuranceFund` capacity
    /// @return capacityX10_S The capacity value (settlementTokenValue + walletBalance) in settlement token's decimals
    function getInsuranceFundCapacity() external view returns (int256 capacityX10_S);

    function getClearingHouse() external view returns (address);

    function getRepegAccumulatedFund() external view returns (int256);

    function getRepegDistributedFund() external view returns (int256);

    function addRepegFund(uint256 fund) external;

    function repegFund(int256 fund) external;
}

