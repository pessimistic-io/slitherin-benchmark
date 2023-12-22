// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import {Proxied} from "./Proxied.sol";
import {Gelatofied} from "./Gelatofied.sol";

contract HelloWorld is Proxied, Gelatofied {
    uint256 public interval;
    uint256 public lastCallTime;

    event LogHelloWorld();

    // solhint-disable-next-line no-empty-blocks
    constructor(address payable _gelato) Gelatofied(_gelato) {}

    function setInterval(uint256 _interval) external onlyProxyAdmin {
        interval = _interval;
    }

    function helloWorld(uint256 _paymentAmount)
        external
        gelatofy(_paymentAmount, Gelatofied.ETH)
    {
        require(canExec(), "helloWorld: not canExec");
        lastCallTime = block.timestamp; // solhint-disable-line
        emit LogHelloWorld();
    }

    function canExec() public view returns (bool) {
        if (lastCallTime == 0) return true;
        return lastCallTime + interval <= block.timestamp; // solhint-disable-line
    }
}

