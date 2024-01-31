// SPDX-License-Identifier: No license

pragma solidity 0.8.18;

/// @title Interface: Blacklist
/// @notice Interface for Blacklist.sol

interface IBlacklist {

    /****************************************************************
     *                           Errors                             
     ****************************************************************/

    /// Either the `from` or `to` address is blacklisted
    error AccountBlacklisted();
    /// The caller does not have permission to blacklist accounts
    error NotBlacklister();

    /****************************************************************
     *                        Events                                
     ****************************************************************/

    /// The `target` has been blacklisted
    event Blacklisted(address indexed target);
    ///  The `target` has been removed from the blacklist
    event BlacklistRevoked(address indexed target);
    /// The blacklister address has been changed
    event NewBlacklister(address indexed newBlacklister);

    /****************************************************************
     *                    Getter Functions                          
     ****************************************************************/

    /**
     * @dev Check if a `target` is blacklisted
     */
    function isBlacklisted(address target) external view returns (bool);

    /**
     * @dev Check if a `target` is the blacklister account
     */
    function getBlacklister() external view returns (address);

}
