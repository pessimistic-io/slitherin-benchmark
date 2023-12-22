// SPDX-License-Identifier: MIT

/*
    twitter: https://twitter.com/arbvmpx
*/

pragma solidity ^0.8.10;

import "./ERC20.sol";
import "./ERC20Capped.sol";

contract ARBVMPX is ERC20("ARB VMPX", "ARB VMPX"), ERC20Capped(108_624_000 ether) {

    uint256 public counter;
    mapping(uint256 => bool) private _work;
    mapping(address => uint256) public _userMinted;
    uint256 public one = 2000 ether;

    function _doWork() internal {
        // cycles = mint count / 20 + 1
        uint256 cycles = totalSupply() / one / 20 + 1;

        for (uint i = 0; i < cycles; i++) {
            _work[++counter] = true;
        }
    }

    function _mint(address account, uint256 amount) internal override (ERC20, ERC20Capped) {
        super._mint(account, amount);
    }

    function mint() external {
        require(tx.origin == msg.sender, 'only EOAs allowed');
        require(totalSupply() + one <= cap(), "minting would exceed cap");
        require(_userMinted[msg.sender] < 10, "user max 10");
        _userMinted[msg.sender] += 1;
        _doWork();
        _mint(msg.sender, one);
    }

    receive() payable external {
        require(tx.origin == msg.sender, 'only EOAs allowed');
        require(totalSupply() + one <= cap(), "minting would exceed cap");
        require(_userMinted[msg.sender] < 10, "user max 10");
        _userMinted[msg.sender] += 1;
        _doWork();
        _mint(msg.sender, one);
    }
}

