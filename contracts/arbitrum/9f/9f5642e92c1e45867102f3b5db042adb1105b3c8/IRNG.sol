//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IRNG {
    function makeRequestUint256() external returns (bytes32);

    function makeRequestUint256Array(uint256 _size) external returns (bytes32);

    function setRequestParameters(
        uint64 _vrfSubscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        bytes32 _keyHash
    ) external;

    function setCallerWhitelist(address _caller, bool _isWhitelisted) external;

    function getExpectingRequestWithIdToBeFulfilled(
        bytes32
    ) external returns (bool);

    function getCallers(bytes32) external returns (address);

    function getCallerWhitelist(address) external returns (bool);
}

