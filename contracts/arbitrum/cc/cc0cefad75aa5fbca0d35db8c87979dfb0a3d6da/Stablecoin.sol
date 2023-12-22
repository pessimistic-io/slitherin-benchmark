// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ContextUpgradeable} from "./ContextUpgradeable.sol";
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "./ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "./ERC20PermitUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {ERC20BlacklistableUpgradable} from "./ERC20BlacklistableUpgradable.sol";
import {ExtendedAccessControlUpgradeable} from "./ExtendedAccessControlUpgradeable.sol";

contract Stablecoin is
    Initializable, // Used for contract initialization purposes.
    ContextUpgradeable, // Provides basic functionality from the Context contract.
    ERC20Upgradeable, // Represents an upgradeable ERC20 token.
    ERC20PausableUpgradeable, // Provides functionality to pause and unpause the contract.
    ExtendedAccessControlUpgradeable, // Manages access roles for the contract.
    ERC20PermitUpgradeable, // ERC20 token with a permit function (off-chain approval).
    ERC20BlacklistableUpgradable // Allows certain addresses to be blacklisted.
{
    // Define constants for various roles using the keccak256 hash of the role names.
    bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with default settings and roles.
     * @param _admin The address to be granted initial roles.
     */
    function initialize(address _admin) public initializer {
        string memory name = "Forte AUD";
        __ERC20_init(name, "AUDF");
        __Pausable_init();
        __ExtendedAccessControl_init();
        __ERC20Permit_init(name);
        __ERC20Blacklistable_init();
        _addRole(BLACKLIST_ROLE);
        _addRole(BURN_ROLE);
        _addRole(MINT_ROLE);
        _addRole(PAUSE_ROLE);
        _grantRoles(_admin);
    }

    /**
     * @dev Returns the number of decimals the token uses.
     * @return uint8 Number of decimals.
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /**
     * @dev Pauses all token transfers.
     * Can only be called by an account with the PAUSE_ROLE.
     */
    function pause() public onlyRole(PAUSE_ROLE) {
        _pause();
    }

    /**
     * @dev Resumes all token transfers.
     * Can only be called by an account with the PAUSE_ROLE.
     */
    function unpause() public onlyRole(PAUSE_ROLE) {
        _unpause();
    }

    /**
     * @dev Blacklists an account, preventing it from participating in token transfers.
     * Can only be called by an account with the BLACKLIST_ROLE.
     * @param _account Address to be blacklisted.
     */
    function blacklist(address _account) public onlyRole(BLACKLIST_ROLE) {
        _blacklist(_account);
    }

    /**
     * @dev Removes an account from the blacklist.
     * Can only be called by an account with the BLACKLIST_ROLE.
     * @param _account Address to be removed from the blacklist.
     */
    function unBlacklist(address _account) public onlyRole(BLACKLIST_ROLE) {
        _unBlacklist(_account);
    }

    /**
     * @dev Mints tokens to the caller's address.
     * Can only be called by an account with the MINT_ROLE.
     * @param _amount Amount of tokens to mint.
     */
    function mint(uint256 _amount) public onlyRole(MINT_ROLE) {
        _mint(_msgSender(), _amount);
    }

    /**
     * @dev Mints tokens to a specified address.
     * Can only be called by an account with the MINT_ROLE.
     * @param _account Address to mint token tos.
     * @param _amount Amount of tokens to mint.
     */
    function mint(address _account, uint256 _amount) public onlyRole(MINT_ROLE) {
        _mint(_account, _amount);
    }

    /**
     * @dev Burns tokens from the caller's address.
     * Can only be called by an account with the BURN_ROLE.
     * @param _amount Amount of tokens to burn.
     */
    function burn(uint256 _amount) public onlyRole(BURN_ROLE) {
        _burn(_msgSender(), _amount);
    }

    /**
     * @dev Burns tokens from a specified address, assuming they have the required allowance.
     * Can only be called by an account with the BURN_ROLE.
     * @param _account Address to burn tokens from.
     * @param _amount Amount of tokens to burn.
     */
    function burn(address _account, uint256 _amount) public onlyRole(BURN_ROLE) {
        _spendAllowance(_account, _msgSender(), _amount);
        _burn(_account, _amount);
    }

    // The following functions are overrides required by Solidity.
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20BlacklistableUpgradable) {
        super._update(from, to, value);
    }
}

