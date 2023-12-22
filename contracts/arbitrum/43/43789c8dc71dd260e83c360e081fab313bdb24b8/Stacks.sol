// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Ownable.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC2981.sol";
import "./WhitelistData.sol";
import "./StacksAuctionHouse.sol";

contract Stacks is ERC721, ERC721Enumerable, ERC2981, Ownable {
  bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

  uint public constant PERCENT_DIVIDER = 10000;
  uint public SALE_FEE = 1000; // 10%

  bool public wlMintOpen;

  mapping(uint => TokenMetaData) public tokenMetaDataRecord;

  address public auctionHouse;
  bool public mintOpen;
  uint public maxSupply = 5000; // Immutable
  uint public softCap = 4009; // Available for auction - Immutable
  uint public teamMinted = 0;
  address public wlDataAddress;
  address public treasuryAddress;

  struct TokenMetaData {
    bool minted;
    address minter;
    uint timestamp;
  }

  constructor(address _treasuryAddress, address _wlDataAddress) ERC721("Stacks Investment Card", "STACKS") {
    treasuryAddress = _treasuryAddress;
    wlDataAddress = _wlDataAddress;
  }

  function mint(uint _tokenId) public {
    require(mintOpen, "Minting is not open");
    require(_tokenId >=0 && _tokenId <= maxSupply, "Token ID is invalid");

    StacksAuctionHouse auctionHouseContract = StacksAuctionHouse(auctionHouse);
    StacksAuctionHouse.Auction memory auction = auctionHouseContract.getAuction(_tokenId);
    require(auction.endTime < block.timestamp, "Auction is not closed");
    require(auction.topBidder == msg.sender, "You are not the winner of this auction");

    require(!tokenMetaDataRecord[_tokenId].minted, "Token has already been minted");

    tokenMetaDataRecord[_tokenId] = TokenMetaData(true, msg.sender, block.timestamp);
    _safeMint(msg.sender, _tokenId);
  }

  // Admin functions
  function setTreasuryAddress(address payable _treasuryAddress) public onlyOwner {
    treasuryAddress = _treasuryAddress;
  }

  function setAuctionHouse(address _auctionHouse) public onlyOwner {
    auctionHouse = _auctionHouse;
  }

  function toggleMint(bool _open) public onlyOwner {
    mintOpen = _open;
  }

  function toggleWlMint(bool _open) public onlyOwner {
    wlMintOpen = _open;
  }

  function wlMint() public {
    require(wlMintOpen, "Minting is not open");
    WhitelistData.Account memory wlAccount = WhitelistData(wlDataAddress).getWhitelistAccount(msg.sender);
    require(wlAccount.exists, "Address not whitelisted");

    uint _tokenId = wlAccount.tokenId;
    require(!tokenMetaDataRecord[_tokenId].minted, "Token has already been minted");

    tokenMetaDataRecord[_tokenId] = TokenMetaData(true, msg.sender, block.timestamp);
    _safeMint(msg.sender, _tokenId);
  }

  // Mint token for team members
  function teamMint(address _teamMember) public onlyOwner {
    // _tokenId for team is between 4010 and 5000
    uint _tokenId = softCap + teamMinted + 1;
    require(_tokenId <= maxSupply, "Token ID is too high");

    // make it so team can only mint 300 tokens per year
    // 2023: 4010 - 4309
    if(_tokenId >= 4310) {
      // 2024: 4310 - 4609
      require(block.timestamp > 1704067199, "Team can only mint 300 tokens in 2023"); // 31/12/2023
    }
    if(_tokenId >= 4610) {
      // 2025: 4610 - 4909
      require(block.timestamp > 1735689599, "Team can only mint 300 tokens in 2024"); // 31/12/2024
    }
    if(_tokenId >= 4910) {
      // 2026: 4910 - 5000
      require(block.timestamp > 1767225599, "Team can only mint the remaining tokens in 2025"); // 31/12/2025
    }

    // set mint timestamp
    tokenMetaDataRecord[_tokenId] = TokenMetaData(true, _teamMember, block.timestamp);
    // mint token
    _safeMint(_teamMember, _tokenId);
    teamMinted++;
  }

  function setRegularFee(uint _SALE_FEE) public onlyOwner {
    require(_SALE_FEE <= 3300, "Fee must be less or equal to 33%");
    SALE_FEE = _SALE_FEE;
  }

  function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC721, ERC2981, ERC721Enumerable) returns (bool) {
    if (_interfaceId == _INTERFACE_ID_ERC2981) { return true; }
    return super.supportsInterface(_interfaceId);
  }

  function royaltyInfo(uint256, uint256 _salePrice) override view public returns (address receiver, uint256 royaltyAmount){
    return (treasuryAddress, _salePrice * SALE_FEE / PERCENT_DIVIDER);
  }

  // Overwrite tokenURI
  // ignore tokenId as all the tokens have the same image
  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    _requireMinted(_tokenId);
    return string(abi.encodePacked(_baseURI()));
  }

  // Overwrite _baseURI
  function _baseURI() override pure internal returns (string memory) {
    return "ipfs://QmWGK8DFya3xn642gLtp5zdTz2kKJetaiVX8razBL5Nzu4/stacks";
  }

  function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) internal virtual override(ERC721, ERC721Enumerable) {
    return super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
  }
}

