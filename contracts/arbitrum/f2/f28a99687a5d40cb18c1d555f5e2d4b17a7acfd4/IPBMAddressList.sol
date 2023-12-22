// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title PBM Address list Interface.
/// @notice The PBM address list stores and manages whitelisted merchants and blacklisted address for the PBMs
interface IPBMAddressList {
    /// @notice Adds wallet addresses to the blacklist who are unable to receive the pbm tokens.
    /// @param addresses The list of merchant wallet address
    /// @param metadata any comments on the addresses being added
    function blacklistAddresses(address[] memory addresses, string memory metadata) external;

    /// @notice Removes wallet addresses from the blacklist who are  unable to receive the PBM tokens.
    /// @param addresses The list of merchant wallet address
    /// @param metadata any comments on the addresses being added
    function unBlacklistAddresses(address[] memory addresses, string memory metadata) external;

    /// @notice Checks if the address is one of the blacklisted addresses
    /// @param _address The address in query
    /// @return True if address is a blacklisted, else false
    function isBlacklisted(address _address) external returns (bool);

    /// @notice Adds wallet addresses of merchants who are the only wallets able to receive the underlying ERC-20 tokens (whitelisting).
    /// @param addresses The list of merchant wallet address
    /// @param metadata any comments on the addresses being added
    function addMerchantAddresses(address[] memory addresses, string memory metadata) external;

    /// @notice Removes wallet addresses from the merchant addresses who are  able to receive the underlying ERC-20 tokens (un-whitelisting).
    /// @param addresses The list of merchant wallet address
    /// @param metadata any comments on the addresses being added
    function removeMerchantAddresses(address[] memory addresses, string memory metadata) external;

    /// @notice Checks if the address is one of the whitelisted merchant
    /// @param _address The address in query
    /// @return True if address is a merchant, else false
    function isMerchant(address _address) external returns (bool);

    /// @notice Adds wallet addresses of merchants who are hero merchants.
    /// @param addresses The list of hero merchant wallet address
    /// @param token_ids The list of heroNFT token_id
    function addHeroMerchant(address[] memory addresses, uint256[] memory token_ids) external;

    /// @notice Removes wallet addresses of merchants who are hero merchants.
    /// @param addresses The list of hero merchant wallet address
    function removeHeroMerchant(address[] memory addresses) external;

    /// @notice Get the heroNFT token_id
    /// @param _address The address in query
    /// @return 0 if not a hero merchant, else the heroNFT token_id
    function getHeroNFTId(address _address) external returns (uint256);

    /// @notice Event emitted when the Merchant List is edited
    /// @param action Tags "add" or "remove" for action type
    /// @param addresses The list of merchant wallet address
    /// @param metadata any comments on the addresses being added
    event MerchantList(string action, address[] addresses, string metadata);

    /// @notice Event emitted when the Blacklist is edited
    /// @param action Tags "add" or "remove" for action type
    /// @param addresses The list of merchant wallet address
    /// @param metadata any comments on the addresses being added
    event Blacklist(string action, address[] addresses, string metadata);
}

