// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Ownable.sol";

contract ZapV2 is Ownable {
    mapping(address => bool) private adaptersWhiteList;
    error NOT_VALID_ADAPTER();
    error DELEGATE_CALL_FAILED();

    event Executed(address indexed target, bytes data, bytes returnData);

    constructor() Ownable(msg.sender) {}

    function registerAdapter(address[] memory _adapters) external onlyOwner {
        for (uint i = 0; i < _adapters.length; i++) {
            adaptersWhiteList[_adapters[i]] = true;
        }
    }

    function executeBatch(address[] calldata adapters, bytes[] calldata paramsList) external {
        if (adapters.length != paramsList.length) revert DELEGATE_CALL_FAILED();
        for (uint i = 0; i < adapters.length; i++) {
            if (!adaptersWhiteList[adapters[i]]) revert NOT_VALID_ADAPTER();
            (bool success, bytes memory returnData) = adapters[i].delegatecall(paramsList[i]);
            emit Executed(adapters[i], paramsList[i], returnData);
            if (!success) revert DELEGATE_CALL_FAILED();
        }
    }
}

