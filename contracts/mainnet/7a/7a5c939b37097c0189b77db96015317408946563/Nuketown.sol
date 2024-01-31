// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./introspection_IERC165.sol";
import "./IERC2981.sol";
import "./Math.sol";
import "./Strings.sol";
import "./PRBMathUD60x18.sol";

contract Nuketown is Ownable, ERC721A, IERC2981 {

  bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;
  bytes4 private constant INTERFACE_ID_ERC165 = 0x01ffc9a7;
  bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
  bytes4 private constant INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;

  uint public maxSupply;
  uint public reservedSupply;

  string private tokenUriPrefix;

  address private royaltyAddress;
  uint private royaltyFee = 0.07 ether;

  mapping(address => uint) private tokensAllowed;
  mapping(address => uint) private tokensMinted;

  constructor(
      string memory tokenUriPrefix_,
      address royaltyAddress_
  ) ERC721A("Community Member", "CM") {
    tokenUriPrefix = tokenUriPrefix_;
    royaltyAddress = royaltyAddress_;
    maxSupply = 10000;
    reservedSupply = 1000;
  }

  /*** NFT basics ***/

  function tokenURI(uint tokenId) public view virtual override
      returns (string memory) {
    require(_exists(tokenId), "tokenURI: Token does not exist");
    return string(abi.encodePacked(tokenUriPrefix, Strings.toString(tokenId)));
  }

  function exists(uint tokenId) external view returns (bool) {
    return _exists(tokenId);
  }

  function royaltyInfo(uint tokenId, uint salePrice) external view override
      returns (address receiver, uint royaltyAmount) {
    require(_exists(tokenId), "royaltyInfo: Token does not exist");
    return (royaltyAddress, PRBMathUD60x18.mul(salePrice, royaltyFee));
  }

  /*** ERC721A customizations ***/

  function _startTokenId() internal pure override returns (uint256) {
    return 1;
  }

  /*** Mint ***/

  function mint(uint amount) external {
    uint maxAllowed = tokensAllowed[_msgSender()];
    if (maxAllowed == 0) maxAllowed = 1;
    require(tokensMinted[_msgSender()] + amount <= maxAllowed,
        'mint: Max tokens already minted');

    require(totalSupply() + amount + reservedSupply <= maxSupply,
        'mint: Token supply exhausted');

    _mint(_msgSender(), amount);
    tokensMinted[_msgSender()] += amount;
  }

  /*** Owner privileges ***/

  function mintReserved(address recipient, uint amount) external onlyOwner {
    require(totalSupply() + amount <= maxSupply,
        'mint: Token supply exhausted');

    _mint(recipient, amount);
    reservedSupply = Math.max(0, reservedSupply - amount);
  }

  function allowMore(address minter, uint additionalAmount) external onlyOwner {
    uint maxAllowed = tokensAllowed[minter];
    if (maxAllowed == 0) maxAllowed = 1;
    tokensAllowed[minter] = maxAllowed + additionalAmount;
  }

  function setMaxSupply(uint maxSupply_) external onlyOwner {
    require(maxSupply_ < maxSupply, "setMaxSupply: Max supply can only be reduced");
    maxSupply = maxSupply_;
  }

  function setTokenUri(string calldata tokenUriPrefix_) external onlyOwner {
    tokenUriPrefix = tokenUriPrefix_;
  }

  function setRoyaltyAddress(address royaltyAddress_) external onlyOwner {
    royaltyAddress = royaltyAddress_;
  }

  /*** ERC165 ***/

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, IERC165) returns (bool) {
    return interfaceId == INTERFACE_ID_ERC2981
        || interfaceId == INTERFACE_ID_ERC165
        || interfaceId == INTERFACE_ID_ERC721
        || interfaceId == INTERFACE_ID_ERC721_METADATA;
  }
}

