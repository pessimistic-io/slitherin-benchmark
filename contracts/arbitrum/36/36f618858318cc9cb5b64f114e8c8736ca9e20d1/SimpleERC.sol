// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "./ERC20.sol";

contract SimpleERC is ERC20 {
    constructor() ERC20("MetaMusk", "MMUSK") {
        _mint(msg.sender, 80085000000 * 10 ** decimals());
    }
}
