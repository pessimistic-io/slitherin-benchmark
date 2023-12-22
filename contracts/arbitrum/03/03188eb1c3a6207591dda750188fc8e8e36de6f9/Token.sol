// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.19;

import {RebasingToken} from "./RebasingToken.sol";
import {Whitelist} from "./Whitelist.sol";
import {Owned} from "./Owned.sol";

/// @title Token contract extending RebasingToken and Owned.
/// @notice This contract adds pausing, whitelisting and ownership functionalities to RebasingToken.
contract Token is RebasingToken, Owned {
    Whitelist public whitelist;
    bool public paused;

    event SetName(string name, string symbol);
    event SetWhitelist(address indexed whitelist);
    event Pause();
    event UnPause();

    error Paused();
    error NotWhitelisted();

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier onlyWhitelisted(address account) {
        if (!isWhitelisted(account)) revert NotWhitelisted();
        _;
    }

    constructor(Whitelist _whitelist, string memory name, string memory symbol, uint8 decimals)
        RebasingToken(name, symbol, decimals)
        Owned(msg.sender)
    {
        whitelist = _whitelist;
        emit SetName(name, symbol);
        emit SetWhitelist(address(_whitelist));
    }

    /// @notice Checks if an address is whitelisted.
    /// @param account The address to check.
    /// @return True if the address is whitelisted, false otherwise.
    function isWhitelisted(address account) public view returns (bool) {
        return whitelist.isWhitelisted(account);
    }

    /// @notice Sets the name and symbol of the token.
    /// @param _name The new name of the token.
    /// @param _symbol The new symbol of the token.
    function setName(string memory _name, string memory _symbol) external onlyOwner {
        name = _name;
        symbol = _symbol;
        emit SetName(_name, _symbol);
    }

    /// @notice Sets the Whitelist contract for the token.
    /// @param _whitelist The new Whitelist contract.
    function setWhitelist(Whitelist _whitelist) external onlyOwner {
        whitelist = _whitelist;
        emit SetWhitelist(address(_whitelist));
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

    /// @notice Mints tokens to a whitelisted address.
    /// @param to The address to mint tokens to.
    /// @param amount The amount of tokens to mint.
    /// @return sharesMinted The number of shares minted.
    function mint(address to, uint256 amount) external onlyOwner onlyWhitelisted(to) returns (uint256 sharesMinted) {
        return _mint(to, amount);
    }

    /// @notice Burns tokens from a user.
    /// @param user The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    /// @return sharesBurned The number of shares burned.
    function burn(address user, uint256 amount) external onlyOwner returns (uint256 sharesBurned) {
        return _burn(user, amount);
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
    function _transfer(address from, address to, uint256 amount) internal override whenNotPaused onlyWhitelisted(to) {
        super._transfer(from, to, amount);
    }
}

