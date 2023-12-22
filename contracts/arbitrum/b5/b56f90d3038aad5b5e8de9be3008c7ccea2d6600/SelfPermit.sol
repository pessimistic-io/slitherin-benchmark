// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Permit2.sol";
import "./IERC20PermitAllowed.sol";

abstract contract SelfPermit {
    function selfPermit(address token, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) public payable {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function selfPermit2(address token, uint value, uint deadline, bytes calldata signature) public payable {
        IERC20Permit2(token).permit2(msg.sender, address(this), value, deadline, signature);
    }
}

