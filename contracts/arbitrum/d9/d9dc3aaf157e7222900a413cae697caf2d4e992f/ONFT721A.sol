// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IONFT721A.sol";
import "./ONFT721ACore.sol";
import "./ERC721ASpecific.sol";
import "./DefaultOperatorFilterer.sol";


contract ONFT721A is ONFT721ACore, ERC721ASpecific, IONFT721A, DefaultOperatorFilterer{
    constructor(string memory _name, string memory _symbol, uint256 _minGasToTransfer, address _lzEndpoint, uint256 _startId) ERC721ASpecific(_name, _symbol, _startId) ONFT721ACore(_minGasToTransfer, _lzEndpoint) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ONFT721ACore, ERC721ASpecific, IONFT721A) returns (bool) {
        return interfaceId == type(IONFT721A).interfaceId || super.supportsInterface(interfaceId);
    }

    function _debitFrom(address _from, uint16, bytes memory, uint _tokenId) internal virtual override {
        bridgeTransfer(_from, address(this), _tokenId);
    }

    function _creditTo(uint16, address _toAddress, uint _tokenId) internal virtual override {
        require(!_exists(_tokenId) || (_exists(_tokenId) && ERC721ASpecific.ownerOf(_tokenId) == address(this)));
        if (!_exists(_tokenId)) {
            bridgeMint(_toAddress, _tokenId);
        } else {
            bridgeTransfer(address(this), _toAddress, _tokenId);
        }
    }

    function setApprovalForAll(address operator, bool approved) public override(ERC721ASpecific, IERC721ASpecific) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public payable override(ERC721ASpecific, IERC721ASpecific) onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable override(ERC721ASpecific, IERC721ASpecific) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public payable override(ERC721ASpecific, IERC721ASpecific) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        payable
        override(ERC721ASpecific, IERC721ASpecific)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}

