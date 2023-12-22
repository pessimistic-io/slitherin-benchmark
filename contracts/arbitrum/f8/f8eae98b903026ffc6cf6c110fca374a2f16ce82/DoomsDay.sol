// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC1155.sol";
import "./AccessControl.sol";
import "./StringConverter.sol";

// @title Doomsday: Adventure Into The Gloomyverse
// @author: Stinky (@nomamesgwei)
// @notice ERC-1155 Art Collection by Oblomov
contract DoomsDay is ERC1155, AccessControl {

    // @dev Contract Token Name
    string public name = "Doomsday: Adventure Into The Gloomyverse";
    // @dev Contract Symbol
    string public symbol = "GMVS";
    // @dev Whitelist per Token
    mapping (uint256 => mapping(address => uint256)) whitelist;
    // @dev custom baseURI
    string private baseURI;

    // @dev Custom Errors
    error NotAuthorized(); 

    // @dev ERC-1155 contract for Gloomy Doomer claims
    // @param stringURI The baseURI for the token
    constructor(string memory stringURI) ERC1155(stringURI) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        baseURI = stringURI;
    }

    // @dev Update the URI
    // @param newuri The new uri link
    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    // @notice Mint Token if you are whitelist
    // @param tokenId The token ID to mint
    // @param data ERC-1155
    function mint(uint256 tokenId, bytes memory data) external {
        if(whitelist[tokenId][_msgSender()] == 0) { revert NotAuthorized(); }
        _mint(_msgSender(), tokenId, whitelist[tokenId][_msgSender()], data);
        whitelist[tokenId][_msgSender()] = 0;
    }

    // @dev Add whitelist per tokenID
    // @param tokenId The ID to set for airdrop
    // @param winners The list of address to whitelit
    // @param amount Number of mints to
    function addWhitelist(
        uint256 tokenId, 
        address[] calldata winners, 
        uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 length = winners.length;
        for (uint i; i < length;) {
            whitelist[tokenId][winners[i]] = amount;
            // Cannot possibly overflow due to size of array
            unchecked {++i;}            
        }
    }

    // @dev Retreive status for user on specific tokenId
    // @param tokenId The tokenId to check
    // @param user The address to check
    function isWhitelisted(uint256 tokenId, address user) public view returns(uint256) {
        return whitelist[tokenId][user];
    }

    // @dev required override
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function uri(uint256 tokenId) public view virtual override returns(string memory) {
      return string(abi.encodePacked(baseURI, StringConverter.toString(tokenId), '.json'));  
    } 
}
