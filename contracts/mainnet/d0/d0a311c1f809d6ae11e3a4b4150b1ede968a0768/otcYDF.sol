// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./IOverTheCounterSlim.sol";

contract otcYDF is ERC721Enumerable, Ownable {
  using Strings for uint256;
  using Counters for Counters.Counter;

  address public overTheCounter;

  Counters.Counter internal _ids;
  string private baseTokenURI; // baseTokenURI can point to IPFS folder like https://ipfs.io/ipfs/{cid}/ while
  address public royaltyAddress;

  // Royalties basis points (percentage using 2 decimals - 1000 = 100, 500 = 50, 0 = 0)
  uint256 private royaltyBasisPoints = 50; // 5%

  // array of all the NFT token IDs owned by a user
  mapping(address => uint256[]) public allUserOwned;
  // the index in the token ID array at allUserOwned to save gas on operations
  mapping(uint256 => uint256) public ownedIndex;

  mapping(uint256 => uint256) public tokenMintedAt;

  event Burn(uint256 indexed tokenId, address indexed owner);
  event Mint(uint256 indexed tokenId, address indexed owner);
  event SetPaymentAddress(address indexed user);
  event SetRoyaltyAddress(address indexed user);
  event SetRoyaltyBasisPoints(uint256 indexed _royaltyBasisPoints);
  event SetBaseTokenURI(string indexed newUri);

  modifier onlyOTC() {
    require(msg.sender == overTheCounter, 'only OTC');
    _;
  }

  constructor(string memory _baseTokenURI)
    ERC721('Yieldification OTC', 'otcYDF')
  {
    baseTokenURI = _baseTokenURI;
    overTheCounter = msg.sender;
  }

  function mint(address owner) external onlyOTC returns (uint256) {
    _ids.increment();
    _safeMint(owner, _ids.current());
    tokenMintedAt[_ids.current()] = block.timestamp;
    emit Mint(_ids.current(), owner);
    return _ids.current();
  }

  function burn(uint256 _tokenId) external onlyOTC {
    address _user = ownerOf(_tokenId);
    require(_exists(_tokenId));
    _burn(_tokenId);
    emit Burn(_tokenId, _user);
  }

  function approveOverTheCounter(uint256 _tokenId) external onlyOTC {
    _approve(overTheCounter, _tokenId);
  }

  // Support royalty info - See {EIP-2981}: https://eips.ethereum.org/EIPS/eip-2981
  function royaltyInfo(uint256, uint256 _salePrice)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
  {
    return (royaltyAddress, (_salePrice * royaltyBasisPoints) / 1000);
  }

  function tokenURI(uint256 _tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(_exists(_tokenId));
    return string(abi.encodePacked(_baseURI(), _tokenId.toString(), '.json'));
  }

  // Contract metadata URI - Support for OpenSea: https://docs.opensea.io/docs/contract-level-metadata
  function contractURI() public view returns (string memory) {
    return string(abi.encodePacked(_baseURI(), 'contract.json'));
  }

  // Override supportsInterface - See {IERC165-supportsInterface}
  function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override(ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(_interfaceId);
  }

  function getLastMintedTokenId() external view returns (uint256) {
    return _ids.current();
  }

  function doesTokenExist(uint256 _tokenId) external view returns (bool) {
    return _exists(_tokenId);
  }

  function setRoyaltyAddress(address _address) external onlyOwner {
    royaltyAddress = _address;
    emit SetRoyaltyAddress(_address);
  }

  function setRoyaltyBasisPoints(uint256 _points) external onlyOwner {
    royaltyBasisPoints = _points;
    emit SetRoyaltyBasisPoints(_points);
  }

  function setBaseURI(string memory _uri) external onlyOwner {
    baseTokenURI = _uri;
    emit SetBaseTokenURI(_uri);
  }

  function setPerpetualFutures(address _otc) external onlyOwner {
    overTheCounter = _otc;
  }

  function getAllUserOwned(address _user)
    external
    view
    returns (uint256[] memory)
  {
    return allUserOwned[_user];
  }

  function _baseURI() internal view override returns (string memory) {
    return baseTokenURI;
  }

  function _afterTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal virtual override(ERC721) {
    // if from == address(0), token is being minted
    if (_from != address(0)) {
      uint256 _currIndex = ownedIndex[_tokenId];
      uint256 _tokenIdMovingIndices = allUserOwned[_from][
        allUserOwned[_from].length - 1
      ];
      allUserOwned[_from][_currIndex] = allUserOwned[_from][
        allUserOwned[_from].length - 1
      ];
      allUserOwned[_from].pop();
      ownedIndex[_tokenIdMovingIndices] = _currIndex;
    }

    // if to == address(0), token is being burned
    if (_to != address(0)) {
      ownedIndex[_tokenId] = allUserOwned[_to].length;
      allUserOwned[_to].push(_tokenId);
    }

    // if this package is just moving wallets, turn off trading
    // so the new wallet can control if/when they would like to trade
    if (_from != address(0) && _to != address(0)) {
      IOverTheCounterSlim(overTheCounter).turnOffPackageTrading(_tokenId);
    }

    super._afterTokenTransfer(_from, _to, _tokenId);
  }
}

