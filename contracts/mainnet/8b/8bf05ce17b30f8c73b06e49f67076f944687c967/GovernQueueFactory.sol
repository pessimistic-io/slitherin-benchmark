/*
 * SPDX-License-Identifier:    GPL-3.0
 */

pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "./GovernQueue.sol";
import "./ERC1167ProxyFactory.sol";

contract GovernQueueFactory {
    using ERC1167ProxyFactory for address;

    address public base;

    constructor() public {
        setupBase();
    }

    function newQueue(address _aclRoot, ERC3000Data.Config memory _config, bytes32 _salt) public returns (GovernQueue queue) {
        if (_salt != bytes32(0)) {
            return GovernQueue(base.clone2(_salt, abi.encodeWithSelector(queue.initialize.selector, _aclRoot, _config)));
        } else {
            return new GovernQueue(_aclRoot, _config);
        }
    }

    function setupBase() private {
        ERC3000Data.Collateral memory noCollateral;
        ERC3000Data.Config memory config = ERC3000Data.Config(
            3600,  // how many seconds to wait before being able to call `execute`
            noCollateral,
            noCollateral,
            address(0),
            "",
            100000 // initial maxCalldatasize
        );
        base = address(new GovernQueue(address(2), config));
    }
}

