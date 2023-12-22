// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.16;

import "./AccessControl.sol";
import "./ERC721Burnable.sol";

import "./IArkenOptionNFT.sol";

contract ArkenOptionNFT is ERC721Burnable, AccessControl, IArkenOptionNFT {
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
    string public baseURI;
    uint256 internal tokenIdCounter;

    mapping(uint256 => TokenData) internal _tokenData;
    mapping(uint256 => uint256) internal _createdAt;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI_
    ) ERC721(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        baseURI = baseURI_;
    }

    function mint(
        address to,
        TokenData calldata data
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = ++tokenIdCounter;
        _mint(to, tokenId);
        _tokenData[tokenId] = data;
        _createdAt[tokenId] = block.timestamp;
        emit MintTokenData(tokenId, data);
    }

    function updateBaseURI(
        string calldata baseURI_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = baseURI_;
        emit UpdateBaseURI(baseURI_);
    }

    function tokenData(
        uint256 tokenId
    ) external view returns (TokenData memory data, uint256 createdAt_) {
        createdAt_ = _createdAt[tokenId];
        data = _tokenData[tokenId];
    }

    function createdAt(uint256 tokenId) external view returns (uint256) {
        return _createdAt[tokenId];
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(AccessControl, ERC721, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

