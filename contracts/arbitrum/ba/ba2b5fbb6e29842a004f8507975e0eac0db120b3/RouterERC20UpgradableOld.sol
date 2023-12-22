// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./AddressUpgradeable.sol";

import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

contract RouterERC20UpgradableToken is
    Initializable,
    ContextUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable
{
    using AddressUpgradeable for address;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint8 private _decimals;

    // Upgradable Functions

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external initializer {
        __RouterERC20Upgradable_init(name_, symbol_, decimals_);
    }

    /// @dev Sets the values for {name} and {symbol}.
    ///
    /// The default value of {decimals} is 18. To select a different value for
    /// {decimals} you should overload it.
    ///
    /// All two of these values are immutable: they can only be set once during
    /// construction.
    function __RouterERC20Upgradable_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal initializer {
        __Context_init_unchained();
        __AccessControl_init();
        __Pausable_init();
        __ERC20_init_unchained(name_, symbol_);
        __RouterERC20Upgradable_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setDecimals(decimals_);

        // _setupRole(MINTER_ROLE, _msgSender());
        // _setupRole(BURNER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    function __RouterERC20Upgradable_init_unchained() internal initializer {}


    // Upgradable Functions

    //Core Contract Functions

    /// @notice Used to set decimals
    /// @param decimal Value of decimal
    function _setDecimals(uint8 decimal) internal virtual {
        _decimals = decimal;
    }

    /// @notice Fetches decimals
    /// @return Returns Value of decimals that is set
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /// @notice Used to pause the token
    /// @notice Only callable by an address that has Pauser Role
    /// @return Returns true when paused
    function pauseToken() public virtual onlyRole(PAUSER_ROLE) returns (bool) {
        _pause();
        return true;
    }

    /// @notice Used to unpause the token
    /// @notice Only callable by an address that has Pauser Role
    /// @return Returns true when unpaused
    function unpauseToken() public virtual onlyRole(PAUSER_ROLE) returns (bool) {
        _unpause();
        return true;
    }

    /// @notice Mints `_value` amount of tokens to address `_to`
    /// @notice Only callable by an address that has Minter Role.
    /// @param _to Recipient address
    /// @param _value Amount of tokens to be minted to `_to`
    /// @return Returns true if minted succesfully
    function mint(address _to, uint256 _value) public virtual whenNotPaused onlyRole(MINTER_ROLE) returns (bool) {
        _mint(_to, _value);
        return true;
    }

    /// @notice Destroys `_value` amount of tokens from `_from` account
    /// @notice Only callable by an address that has Burner Role.
    /// @param _from Address whose tokens are to be destroyed
    /// @param _value Amount of tokens to be destroyed
    /// @return Returns true if burnt succesfully
    function burn(address _from, uint256 _value) public virtual whenNotPaused onlyRole(BURNER_ROLE) returns (bool) {
        _burn(_from, _value);
        return true;
    }

    /// @dev See {ERC20-_beforeTokenTransfer}.
    ///
    /// Requirements:
    ///
    /// - the contract must not be paused.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), "ERC20Pausable: token transfer while paused");
    }
    //Core Contract Functions
}

