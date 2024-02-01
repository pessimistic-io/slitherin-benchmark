// SPDX-License-Identifier: No license

pragma solidity 0.8.18;

/// @title Blacklist
/// @notice Composable Blacklist Logic Contract

/**
 * Note: In certain instances it might be beneficial to rework `accounts`
 * to a mapping of address => uint8 and use bit packing to represent other
 * roles a protocol may need (e.g. `burner`, `blacklister`, etc) to make more
 * efficient use of storage.
 *
 * This contract relies on derived contracts to expose internal functionality.
 *
 */

import "./IBlacklist.sol";

contract Blacklist is IBlacklist {
    /****************************************************************
     *                      State Variables                         
     ****************************************************************/

    /// The account that can blacklist accounts
    address internal blacklister;

    /// A mapping containing the addresses of blacklisted users
    mapping(address => bool) internal accounts;

    /****************************************************************
     *                        Modifiers                             
     ****************************************************************/

    /**
     * @dev Access control: Blacklister
     */
    modifier onlyBlacklister() {
        if (getBlacklister() != msg.sender) revert NotBlacklister();
        _;
    }

    /****************************************************************
     *                   Inititialization Logic                     
     ****************************************************************/

    /// @notice Initializes the token contract
    /// @dev This contract is intended to be deployed behind an upgradeable proxy
    /// @param initialBlacklister The address of the account allowed to `blacklist` other accounts
    function _initializeBlacklist(address initialBlacklister) internal {
        blacklister = initialBlacklister;
    }

    /****************************************************************
     *                     Blacklist Logic                           
     ****************************************************************/

    /// @notice Blacklist's a `target` account
    /// @dev For AML compliance the MTC Issuer must be able to blacklist accounts engaged in high-risk activities
    /// @dev Blacklisted accounts cannot `transfer` or `receive` tokens
    /// Note: Blacklisting can be revoked
    /// @param target The address that is to be blacklisted
    function _blacklistAccount(address target) internal virtual {
        accounts[target] = true;

        emit Blacklisted(target);
    }

    /// @notice Revokes an account's blacklisted status
    /// @dev Business logic requires that accounts that are cleared after investigation be allowed to `send` and `receive` tokens again
    /// Note Does not check is `target` is already blacklisted
    /// @param target The account that should be removed from `blacklist`
    function _revokeBlacklisting(address target) internal virtual {
        /// Set the `target` to false
        delete accounts[target];

        emit BlacklistRevoked(target);
    }

    /****************************************************************
     *                    Getter Functions                          
     ****************************************************************/

    /**
     * @dev Check if a `target` is blacklisted
     */
    function isBlacklisted(address target) public view returns (bool) {
        return accounts[target];
    }

    /**
     * @dev Check if a `target` is the blacklister account
     */
    function getBlacklister() public view returns (address) {
        return blacklister;
    }

    /****************************************************************
     *                    Internal Utility Logic                    
     ****************************************************************/

    /// @notice Sets the `blacklister` account to `newBlacklister` address
    /// @dev Beware: validity check is left to the derived contract
    /// @param newBlacklister The address of the new `blacklister`
    function _setBlacklister(address newBlacklister) internal {
        blacklister = newBlacklister;

        emit NewBlacklister(newBlacklister);
    }


}
