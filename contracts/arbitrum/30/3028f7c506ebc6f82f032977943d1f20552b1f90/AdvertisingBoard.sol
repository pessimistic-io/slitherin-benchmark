// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOpsProxyFactory} from "./IOpsProxyFactory.sol";

contract AdvertisingBoard {
    IOpsProxyFactory public constant opsProxyFactory =
        IOpsProxyFactory(0x370BC2D643637F4eC19F6cbA5244c8EA6146a6D9);

    mapping(address => string) public messages;

    function postMessage(string calldata _message) external {
        messages[msg.sender] = _message;
    }

    function viewMessage(address _eoa) external view returns (string memory) {
        (address dedicatedMsgSender, ) = opsProxyFactory.getProxyOf(_eoa);

        return messages[dedicatedMsgSender];
    }
}

