// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
import "./AccessControl.sol";
import "./ERC20Burnable.sol";

contract DINO_PRE is AccessControl, ERC20Burnable {
    constructor() ERC20("DINO_PRE", "DINO_PRE") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _mint(msg.sender, 150000 * 1e18);
    }
}
