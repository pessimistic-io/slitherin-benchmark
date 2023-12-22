// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";

contract Lily is ERC20, Ownable {
    address constant internal receiver = 0x7Bf95091a91676DbbDF402906497cdB389FaE4d7;
    address constant internal V3LP = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    uint256 public openTime;
    address[] public whitelist;

    constructor(uint256 _openTime) ERC20("Lily", "Lily") {
        _mint(receiver, 87000000*10**decimals());
        openTime = _openTime;
    }
    
    function setopenTime(uint256 _openTime) external onlyOwner {
        openTime = _openTime;
    }

    function setWhitelist(address[] memory _whitelist) external onlyOwner {
        whitelist = _whitelist;
    }

    function inWhitelist(address _addr) public view returns (bool) {
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == _addr) {
                return true;
            }
        }
        return false;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if(block.timestamp <= openTime) {
            if(msg.sender == V3LP) {
                require(inWhitelist(tx.origin), "not in whitelist");
            }
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
}
