// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.19;

import {RebasingERC20Permit} from "./RebasingERC20Permit.sol";
import {Whitelist} from "./Whitelist.sol";
import {OFT} from "./OFT.sol";

contract Token is OFT, RebasingERC20Permit {
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

    constructor(Whitelist _whitelist, address _lzEndpoint)
        OFT(_lzEndpoint)
        RebasingERC20Permit("XYZ", "XYZ", 6)
    {
        whitelist = _whitelist;
    }

    function circulatingSupply() public view override returns (uint) {
        return totalSupply();
    }

    function _debitFrom(address _from, uint16, bytes memory, uint256 _amount) internal virtual override returns(uint256) {
        address spender = msg.sender;
        if (_from != spender) _decreaseAllowance(_from, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(uint16, address _toAddress, uint256 _amount) internal override returns(uint256) {
        _mint(_toAddress, _amount);
        return _amount;
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

