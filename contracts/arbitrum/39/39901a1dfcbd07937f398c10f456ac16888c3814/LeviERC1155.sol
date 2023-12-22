// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./ERC1155.sol";
import "./Ownable.sol";

// Made with love for the Levi Community
// made by: Leverage Inu Team

contract LeviERC1155 is ERC1155, Ownable {

  mapping(uint256 => uint256) public tokenWhitelisted;
  mapping(uint256 => string) public tokenURIS;
  mapping(address => uint256) public contractToWhitelisted;
  mapping(uint256 => uint256) public tokenIDToURILocked;

  event ContractWhitelisted(address _contract);
  event URILocked(uint256 tokenID);

  error LeveragedCollections_Zero_Address();
  error LeveragedCollections_Not_Whitelisted();
  error LeveragedCollections_Uri_Locked();
  error LeveragedCollections_Cannot_Whitelist_Twice();

  constructor() ERC1155("") {

  }

  function mint(address account, uint256 tokenID) external {
    if(contractToWhitelisted[msg.sender] == 0) revert LeveragedCollections_Not_Whitelisted();

    _mint(account, tokenID, 1, "");
  }

  function whitelistContract(address contractToWhitelist, uint256 tokenID) external onlyOwner {
    if(tokenWhitelisted[tokenID] == 1) revert LeveragedCollections_Cannot_Whitelist_Twice();

    contractToWhitelisted[contractToWhitelist] = 1;
    tokenWhitelisted[tokenID] = 1;

    emit ContractWhitelisted(contractToWhitelist);
  }

  function setURI(string memory _uri, uint256 tokenID) external onlyOwner {
    if(tokenIDToURILocked[tokenID] == 1) revert LeveragedCollections_Uri_Locked();

    tokenURIS[tokenID] = _uri;

    emit URI(_uri, tokenID);
  }

  function lockURI(uint256 tokenID) external onlyOwner {
    tokenIDToURILocked[tokenID] = 1;

    emit URILocked(tokenID);
  }

  function uri(uint256 tokenId) public view override returns(string memory) {
    return tokenURIS[tokenId];
  }
}
