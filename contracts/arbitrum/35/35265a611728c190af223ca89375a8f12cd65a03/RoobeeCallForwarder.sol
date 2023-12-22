/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./IRoobeeMulticall.sol";

contract RoobeeCallForwarder {

    IRoobeeMulticall public multicall;

    constructor(address multicall_) {
        multicall = IRoobeeMulticall(multicall_);
    }

    function payAndExecute(
        address payToken,
        uint256 payAmount,
        address[] calldata addresses,
        bytes[] calldata datas,
        uint256[] calldata values
    ) external payable {

        IERC20(payToken).transferFrom(msg.sender, address(multicall), payAmount);

        multicall.makeCalls{value: msg.value}(addresses, datas, values);
    }
}
