// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
//import openzepplin ERC20
import "./ERC20.sol";

contract YURI is ERC20 {
    constructor() ERC20('Yuri', 'Yuri'){
        _mint(msg.sender, 500000000000000 ether);
    }
}

