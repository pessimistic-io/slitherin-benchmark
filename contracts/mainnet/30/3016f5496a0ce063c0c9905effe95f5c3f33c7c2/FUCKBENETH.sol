// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./ERC20.sol";



////FUCKBENETH.sol

contract FUCKBENETH is ERC20{
    constructor(address _to) ERC20("FUCKBEN.ETH", "FUCKBEN.ETH") {
        _mint(_to, 420000000000000 * 10 ** decimals());
    }

}
