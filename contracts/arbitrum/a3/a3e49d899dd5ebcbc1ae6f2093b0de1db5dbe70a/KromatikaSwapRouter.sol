// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

import "./Multicall.sol";

contract KromatikaSwapRouter is Multicall {

    mapping(string => address) internal swapAggregators;

    event SwapExecuted(address owner, string aggregatorId, bytes result);

    constructor(string[] memory _aggregators, address[] memory _addresses) {

        require(_aggregators.length == _addresses.length, "KSR_LN");
        for (uint256 i = 0; i < _aggregators.length; i++) {
            swapAggregators[_aggregators[i]] = _addresses[i];
        }
    }

    function executeSwap(
        string calldata aggregatorId,
        uint256 deadline,
        bytes calldata data
    ) external payable checkDeadline(deadline) returns (bool success, bytes memory result) {

        address targetAddress = swapAggregators[aggregatorId];
        require(targetAddress != address(0), "KSR_NF");

        (success, result) = targetAddress.call{value: msg.value}(data);

        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (result.length < 68) revert();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
        emit SwapExecuted(msg.sender, aggregatorId, result);
    }

    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, 'KSR_OLD');
        _;
    }
}
