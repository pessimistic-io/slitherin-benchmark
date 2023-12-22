// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";

interface ITokenStaking {
    function mintAndAllocate(uint256 index, uint256 amount, address to) external;
}

contract VesterPluginXrdo {
    ITokenStaking public xrdo;

    constructor(address _xrdo) {
        xrdo = ITokenStaking(_xrdo);
    }

    function onClaim(address from, uint256, address token, uint256 amount) external {
       IERC20(token).approve(address(xrdo), amount);
       xrdo.mintAndAllocate(0, amount, from);
    }
}

