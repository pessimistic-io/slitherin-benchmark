// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import "./IOriginalMintersPool.sol";

interface IEtherealSpheres {
    enum Period { PRIVATE, WHITELIST, PUBLIC }

    error InvalidPeriod();
    error InvalidNumberOfTokens();
    error ForbiddenToMintMore();
    error InvalidMsgValue();
    error ForbiddenToMint();
    error ZeroEntry();
    error InvalidProof();

    event OriginalMintersPoolUpdated(
        IOriginalMintersPool indexed oldOriginalMintersPool, 
        IOriginalMintersPool indexed newOriginalMintersPool
    );
    event PeriodUpdated(Period indexed oldPeriod, Period indexed newPeriod);
    event TokenPriceUpdated(uint256 indexed oldTokenPrice, uint256 indexed newTokenPrice);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event BaseURIUpdated(string indexed oldBaseURI, string indexed newBaseURI);
    event AvailableNumberOfTokensToMintIncreased(
        uint256 indexed oldAvailableNumberOfTokensToMint, 
        uint256 indexed newAvailableNumberOfTokensToMint,
        uint256 indexed difference
    );
    event AvailableNumberOfTokensToMintDecreased(
        uint256 indexed oldAvailableNumberOfTokensToMint, 
        uint256 indexed newAvailableNumberOfTokensToMint,
        uint256 indexed difference
    );

    /// @notice Adds accounts to whitelist.
    /// @param accounts_ Account addresses.
    /// @param period_ Minting period.
    function addAccountsToWhitelist(address[] calldata accounts_, Period period_) external;

    /// @notice Removes accounts from whitelist.
    /// @param accounts_ Account addresses.
    /// @param period_ Minting period.
    function removeAccountsFromWhitelist(address[] calldata accounts_, Period period_) external;

    /// @notice Updates the OriginalMintersPool contract address.
    /// @param originalMintersPool_ New OriginalMintersPool contract address.
    function updateOriginalMintersPool(IOriginalMintersPool originalMintersPool_) external;

    /// @notice Updates the minting period.
    /// @param period_ New minting period.
    function updatePeriod(Period period_) external;

    /// @notice Updates the minting price per token.
    /// @param price_ New minting price per token.
    function updatePrice(uint256 price_) external;

    /// @notice Updates the treasury.
    /// @param treasury_ New treasury address.
    function updateTreasury(address payable treasury_) external;

    /// @notice Updates the base URI.
    /// @param baseURI_ New base URI.
    function updateBaseURI(string calldata baseURI_) external;

    /// @notice Increases the available amount of tokens to mint.
    /// @param numberOfTokens_ Number of tokens to increase.
    function increaseAvailableNumberOfTokensToMint(uint256 numberOfTokens_) external;

    /// @notice Decreases the available amount of tokens to mint.
    /// @param numberOfTokens_ Number of tokens to decrease.
    function decreaseAvailableNumberOfTokensToMint(uint256 numberOfTokens_) external;

    /// @notice Withdraws payments for mint.
    function withdraw() external;

    /// @notice Mints `numberOfTokens_` tokens to `account_` for free.
    /// @param account_ Account address.
    /// @param numberOfTokens_ Number of tokens to mint.
    function reserve(address account_, uint256 numberOfTokens_) external;

    /// @notice Mints `numberOfTokens_` tokens to the caller during private period.
    /// @param numberOfTokens_ Number of tokens to mint.
    function privatePeriodMint(uint256 numberOfTokens_) external payable;

    /// @notice Mints `numberOfTokens_` tokens to the caller during whitelist period.
    /// @param numberOfTokens_ Number of tokens to mint.
    function whitelistPeriodMint(uint256 numberOfTokens_) external payable;

    /// @notice Mints `numberOfTokens_` tokens to the caller during public period.
    /// @param numberOfTokens_ Number of tokens to mint.
    function publicPeriodMint(uint256 numberOfTokens_) external payable;

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
