/**
 * Access Control (whitelisting, admins, mods) used by the vault contract.
 * Note only relevent for private vaults!
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Schema.sol";

contract AccessControl {
    // ===================
    //      ABSTRACTS
    // ===================
    /**
     * @dev The address of the Yieldchain diamond contract
     */
    address public immutable YC_DIAMOND;

    /**
     * @dev The address of the creator of this strategy
     */
    address public immutable CREATOR;

    constructor(address creator, address diamond) {
        CREATOR = creator;
        YC_DIAMOND = diamond;
    }

    // ===================
    //      STORAGE
    // ===================
    /**
     * @dev
     * Tracking whether the strategy is private or not,
     * this is not immutable since we would allow to change it from the diamond (deploying) contract,
     * if permmited.
     */
    bool public isPublic;

    /**
     * @dev
     * Keeping track of whitelisted users that are allowed to use this vault
     * @notice This is only relevent for private vaults - In public vaults, everyone is allowed in.
     */
    mapping(address => bool) public whitelistedUsers;

    /**
     * @dev
     * Keeping track of all of the admins of the vault,
     * that can whitelist/blacklist users from using it,
     * also only relevent for private vaults
     */
    mapping(address => bool) public mods;

    /**
     * @dev
     * Keeping track of all of the administrators of the vault,
     * Adminstrators have mods permissions but can also add/remove other mods,
     * also only relevent for private vaults
     */
    mapping(address => bool) public admins;

    // ===================
    //      MODIFIERS
    // ===================
    /**
     * Requires the msg.sender to be the Yieldchain dimaond
     */
    modifier onlyDiamond() {
        require(msg.sender == YC_DIAMOND, "You Are Not Yieldchain Diamond");
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "Only self");
        _;
    }

    /**
     * Requires the msg.sender to be the vault's creator
     */
    modifier onlyCreator() {
        require(msg.sender == CREATOR, "You Are Not Vault Creator");
        _;
    }

    /**
     * Requires the msg.sender to be a moderator of this vault
     */
    modifier onlyMods() {
        require(mods[msg.sender], "You Are Not A Mod");
        _;
    }
    /**
     * Requires the msg.sender to be an admin of this vault
     */
    modifier onlyAdmins() {
        require(admins[msg.sender], "You Are Not An Admin");
        _;
    }

    /**
     * Requires an inputted address to not be another moderator
     * @notice We do allow it if msg.sender is an administrator (higher role)
     */
    modifier peaceAmongstMods(address otherMod) {
        require(
            !mods[otherMod] || (admins[msg.sender] && !admins[otherMod]),
            "Mods Cannot Betray Mods"
        );
        _;
    }

    /**
     * Requires an inputted address to not be another adminstrator
     */
    modifier peaceAmongstAdmins(address otherAdmin) {
        require(
            admins[msg.sender] && !admins[otherAdmin],
            "Admins Cannot Betray Admins"
        );
        _;
    }

    /**
     * Requires the msg.sender to either be whitelisted, or the vault be public
     */
    modifier onlyWhitelistedOrPublicVault() {
        require(
            isPublic || whitelistedUsers[msg.sender],
            "You Are Not Whitelisted"
        );
        _;
    }

    // ===================
    //      FUNCTIONS
    // ===================
    /**
     * @dev
     * changePrivacy()
     * Changes the privacy of this vault.
     * @notice ONLY callable by the Diamond. This is in order to enforce some rules logic, like:
     * 1) A public vault cannot be changed to private in most cases
     * 2) Vaults can only be private for premium users,
     * etc.
     *
     * The logic may change in the future
     *
     * @param shouldBePublic - true: Public, false: private.
     */
    function changePrivacy(bool shouldBePublic) external onlyDiamond {
        isPublic = shouldBePublic;
    }

    /**
     * @dev
     * Whitelist an address
     * @param userAddress - The address to whitelist
     */
    function whitelist(address userAddress) external onlyMods {
        whitelistedUsers[userAddress] = true;
    }

    /**
     * @dev
     * Blacklist an address
     * @param userAddress - The address to whitelist
     */
    function blacklist(
        address userAddress
    ) external onlyMods peaceAmongstMods(userAddress) {
        whitelistedUsers[userAddress] = false;
    }

    /**
     * @dev
     * Add a moderator
     */
    function addModerator(address userAddress) external onlyAdmins {
        mods[userAddress] = true;
        whitelistedUsers[userAddress] = true;
    }

    /**
     * @dev
     * Remove a moderator
     */
    function removeModerator(
        address userAddress
    ) external onlyAdmins peaceAmongstAdmins(userAddress) {
        mods[userAddress] = false;
    }

    /**
     * @dev
     * Add an administrator
     */
    function addAdministrator(address userAddress) external onlyCreator {
        mods[userAddress] = true;
        admins[userAddress] = true;
        whitelistedUsers[userAddress] = true;
    }

    /**
     * @dev
     * Remove an administrator
     */
    function removeAdministrator(address userAddress) external onlyCreator {
        admins[userAddress] = false;
        mods[userAddress] = false;
    }
}

