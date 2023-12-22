// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Owned} from "./Owned.sol";
import {ERC20} from "./ERC20.sol";

/// @title Big Dick Bull (BDB)
/// @notice Token is a standard ERC20

contract BDB is ERC20, Owned {
    constructor() ERC20("Big Dick Bull", "BDB", 18) Owned(msg.sender) {}

    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function renounceOwnership() public virtual onlyOwner {
        transferOwnership(address(0));
    }
}

