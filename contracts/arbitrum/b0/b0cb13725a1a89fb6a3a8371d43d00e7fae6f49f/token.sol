// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract MyToken is ERC20, Pausable, Ownable {
    mapping(address => bool) private _unrestrictedAddresses;

    constructor() ERC20("MyToken", "test") {
        _mint(msg.sender, 210000000000000 * 10 ** decimals());
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function addUnrestrictedAddress(address unrestrictedAddress) public onlyOwner {
        _unrestrictedAddresses[unrestrictedAddress] = true;
    }

    function removeUnrestrictedAddress(address unrestrictedAddress) public onlyOwner {
        _unrestrictedAddresses[unrestrictedAddress] = false;
    }

    function isUnrestrictedAddress(address addr) public view returns (bool) {
        return _unrestrictedAddresses[addr];
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPausedOrUnrestricted(from)
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    modifier whenNotPausedOrUnrestricted(address addr) {
        require(!paused() || isUnrestrictedAddress(addr), "ERC20Pausable: token transfer while paused");
        _;
    }

    function renounceOwnership() public override onlyOwner {
        transferOwnership(address(0));
    }
}

