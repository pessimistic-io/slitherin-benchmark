// SPDX-License-Identifier: UNLICENSED



pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";

contract Wow is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    
    bool public mintingActive;
    bool public originBalanceRequired = true;

    mapping(address => bool) public minters;
    mapping(address => bool) public blacklist;
    
    constructor() ERC20("Wow", "WOW") ERC20Permit("Wow") {}

    function flipMinter(address _minter) external onlyOwner {
        minters[_minter] = !minters[_minter];
    }

    function flipBlacklist(address _blacklist) external onlyOwner {
        blacklist[_blacklist] = !blacklist[_blacklist];
    }

    function flipMintingActive() external onlyOwner {
        mintingActive = !mintingActive;
    }

    function flipOriginBalanceRequired() external onlyOwner {
        originBalanceRequired = !originBalanceRequired;
    }

    function mint(address to, uint256 amount) external {
        require(mintingActive, "Minting is not active.");
        require(minters[msg.sender], "Only permissioned addresses can mint.");
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
    internal override(ERC20) {
        require(!blacklist[from] && !blacklist[to], "Blacklisted!");
        if(from != address(0) && originBalanceRequired){
            require(balanceOf(tx.origin) > 0, "Transaction origin must have a balance.");
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}
