// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "./Ownable.sol";

abstract contract MsgBusAddr is Ownable {
    address public msgBus;

    function setMsgBus(address _addr) public onlyOwner {
        msgBus = _addr;
    }
}

