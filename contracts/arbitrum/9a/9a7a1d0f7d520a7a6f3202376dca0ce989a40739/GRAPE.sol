// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";

contract GRAPE_Token is ERC20 {
    constructor() ERC20('GRAPE', 'GRAPE'){
        _mint(0xcA8487024bf39EE9c26B89e23AFFd6122F06659e, 10000000000 ether);
    }
}

