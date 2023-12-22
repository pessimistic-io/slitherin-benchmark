// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IInsuranceFund {
    /// @param vault The address of the vault
    event VaultChanged(address vault);

    event ClearingHouseChanged(address clearingHouse);

    event InsuranceFundContributed(address baseToken, address contributor, uint256 amount, uint256 contributedAmount);

    event PlatformFeeReleased(address baseToken, address contributor, uint256 sharedFee, uint256 pendingFee);

    /// @notice Get settlement token address
    /// @return token The address of settlement token
    function getToken() external view returns (address token);

    /// @notice Get `Vault` address
    /// @return vault The address of `Vault`
    function getVault() external view returns (address vault);

    /// @notice Get `InsuranceFund` capacity
    /// @return capacityX10_S The capacity value (settlementTokenValue + walletBalance) in settlement token's decimals
    function getInsuranceFundCapacity(address baseToken) external view returns (int256 capacityX10_S);

    function getInsuranceFundCapacityFull(address baseToken) external view returns (int256 capacityX10_S);

    function getClearingHouse() external view returns (address);

    function getRepegAccumulatedFund(address baseToken) external view returns (int256);

    function getRepegDistributedFund(address baseToken) external view returns (int256);

    function addRepegFund(uint256 fund, address baseToken) external;

    function repegFund(int256 fund, address baseToken) external;

    function modifyPlatformFee(address baseToken, int256 amount) external;

    function addContributionFund(address baseToken, address contributor, uint256 amount) external;

    function contributeEther(address baseToken) external payable;

    function contributeEtherFor(address baseToken, address to) external payable;

    function contribute(address baseToken, address token, uint256 amount) external;

    function contributeFor(address baseToken, address token, uint256 amount, address to) external;

    function requestContributeEtherForCreated(address baseToken, address to) external payable;

    function requestContributeForCreated(address baseToken, address token, uint256 amount, address to) external;

    function withdrawPlatformFee(address baseToken) external;
}

