// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./AccessControl.sol";
import "./Counters.sol";

contract Custom is ERC721Enumerable, ERC721URIStorage, AccessControl {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    uint256 public MAX_NFT;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(uint256 maxNftSupply, address admin) ERC721("Commonopoly", "COM") {
        MAX_NFT = maxNftSupply;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function changeURI(uint256 tokenId, string memory _tokenURI) public onlyRole(MINTER_ROLE) {
        _setTokenURI(tokenId,_tokenURI);
    }

    function mintToWallet(string memory _tokenURI) public onlyRole(MINTER_ROLE) returns (uint) {
        require(_tokenIds.current() <= MAX_NFT);

        uint256 tokenId = _tokenIds.current();
        _tokenIds.increment();

        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        return tokenId;
    }

        function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

        function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

        function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

}
