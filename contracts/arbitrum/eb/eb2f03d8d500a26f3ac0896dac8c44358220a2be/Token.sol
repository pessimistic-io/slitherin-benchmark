// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.19;

import {RebasingERC20Permit} from "./RebasingERC20Permit.sol";
import {Whitelist} from "./Whitelist.sol";
import {Owned} from "./Owned.sol";

contract Token is RebasingERC20Permit, Owned {
    Whitelist public immutable whitelist;

    bool public paused = true;

    error Paused();
    error NotWhitelisted();

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier isWhitelisted(address account) {
        if (!whitelist.isWhitelisted(account)) revert NotWhitelisted();
        _;
    }

    constructor(Whitelist _whitelist)
        RebasingERC20Permit("XYZ", "XYZ", 6)
        Owned(msg.sender)
    {
        whitelist = _whitelist;
    }

    // Owner actions.

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function setRebase(uint32 change, uint32 startTime, uint32 endTime) external onlyOwner {
        _setRebase(change, startTime, endTime);
    }

    function mint(address to, uint256 amount) external onlyOwner isWhitelisted(to) {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override whenNotPaused isWhitelisted(to) {
        super._transfer(from, to, amount);
    }
}

