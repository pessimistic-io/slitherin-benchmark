// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import "./ECDSA.sol";
import "./Strings.sol";

contract ReadONPickBadge is ERC721,AccessControl,Pausable {
    using ECDSA for bytes32;
    using Strings for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public signer;

    constructor() ERC721("Pick", "Pick") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }
    

    function _baseURI() internal pure override returns (string memory) {
        return "https://readon-api.readon.me/v1/metadata/vote/";
    }

    function safeMint(uint256 tokenId, bytes memory signature)
        public
    {
        require(verifySignature(tokenId.toString(),signature),"ReadON:invalid signature");
        _safeMint(msg.sender, tokenId);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function setSigner(address _signer) public onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal whenNotPaused override {
        require(
            from == address(0),
            "ReadON: Token transfer not allowed"
        );
        super._beforeTokenTransfer(from, to, tokenId,batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function verifySignature(string memory message, bytes memory signature) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(message));
        bytes32 prefixedHash = messageHash.toEthSignedMessageHash();
        
        address recoveredSigner = prefixedHash.recover(signature);
        
        return (recoveredSigner == signer);
    }
}

