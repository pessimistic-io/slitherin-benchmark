// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved

pragma solidity 0.8.9;

import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable2Step.sol";
import "./AccessControl.sol";

contract XDCAToken is ERC20Burnable, ERC20Permit, Ownable2Step, AccessControl {
    bytes32 public constant MINTER = keccak256("MINTER");

    constructor() ERC20("xAutoDCA", "xDCA") ERC20Permit("xAutoDCA") {}

    function grantMinter(address to) public onlyOwner {
        _grantRole(MINTER, to);
    }

    function revokeMinter(address to) public onlyOwner {
        _revokeRole(MINTER, to);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER) {
        _mint(to, amount);
    }
}

