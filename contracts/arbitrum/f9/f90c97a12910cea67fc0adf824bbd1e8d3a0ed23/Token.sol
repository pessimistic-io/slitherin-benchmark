// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.20;

import {RebasingToken} from "./RebasingToken.sol";
import {Allowlist} from "./Allowlist.sol";
import {Owned} from "./Owned.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

/// @title Token contract extending RebasingToken and Owned.
/// @custom:oz-upgrades
contract Token is UUPSUpgradeable, RebasingToken, OwnableUpgradeable {
    Allowlist public allowlist;
    bool public paused;

    event SetAllowlist(address indexed allowlist);
    event SetName(string name, string symbol);
    event Pause();
    event UnPause();

    error Paused();
    error NotAllowed();

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier onlyAllowed(address account) {
        if (!canTransact(account)) revert NotAllowed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        Allowlist _allowlist,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _owner
    ) initializer public {
        __RebasingToken_init_(_name, _symbol, _decimals);
        __Ownable_init(_owner);
        allowlist = _allowlist;
        emit SetAllowlist(address(_allowlist));
        emit SetName(_name, _symbol);
    }

    /// @notice Implementation of the UUPS proxy authorization.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Checks if an address is allowed to transact.
    /// @param account The address to check.
    /// @return True if the address is allowed, false otherwise.
    function canTransact(address account) public view returns (bool) {
        return allowlist.canTransact(account);
    }

    /// @notice Sets the name and symbol of the token.
    /// @param _name The new name of the token.
    /// @param _symbol The new symbol of the token.
    function setName(string memory _name, string memory _symbol) external onlyOwner {
        name = _name;
        symbol = _symbol;
        emit SetName(_name, _symbol);
    }

    /// @notice Sets the Allowlist contract for the token.
    /// @param _allowlist The new Allowlist contract.
    function setAllowlist(Allowlist _allowlist) external onlyOwner {
        allowlist = _allowlist;
        emit SetAllowlist(address(_allowlist));
    }

    /// @notice Pauses all token transfers.
    function pause() external onlyOwner {
        paused = true;
        emit Pause();
    }

    /// @notice Unpauses all token transfers.
    function unpause() external onlyOwner {
        paused = false;
        emit UnPause();
    }

    /// @notice Sets the parameters for a rebase.
    /// @param change The change rate for the rebase.
    /// @param startTime The start time for the rebase.
    /// @param endTime The end time for the rebase.
    function setRebase(uint32 change, uint32 startTime, uint32 endTime) external onlyOwner {
        _setRebase(change, startTime, endTime);
    }

    /// @notice Mints tokens to an address.
    /// @param to The address to mint tokens to.
    /// @param amount The amount of tokens to mint.
    /// @return sharesMinted The number of shares minted.
    function mint(address to, uint256 amount) external onlyOwner onlyAllowed(to) returns (uint256 sharesMinted) {
        return _mint(to, amount);
    }

    /// @notice Burns tokens from an account.
    /// @param account The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    /// @return sharesBurned The number of shares burned.
    function burn(address account, uint256 amount) external onlyOwner returns (uint256 sharesBurned) {
        return _burn(account, amount);
    }

    /// @notice Burns tokens from the caller.
    /// @param amount The amount of tokens to burn.
    /// @return sharesBurned The number of shares burned.
    function burn(uint256 amount) external returns (uint256 sharesBurned) {
        return _burn(msg.sender, amount);
    }

    /// @dev Internal function to handle token transfers, overriding the base implementation.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param amount The amount to transfer.
    function _transfer(address from, address to, uint256 amount) internal virtual override whenNotPaused onlyAllowed(from) onlyAllowed(to) {
        super._transfer(from, to, amount);
    }
}

