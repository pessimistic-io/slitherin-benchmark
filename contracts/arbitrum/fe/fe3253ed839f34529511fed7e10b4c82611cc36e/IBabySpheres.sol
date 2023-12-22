// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

interface IBabySpheres {
    error MintAlreadyEnabled();
    error MaximumSupplyExceeded();
    error ForbiddenToMintTokens();

    event MintEnabled(uint256 indexed mintEnablingTimestamp);
    event BaseURIUpdated(string indexed oldBaseURI, string indexed newBaseURI);

    /// @notice Enables possibility to mint tokens.
    function enableMint() external;

    /// @notice Updates the base URI.
    /// @param baseURI_ New base URI.
    function updateBaseURI(string calldata baseURI_) external;

    /// @notice Adds accounts to OG whitelist.
    /// @param accounts_ Account addresses.
    function addPrivatePeriodAccounts(address[] calldata accounts_) external;

    /// @notice Removes accounts from OG whitelist.
    /// @param accounts_ Account addresses.
    function removePrivatePeriodAccounts(address[] calldata accounts_) external;

    /// @notice Adds accounts to whitelist.
    /// @param accounts_ Account addresses.
    function addWhitelistPeriodAccounts(address[] calldata accounts_) external;

    /// @notice Removes accounts from whitelist.
    /// @param accounts_ Account addresses.
    function removeWhitelistPeriodAccounts(address[] calldata accounts_) external;

    /// @notice Mints 1 token for the caller.
    function mint() external;

    /// @notice Returns boolean value indicating whether the account is in private period accounts list or not.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether the account is in private period accounts list or not.
    function isPrivatePeriodAccount(address account_) external view returns (bool);

    /// @notice Returns the length of the private period accounts list.
    /// @return The length of the private period accounts list.
    function privatePeriodAccountsLength() external view returns (uint256);

    /// @notice Returns private period account by index.
    /// @param index_ Index value.
    /// @return Private period account by index.
    function privatePeriodAccountAt(uint256 index_) external view returns (address);

    /// @notice Returns boolean value indicating whether the account is in whitelist period accounts list or not.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether the account is in whitelist period accounts list or not.
    function isWhitelistPeriodAccount(address account_) external view returns (bool);

    /// @notice Returns the length of the whitelist period accounts list.
    /// @return The length of the whitelist period accounts list.
    function whitelistPeriodAccountsLength() external view returns (uint256);

    /// @notice Returns whitelist period account by index.
    /// @param index_ Index value.
    /// @return Whitelist period account by index.
    function whitelistPeriodAccountAt(uint256 index_) external view returns (address);

    /// @notice Returns boolean value indicating whether the account is in original minters list or not.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether the account is in original minters list or not.
    function isOriginalMinter(address account_) external view returns (bool);

    /// @notice Returns the length of the original minters list.
    /// @return The length of the original minters list.
    function originalMintersLength() external view returns (uint256);

    /// @notice Returns original minter by index.
    /// @param index_ Index value.
    /// @return Original minter by index.
    function originalMinterAt(uint256 index_) external view returns (address);
}
