// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./AddressUpgradeable.sol";

interface ITransferManager {
    function getInputData(address nftAddress, address from, address to, uint256 tokenId, bytes32 operateType) external view returns (bytes memory data);
}

library TransferHelper {

    using AddressUpgradeable for address;

    // keccak256("TRANSFER_IN")
    bytes32 private constant TRANSFER_IN = 0xe69a0828d85fdb5875ad77f7b8a0e2275447a64f18daaf58f34b3af9b7b691da;
    // keccak256("TRANSFER_OUT")
    bytes32 private constant TRANSFER_OUT = 0x2b6780fa84213a97faf5c6208861692a9b75df0c4afffad07a2dc98411dfe785;
    // keccak256("APPROVAL")
    bytes32 private constant APPROVAL = 0x2acd155ba8c67e9321668716d05aae1ff9e47e502b6b2f301b6f41e3a57ee2ef;

    /**
     * @notice Transfer in NFT
     * @param transferManager nft transfer manager contract address
     * @param nftAddr nft address
     * @param from Sender address
     * @param to Receiver address
     * @param nftId NFT ID   
     */
    function transferInNonFungibleToken(address transferManager, address nftAddr, address from, address to, uint256 nftId) internal {
        bytes memory data = ITransferManager(transferManager).getInputData(nftAddr, from, to, nftId, TRANSFER_IN);
        nftAddr.functionCall(data);
    }

    /**
     * @notice Transfer in NFT
     * @param transferManager nft transfer manager contract address
     * @param nftAddr nft address
     * @param from Sender address
     * @param to Receiver address
     * @param nftId NFT ID   
     */
    function transferOutNonFungibleToken(address transferManager, address nftAddr, address from, address to, uint256 nftId) internal {
        bytes memory data = ITransferManager(transferManager).getInputData(nftAddr, from, to, nftId, TRANSFER_OUT);
        nftAddr.functionCall(data);
    }

    /**
     * @notice Approve NFT
     * @param transferManager nft transfer manager contract address
     * @param nftAddr nft address
     * @param from Sender address
     * @param to Receiver address
     * @param nftId NFT ID   
     */
    function approveNonFungibleToken(address transferManager, address nftAddr, address from, address to, uint256 nftId) internal {
        bytes memory data = ITransferManager(transferManager).getInputData(nftAddr, from, to, nftId, APPROVAL);
        nftAddr.functionCall(data);
    }
}
