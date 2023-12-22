// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721AQueryable.sol";
import "./ERC721ABurnable.sol";
import "./Withdrawable.sol";
import "./OperatorFilterer.sol";
import "./IERC2981.sol";
import "./Ownable.sol";

abstract contract BaseERC721A is
    ERC721AQueryable,
    ERC721ABurnable,
    OperatorFilterer,
    Withdrawable,
    IERC2981
{
    bool public operatorFilteringEnabled;

    constructor(string memory name, string memory symbol) ERC721A(name, symbol) {
        _registerForOperatorFiltering();
        operatorFilteringEnabled = true;
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override (IERC721A, ERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        payable
        override (IERC721A, ERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId)
        public
        payable
        override (IERC721A, ERC721A)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        payable
        override (IERC721A, ERC721A)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        payable
        override (IERC721A, ERC721A)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override (IERC721A, ERC721A, IERC165)
        returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId) || interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function setOperatorFilteringEnabled(bool value) public onlyOwner {
        operatorFilteringEnabled = value;
    }

    function _operatorFilteringEnabled() internal view override returns (bool) {
        return operatorFilteringEnabled;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

}
