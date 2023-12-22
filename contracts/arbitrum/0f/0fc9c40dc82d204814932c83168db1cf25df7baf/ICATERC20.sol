// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICATERC20 {
    function initialize(
        uint16 chainId,
        address wormhole,
        uint8 finality,
        uint256 maxSupply
    ) external;

    /**
     * @dev To bridge tokens to other chains.
     */
    function bridgeOut(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce
    ) external payable returns (uint64 sequence);

    function bridgeIn(bytes memory encodedVm) external returns (bytes memory);

    function mint(address recipient, uint256 amount) external;
}

