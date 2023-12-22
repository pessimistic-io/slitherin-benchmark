// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./Strings.sol";
import "./AccessControlEnumerable.sol";

contract EmployeeNFT is ERC721, ERC721URIStorage, Ownable, AccessControlEnumerable {
    uint256 private _count;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        _setupRole(
            DEFAULT_ADMIN_ROLE,
            msg.sender
        );
    }
        function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function isAdmin(address account) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    modifier onlyAdmin() {
        require(this.isAdmin(msg.sender), "Restricted to admins.");
        _;
    }

    function addAdmin(address account) public virtual onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, account);
    }

    function renounceAdminRole() public virtual {
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(
        address to,
        uint32 _tokenId,
        string memory _tokenURI
    ) public onlyAdmin {
        _safeMint(to, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        _count++;
    }

    function update(
        address to,
        uint32 _tokenId,
        string memory _tokenURI
    ) public onlyAdmin {
        _burn(_tokenId);
        _safeMint(to, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
    }

    function updateTokenURI(
        uint32 _tokenId,
        string memory _tokenURI
    ) public onlyAdmin {
        _setTokenURI(_tokenId, _tokenURI);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
        --_count;
    }

    function burnToken(uint256 tokenId) external onlyAdmin {
        _burn(tokenId);
    }

    function updateTokenURI(
        uint256 tokenId,
        string memory uri
    ) public onlyAdmin {
        _setTokenURI(tokenId, uri);
    }

    function getTotalTokenCount() external view returns (uint256) {
        return _count;
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(from == address(0), "You can't transfer this NFT.");

        super._transfer(from, to, tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControlEnumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

