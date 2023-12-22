//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IInsuredLongsStrategy} from "./IInsuredLongsStrategy.sol";

import {Ownable} from "./Ownable.sol";

contract CallbackForwarder is Ownable {
    struct CallbackParams {
        bytes32 key;
        bool isExecuted;
    }

    mapping(address => bool) public validCallbackCallers;
    mapping(uint256 => CallbackParams) public gmxPendingCallbacks;
    mapping(uint256 => uint256) public pendingIncreaseOrders;
    uint256 public gmxPendingCallbacksStartIndex;
    uint256 public gmxPendingCallbacksEndIndex;
    uint256 public pendingIncreaseOrdersStartIndex;
    uint256 public pendingIncreaseOrdersEndIndex;

    event ForwardGmxPositionCallback(bytes32 positionKey, bool isExecuted);
    event PendingCallbackCreated(bytes32 positionKey, bool isExecuted);
    event CreatedIncreaseOrder(uint256 _positionId);
    event ExecutedIncreaseOrder(uint256 _positionId);
    event CallbackCallerSet(address _caller, bool _set);

    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool
    ) external {
        require(validCallbackCallers[msg.sender], "Forbidden");
        gmxPendingCallbacks[gmxPendingCallbacksEndIndex] = CallbackParams(
            positionKey,
            isExecuted
        );
        unchecked {
            ++gmxPendingCallbacksEndIndex;
        }

        emit PendingCallbackCreated(positionKey, isExecuted);
    }

    function createIncreaseOrder(uint256 _positionId) external {
        require(validCallbackCallers[msg.sender], "Forbidden");
        pendingIncreaseOrders[pendingIncreaseOrdersEndIndex] = _positionId;
        unchecked {
            ++pendingIncreaseOrdersEndIndex;
        }
        emit CreatedIncreaseOrder(_positionId);
    }

    function forwardGmxPositionCallback(
        address _strategy,
        uint256 _startIndex,
        uint256 _endIndex
    ) external {
        require(validCallbackCallers[msg.sender], "Forbidden");

        CallbackParams memory params;
        while (_startIndex != _endIndex) {
            params = gmxPendingCallbacks[_startIndex];
            try
                IInsuredLongsStrategy(_strategy).gmxPositionCallback(
                    params.key,
                    params.isExecuted,
                    true
                )
            {} catch {}
            unchecked {
                ++_startIndex;
            }
            emit ForwardGmxPositionCallback(params.key, params.isExecuted);
        }

        gmxPendingCallbacksStartIndex = _startIndex;
    }

    function executeIncreaseOrders(
        address _strategy,
        uint256 _startIndex,
        uint256 _endIndex
    ) external payable {
        require(validCallbackCallers[msg.sender], "Forbidden");

        uint256 orders = _endIndex - _startIndex;

        uint256 positionId;
        while (_startIndex != _endIndex) {
            positionId = pendingIncreaseOrders[_startIndex];
            try
                IInsuredLongsStrategy(_strategy)
                    .createIncreaseManagedPositionOrder{
                    value: msg.value / orders
                }(positionId)
            {} catch {}
            unchecked {
                ++_startIndex;
            }
            emit ExecutedIncreaseOrder(positionId);
        }

        pendingIncreaseOrdersStartIndex = _startIndex;
    }

    function setCallbackCaller(address _address, bool _set) external onlyOwner {
        validCallbackCallers[_address] = _set;
        emit CallbackCallerSet(_address, _set);
    }
}

