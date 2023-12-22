// SPDX-License-Identifier: MIT
//
//
//   ■■■■                         ■                                 ■    ■  ■■■■■■■■■■■                           
//  ■■  ■                                        ■                  ■■   ■  ■       ■                             
//  ■    ■  ■■■■   ■■■  ■■■■ ■■   ■  ■■■■  ■  ■ ■■■   ■■■  ■■■      ■■■  ■  ■       ■                             
//  ■    ■  ■  ■  ■  ■  ■  ■■  ■  ■  ■  ■  ■  ■  ■   ■  ■  ■  ■     ■ ■  ■  ■       ■                             
//  ■    ■  ■  ■ ■■■■■  ■  ■   ■  ■  ■  ■  ■  ■  ■  ■■■■■  ■■■      ■  ■ ■  ■■■■    ■                             
//  ■    ■  ■  ■ ■■     ■  ■   ■  ■  ■  ■  ■  ■  ■  ■■       ■■     ■  ■■■  ■       ■                             
//  ■■  ■   ■  ■  ■     ■  ■   ■  ■  ■  ■  ■  ■  ■   ■     ■  ■     ■   ■■  ■       ■                             
//   ■■■■   ■  ■   ■■■  ■  ■   ■  ■  ■  ■  ■■■■  ■■   ■■■  ■■■      ■   ■■  ■       ■                             
//                           
//
// SPECIAL THANKS
// P5JS
// P5SOUNDJS
// THREEJS
// DigitalNormal-xO6j.otf
// CHATGPT-4
//

pragma solidity ^0.8.17;
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./SafeMath.sol";
import "./RoyaltiesV2Impl.sol";
import "./LibPart.sol";
import "./LibRoyaltiesV2.sol";
import "./console.sol";

contract Oneminutes is ERC721Enumerable, Ownable, RoyaltiesV2Impl{
  bool public paused = false;
  string public baseTokenURI;
  uint256 public cost = 0.02 ether;
  uint256 public maxSupply = 60;
  uint256 public airdropStartDate = 1684088400; // 2023-05-15 21:00:00 JST
  uint256 public mintStartDate = 1684099200; // 2023-05-16 00:00:00 JST
  uint256 public maxMintAmount = 1;
  mapping(address => uint256) private _mintedTokensPerWallet;

  using SafeMath for uint256;
  using Counters for Counters.Counter;
  Counters.Counter private _tokenIds;

  bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

  // Whitelist
  address[] public whitelist;
  address public airdropper;

  // Set airdropper
  function setAirdropper(address _airdropper) external onlyOwner {
      airdropper = _airdropper;
  }

  // Modifier to allow minting only by owner or airdropper
  modifier onlyMinter() {
      require(msg.sender == owner() || msg.sender == airdropper, "Caller is not a minter");
      _;
  }

  constructor(string memory baseURI) ERC721 ("Oneminutes", "1MN") {
      setBaseURI(baseURI);
  }

  function _baseURI() internal view virtual override returns (string memory) {
      return baseTokenURI;
  }
  function setBaseURI(string memory _baseTokenURI) public onlyOwner {
      baseTokenURI = _baseTokenURI;
  }
  function getTotalNFTsMintedSoFar() public view returns(uint256) {
            return _tokenIds.current();
  }
  function getMintStartDate() public view returns (uint256) {
    return mintStartDate;
  }
  // OwnerReserveFunction
  function reserveNFTs() public onlyOwner {
      uint totalMinted = _tokenIds.current();
      require(totalMinted.add(5) < maxSupply);
      for (uint i = 0; i < 5; i++) {
          _mintSingleNFT();
      }
  }
  // Airdrop function
  function mintTo(address _to, uint256 _tokenId) external onlyMinter {
    require(block.timestamp >= airdropStartDate, "Airdrop is not allowed before 2023-05-15 21:00:00 JST.");
    _safeMint(_to, _tokenId);
    _tokenIds.increment(); // Add this line to increment the tokenIdCounter
  }
  // Publicmint function
  function mintNFTs(uint256 _count) public payable {
    uint totalMinted = _tokenIds.current();
    require(!paused);
    require(block.timestamp >= mintStartDate, "Minting is not allowed before 2023-05-16 JST.");
    require(totalMinted.add(_count) <= maxSupply, "SOLD OUT!");
    require(_count > 0 && _count <= maxMintAmount, "Cannot mint specified number of NFTs.");
    require(msg.value >= cost.mul(_count), "Not enough ether to purchase NFTs.");
    require(_mintedTokensPerWallet[msg.sender] < 1, "Wallet can mint only one token.");

    for (uint i = 0; i < _count; i++) {
        _mintSingleNFT();
    }

    // Update the minted tokens count for the wallet
    _mintedTokensPerWallet[msg.sender] += _count;
  }

  function _mintSingleNFT() private {
      uint newTokenID = _tokenIds.current();
      _safeMint(msg.sender, newTokenID);
      _tokenIds.increment();
  }
  function walletOfOwner(address _owner)
    external view returns (uint[] memory)
      {
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory tokensId = new uint256[](ownerTokenCount);
    for (uint256 i = 0; i < ownerTokenCount; i++) {
      tokensId[i] = tokenOfOwnerByIndex(_owner, i);
    }
    return tokensId;
  }
  //set the max amount an address can mint
  function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner {
    maxMintAmount = _newmaxMintAmount;
  }
  //pause the contract and do not allow any more minting
  function pause(bool _state) public onlyOwner {
    paused = _state;
  }
  function withdraw() public onlyOwner {
    (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
    require(success);
  }
  //configure royalties for Rariable
  function setRoyalties(uint _tokenId, address payable _royaltiesRecipientAddress, uint96 _percentageBasisPoints) public onlyOwner {
        LibPart.Part[] memory _royalties = new LibPart.Part[](1);
        _royalties[0].value = _percentageBasisPoints;
        _royalties[0].account = _royaltiesRecipientAddress;
        _saveRoyalties(_tokenId, _royalties);
    }
    //configure royalties for Mintable using the ERC2981 standard
  function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns (address receiver, uint256 royaltyAmount) {
    //use the same royalties that were saved for Rariable
    LibPart.Part[] memory _royalties = royalties[_tokenId];
    if(_royalties.length > 0) {
      return (_royalties[0].account, (_salePrice * _royalties[0].value) / 10000);
    }
    return (address(0), 0);
  }
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable) returns (bool) {
    if(interfaceId == LibRoyaltiesV2._INTERFACE_ID_ROYALTIES) {
        return true;
    }
    if(interfaceId == _INTERFACE_ID_ERC2981) {
      return true;
    }
    return super.supportsInterface(interfaceId);
  }
}

