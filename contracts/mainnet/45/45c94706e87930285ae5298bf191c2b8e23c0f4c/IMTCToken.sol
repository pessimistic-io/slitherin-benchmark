// SPDX-License-Identifier: No license

pragma solidity 0.8.18;

/**
  * @title Interface for MTCToken
  * @notice Interface for Marketable Tax Credit implementation for Próspera ZEDE
  *
  * Próspera Tax Credit tokens (“PTC”s) are minted by the Roatán Financial Services Authority (“RFSA”)
  * on behalf of Próspera ZEDE as “MTC Tokens” pursuant to Section 3 of the Próspera Resolution
  * Authorizing MTC Tokens, §5-1-199-0-0-0-1. As such, PTCs are both utility tokens and Qualifying
  * Cryptocurrency in Próspera ZEDE. 
  * 
  * Please see the terms and conditions of use at https://www.rfsa.hn/tos
  */

import { IERC20Upgradeable } from "./ERC20Upgradeable.sol";

interface IMTCToken is IERC20Upgradeable {

    /****************************************************************
     *                           Errors                             
     ****************************************************************/

    /// The array is empty
    error EmptyArray();
    /// The `target` is an invalid address for requested operation
    error InvalidTarget();
    /// The caller does not have permission to burn tokens
    error NotBurner();
    /// The caller does not have permission to mint tokens
    error NotMinter();

    /****************************************************************
     *                           Events                             
     ****************************************************************/

    /// The `amount` has been burnt
    event Burnt(uint256 indexed amount);
    /// The `minter`s priviliges have been revoked
    event MinterRemoved(address indexed minter);
    /// The burner address has been changed
    event NewBurner(address indexed newBurner);
    /// The `burner`'s priviliges have been revoked
    event BurnerRemoved(address indexed burner);
    /// The minter address has been changed
    event NewMinter(address indexed newMinter);
    /// The `liquidityAccount` has been changed
    event NewLiquidityAccount(address indexed newLiquidityAccount);

    /****************************************************************
     *                   Inititialization Logic                     
     ****************************************************************/

    /// @notice Initializes the token contract
    /// @dev For the initial account setup we do not enforce separate accounts for admin purposes,
    /// @dev but it is enforced for all subsequent `minters`, `burners`, `blacklisters` and `Owners`
    /// @param initialMinter The address of the account allowed to `mint` new tokens
    /// @param initialBurner The address of the account allowed to `burn` tokens held by `liquidityAccount`
    /// @param initialBlacklister The address of the account allowed to `blacklist` other accounts
    /// @param liquidityAccount The address of the account from which the organization may burn tokens
    function initialize(
        address initialMinter,
        address initialBurner,
        address initialBlacklister,
        address liquidityAccount
    ) external;

    /****************************************************************
     *                     Business Logic                           
     ****************************************************************/

    /// @notice Mints new tokens
    /// @param to The address that will receive the new tokens
    /// @param amount The amount of tokens `to` will receive
    function mint(address to, uint256 amount) external;

    /// @notice Blacklist's a `target` account
    /// @dev For AML compliance the MTC Issuer must be able to blacklist accounts engaged in high-risk activities
    /// @dev Blacklisted accounts cannot `transfer` or `receive` tokens
    /// @dev To prevent gas waste, does not revert on invalid target
    /// Note: Blacklisting can be revoked
    /// @param targets The array of addresses to be blacklisted
    function blacklistAccounts(address[] calldata targets) external;

    /// @notice Revokes an account's blacklisted status
    /// @dev Business logic requires that accounts that are cleared after investigation be allowed to `send` and `receive` tokens again
    /// @param targets The accounts that should be removed from `blacklist`
    function revokeBlacklistings(address[] calldata targets) external;

    /// @notice Burns MTC Tokens
    /// @dev Business logic requires that `MTCs` are burnable once used
    /// @dev The tax-receiver can `burn` tokens it has received from tax-payers
    /// @param amount The amount of tokens to be burnt
    function burn(uint256 amount) external;

    /****************************************************************
     *                    Setter Functions                          
     ****************************************************************/

    /// @notice Sets the `minter` account to `newMinter` address
    /// @param newMinter The address of the new `minter`
    function setMinter(address newMinter) external;

    /// @notice Revokes the `minter`'s minting role
    /// @param minter The address of the `minter` to be removed
    function removeMinter(address minter) external;

    /// @notice Sets the `burner` account to `newBurner` address
    /// @param newBurner The address of the new `minter`
    function setBurner(address newBurner) external;

    /// @notice Revokes the `minter`'s minting role
    /// @param burner The address of the `minter` to be removed
    function removeBurner(address burner) external;

    /// @notice Sets the `blacklister` account to `newBlacklister` address
    /// @param newBlacklister The address of the new `minter`
    function setBlacklister(address newBlacklister) external;

    /// @notice `Sets the `liquidityAccount` address
    /// @dev Must `approve` token address for `balanceOf(liquidityAccount)` prior to call
    /// @param newWallet The address of the new `liquidityAccount`
    function setNewLiquidityAccount(address newWallet) external;

    /****************************************************************
     *                    Getter Functions                          
     ****************************************************************/

    /**
     * @notice Check if a `target` is the burner account
     */
    function checkBurner(address target) external view returns (bool);

    /**
     * @notice Check if a `target` is the minter account
     */
    function checkMinter(address target) external view returns (bool);

}
