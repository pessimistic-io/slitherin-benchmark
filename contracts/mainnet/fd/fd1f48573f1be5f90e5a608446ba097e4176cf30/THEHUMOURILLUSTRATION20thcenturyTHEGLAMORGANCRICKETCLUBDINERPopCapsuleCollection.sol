// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC2981.sol";
import "./Counters.sol";
import "./Address.sol";

contract
THEHUMOURILLUSTRATION20thcenturyTHEGLAMORGANCRICKETCLUBDINERPopCapsuleCollection
is
ERC721,
IERC2981,
ReentrancyGuard,
Ownable
{
  using Counters for Counters.Counter;

  constructor(string memory customBaseURI_)
    ERC721(
      "THE HUMOUR ILLUSTRATION 20th century - THE GLAMORGAN CRICKET CLUB DINER - Pop Capsule Collection",
      "THT3"
    )
  {
    customBaseURI = customBaseURI_;
  }

  /** MINTING **/

  uint256 public constant MAX_SUPPLY = 12;

  uint256 public constant MAX_MULTIMINT = 12;

  Counters.Counter private supplyCounter;

  function mint(uint256 count) public nonReentrant {
    require(saleIsActive, "Sale not active");

    require(totalSupply() + count - 1 < MAX_SUPPLY, "Exceeds max supply");

    require(count <= MAX_MULTIMINT, "Mint at most 12 at a time");

    for (uint256 i = 0; i < count; i++) {
      _mint(msg.sender, totalSupply());

      supplyCounter.increment();
    }
  }

  function totalSupply() public view returns (uint256) {
    return supplyCounter.current();
  }

  /** ACTIVATION **/

  bool public saleIsActive = true;

  function setSaleIsActive(bool saleIsActive_) external onlyOwner {
    saleIsActive = saleIsActive_;
  }

  /** URI HANDLING **/

  string private customBaseURI;

  function setBaseURI(string memory customBaseURI_) external onlyOwner {
    customBaseURI = customBaseURI_;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return customBaseURI;
  }

  function tokenURI(uint256 tokenId) public view override
    returns (string memory)
  {
    return string(abi.encodePacked(super.tokenURI(tokenId), ".token.json"));
  }

  /** PAYOUT **/

  function withdraw() public nonReentrant {
    uint256 balance = address(this).balance;

    Address.sendValue(payable(owner()), balance);
  }

  /** ROYALTIES **/

  function royaltyInfo(uint256, uint256 salePrice) external view override
    returns (address receiver, uint256 royaltyAmount)
  {
    return (address(0x1B36a150f495783Ac569b6F2E338bF604c7FA403), (salePrice * 1250) / 10000);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721, IERC165)
    returns (bool)
  {
    return (
      interfaceId == type(IERC2981).interfaceId ||
      super.supportsInterface(interfaceId)
    );
  }
}
