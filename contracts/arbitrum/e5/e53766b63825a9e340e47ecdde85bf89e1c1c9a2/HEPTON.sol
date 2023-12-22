// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Context.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./ERC20.sol";
import "./console.sol";

contract HEPTON is ERC20, Ownable {
    
    uint256 private immutable _cap;
    mapping(address => bool) public Blacklist;

    constructor(uint256 cap_) ERC20("HEPTON", "HTE") {
        require(cap_ > 0, "ERC20Capped: cap is 0");
        _cap = cap_;
    }

    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function _mint(address account, uint256 amount) internal virtual override {
        require(ERC20.totalSupply() + amount <= cap(), "ERC20Capped: cap exceeded");
        super._mint(account, amount);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        super._beforeTokenTransfer(from, to, amount);
        require(!Blacklist[from], "HEPTON: You are banned from Transfer");
    }

    function BlacklistAddress(address actor) public onlyOwner {
        Blacklist[actor] = true;
    }

    function UnBlacklistAddress(address actor) public onlyOwner {
        Blacklist[actor] = false;
    }
}
