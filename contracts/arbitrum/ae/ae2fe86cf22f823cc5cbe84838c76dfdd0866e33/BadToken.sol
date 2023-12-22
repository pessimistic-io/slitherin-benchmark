// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract BadToken is ERC20 {

    address bulkSender;
    constructor(address _bulkSender) ERC20("Bad Token", "BT") {
        bulkSender = _bulkSender;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if(msg.sender == bulkSender) {
            revert("Bad Token");
        }
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return 10000 ether;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}
