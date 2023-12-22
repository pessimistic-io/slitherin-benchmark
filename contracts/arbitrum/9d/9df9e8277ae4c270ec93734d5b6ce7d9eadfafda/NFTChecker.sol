pragma solidity ^0.8.12;

import "./LzApp.sol";
import "./IERC721.sol";

contract NFTChecker is LzApp {
    event ReceivedMessage(uint16 indexed srcChainId, bytes srcAddress, uint64 nonce, bytes payload);

    constructor(address _endpoint) LzApp(_endpoint) {}

    function doesOwnNFT(address nftContract, address user, uint tokenId) public view returns (bool) {
        IERC721 erc721 = IERC721(nftContract);
        return erc721.ownerOf(tokenId) == user;
    }

    function _lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal {
        (address nftContract, address user, uint tokenId) = abi.decode(_payload, (address, address, uint));
        bool ownsNFT = doesOwnNFT(nftContract, user, tokenId);

        // Send result back to the other contract.
        bytes memory payload = abi.encode(ownsNFT);
        _lzSend(_srcChainId, payload, payable(msg.sender), address(0), "", 0);
    }

    function _blockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override {
        // Your implementation here
        // For example, you might want to emit an event
        emit ReceivedMessage(_srcChainId, _srcAddress, _nonce, _payload);
    }
}
