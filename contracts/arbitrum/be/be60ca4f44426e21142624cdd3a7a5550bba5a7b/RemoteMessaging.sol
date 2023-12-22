// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

abstract contract RemoteMessaging {
    function _sendMessage(
        bytes calldata instructionData,
        bytes memory payload
    ) internal virtual;

    function _processPayload(bytes calldata payload) internal virtual;

    function _encodePayload(
        address sender,
        address recipient,
        uint256 shares
    ) internal pure returns (bytes memory) {
        return abi.encode(sender, recipient, shares);
    }

    function _decodePayload(
        bytes calldata payload
    )
        internal
        pure
        returns (address sender, address recipient, uint256 shares)
    {
        (sender, recipient, shares) = abi.decode(
            payload,
            (address, address, uint256)
        );
    }
}

