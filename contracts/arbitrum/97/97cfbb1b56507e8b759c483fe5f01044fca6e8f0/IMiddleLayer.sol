// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

abstract contract IMiddleLayer {
    // Function reserved for sending messages that could be fallbacks, or are indirectly created by the user ie FB_BORROW
    function msend(
        uint256 dstChainId,
        bytes memory payload,
        address payable refundAddress,
        bool shouldForward
    ) external payable virtual;

    // Function reserved for sending messages that are directly created by a user ie MASTER_DEPOSIT
    function msend(
        uint256 dstChainId,
        bytes memory payload,
        address payable refundAddress,
        address route,
        bool shouldForward
    ) external payable virtual;

    function mreceive(
        uint256 _srcChainId,
        bytes memory _payload
    ) external virtual returns (bool success);
}

