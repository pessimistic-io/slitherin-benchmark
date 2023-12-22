// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract BdsmToken is ERC20, Ownable {
    constructor(
        uint256 initialSupply
    ) ERC20("BDSM Token - buy only on your own risk (v1)", "BDSMv1") {
        _mint(msg.sender, initialSupply);
    }

    function safetyEthWithdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}

