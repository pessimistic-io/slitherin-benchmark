// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.19;

import {RebasingToken} from "./RebasingToken.sol";
import {Whitelist} from "./Whitelist.sol";
import {Owned} from "./Owned.sol";

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

    function isWhitelisted(address account) public view returns (bool) {
        return whitelist.isWhitelisted(account);
    }

    function setName(string memory _name, string memory _symbol) external onlyOwner {
        name = _name;
        symbol = _symbol;
        emit SetName(_name, _symbol);
    }

    function setWhitelist(Whitelist _whitelist) external onlyOwner {
        whitelist = _whitelist;
        emit SetWhitelist(address(_whitelist));
    }

    function pause() external onlyOwner {
        paused = true;
        emit Pause();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit UnPause();
    }

    function setRebase(uint32 change, uint32 startTime, uint32 endTime) external override onlyOwner {
        _setRebase(change, startTime, endTime);
    }

    function mint(address to, uint256 amount) external onlyOwner onlyWhitelisted(to) returns (uint256 sharesMinted) {
        return _mint(to, amount);
    }

    function burn(address user, uint256 amount) external onlyOwner returns (uint256 sharesBurned) {
        return _burn(user, amount);
    }

    function burn(uint256 amount) external returns (uint256 sharesBurned) {
        return _burn(msg.sender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override whenNotPaused onlyWhitelisted(to) {
        super._transfer(from, to, amount);
    }
}

