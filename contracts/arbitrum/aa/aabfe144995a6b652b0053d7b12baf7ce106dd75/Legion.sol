//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CountersUpgradeable.sol";
import "./Initializable.sol";

import "./LegionContracts.sol";

contract Legion is Initializable, LegionContracts {

    using CountersUpgradeable for CountersUpgradeable.Counter;

    function initialize() external initializer {
        LegionContracts.__LegionContracts_init();
    }

    function safeMint(address _to) external override onlyAdminOrOwner whenNotPaused contractsAreSet returns(uint256) {
        uint256 _tokenId = tokenIdCounter.current();
        _safeMint(_to, _tokenId);
        tokenIdCounter.increment();
        return _tokenId;
    }

    function setTokenURI(uint256 _tokenId, string calldata _tokenURI) external onlyAdminOrOwner whenNotPaused contractsAreSet {
        _setTokenURI(_tokenId, _tokenURI);
    }

    function totalSupply() external view returns(uint256) {
        return tokenIdCounter.current() - 1;
    }

    function adminSafeTransferFrom(address _from, address _to, uint256 _tokenId) external onlyAdminOrOwner whenNotPaused contractsAreSet {
        _transfer(_from, _to, _tokenId);
    }

    function adminBurn(address _from, uint256 _tokenId) external onlyAdminOrOwner whenNotPaused {
        require(ownerOf(_tokenId) == _from, "User does not own this legion");

        _burn(_tokenId);
    }

    function _beforeTokenTransfer(address _from, address _to, uint256 _tokenId) internal override {
        super._beforeTokenTransfer(_from, _to, _tokenId);

        if(!isAdmin(msg.sender)) {
            LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenId);
            require(_legionMetadata.legionGeneration != LegionGeneration.RECRUIT, "Can't transfer recruits");
        }
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721URIStorageUpgradeable, IERC721MetadataUpgradeable) returns (string memory) {
        require(_exists(tokenId), "token does not exist");

        return legionMetadataStore.tokenURI(tokenId);
    }

}
