// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./ECDSA.sol";

/* 

      _____________________________________
     |                                     |
     |                  The                |
     |               ARBIDUDES             |
     |             Dutch Auction           |
     |                  v2                 |
     |      https://www.arbidudes.xyz/     |
     |          Twitter: @ArbiDudes        |
     |_____________________________________|

(((((((((((((((((((((((((((((((((((((((((((((((((((((
((((((((((((((@@@@@@@@@@@((((((((((((((((((((((((((((
((((((((((@@@@@@@@@@@@@@@@@((((((((((((((((((((((((((
(((((((@@@@@@@@@@@@@@@@@@@@@@@(((((((((((((((((((((((
(((((@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@((((((((
(((((&&.........@@@@@@@..................//////&&&(((
(((((&&..............@@..................//////&&&(((
(((((&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(((
(((((&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(((
(((((&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//////&&&(((
(((((&&@@@@@@@@@@@@@@..@@@@@@@@@@@@@@@@@@//////&&&(((
(((((&&...@@@@@@@@(......@@@@@@@@@@@@@(..//////&&&(((
(((((&&..................................//////&&&(((
(((((&&...........(@@@@@@@@@@@...........//////&&&(((
(((((&&................................////////&&&(((
(((((&&................................////////&&&(((
(((((&&.............................///////////&&&(((
(((((&&///........................../////////&&((((((
(((((((&&&//......................///////////&&((((((
((((((((((&&////...........////////////////&&((((((((
((((((((((((&&///////////////////////////&&&&((((((((


*/

interface IArbiDudesGenOne {
  function getCurrentTokenId() external view returns (uint256);

  function setPublicPrice(uint256 newPrice) external;

  function setChangeNamePrice(uint256 newPrice) external;

  function setChatPrice(uint256 newPrice) external;

  function setMaxGiveawayTokenId(uint256 _newMaxToken) external;

  function pause() external;

  function unpause() external;

  function setBaseURI(string memory newBaseURI) external;

  function ownerClaimMultiple(uint256 amount, address to) external;

  function ownerWithdraw() external;

  function renounceOwnership() external;

  function transferOwnership(address newOwner) external;
}

contract ArbiDudesDutchAuctionV2 is
  Pausable,
  Ownable,
  ReentrancyGuard,
  AccessControl
{
  IArbiDudesGenOne public dudesContract;

  uint256 private _maxMintAmount = 20;
  uint256 private _auctionStartedAt;

  bool public isAuctionMode;
  uint256 public minDudesMintableMultiple;
  uint256 public mintableMultiplePrice;
  bool private _requireSignature;
  address private _d;

  event AuctionEnded(uint256 indexed tokenId, address indexed owner);
  event AuctionPaused(uint256 indexed tokenId);
  event AuctionUnpaused(uint256 indexed tokenId);
  event ModeAuctionOn();
  event ModeClassicOn();

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  constructor() {
    setMinDudesMintableMultiple(5);
    setMintableMultiplePrice(50000000000000000); //0.05 ETH
    isAuctionMode = true;
    _requireSignature = true;
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    _auctionStartedAt = block.timestamp;
  }

  function setDudesContract(IArbiDudesGenOne arbiDudes) public onlyOwner {
    dudesContract = arbiDudes;
  }

  function getCurrentTokenId() public view returns (uint256) {
    return dudesContract.getCurrentTokenId();
  }

  function getAuctionStartedAt() public view returns (uint256) {
    return _auctionStartedAt;
  }

  function setDudesPublicPrice(uint256 newPrice) public onlyOwner {
    dudesContract.setPublicPrice(newPrice);
  }

  function setDudesChangeNamePrice(uint256 newPrice) public onlyOwner {
    dudesContract.setChangeNamePrice(newPrice);
  }

  function setDudesChatPrice(uint256 newPrice) public onlyOwner {
    dudesContract.setChatPrice(newPrice);
  }

  function setDudesMaxGiveawayTokenId(uint256 _newMaxToken) public onlyOwner {
    dudesContract.setMaxGiveawayTokenId(_newMaxToken);
  }

  function ownerDudesWithdraw() external onlyOwner {
    dudesContract.ownerWithdraw();
  }

  function dudesPause() public onlyOwner {
    dudesContract.pause();
  }

  function dudesUnpause() public onlyOwner {
    dudesContract.unpause();
  }

  function setDudesBaseURI(string memory newBaseURI) public onlyOwner {
    dudesContract.setBaseURI(newBaseURI);
  }

  function dudesRenounceOwnership() public virtual onlyOwner {
    dudesContract.renounceOwnership();
  }

  function dudesTransferOwnership(address newOwner) public virtual onlyOwner {
    dudesContract.transferOwnership(newOwner);
  }

  // Allow the owner to claim any amount of NFTs and direct them to another address.
  function dudesOwnerClaimMultiple(uint256 amount, address to)
    public
    nonReentrant
    onlyOwner
  {
    handleMint(amount, to);
  }

  // Dutch auction

  function handleRestartAuction() private {
    _auctionStartedAt = block.timestamp;
  }

  function auctionMode(bool auctionOn) public onlyOwner {
    require(auctionOn != isAuctionMode, "This mode is currently active");

    isAuctionMode = auctionOn;

    if (auctionOn) {
      // Turn On Auction - Stop Classic mode
      setMinDudesMintableMultiple(5);
      setMintableMultiplePrice(50000000000000000); // 0'05ETH
      unpause();
      emit ModeAuctionOn();
    } else {
      // Turn off Auction - Start Classic mode
      pause();
      setMinDudesMintableMultiple(1);
      setMintableMultiplePrice(50000000000000000); // 0'05ETH
      emit ModeClassicOn();
    }
  }

  function setD(address d) public onlyOwner {
    _d = d;
  }

  function setMinter(address m) public onlyOwner {
    grantRole(MINTER_ROLE, m);
  }

  function setRequireSignature(bool requireSignature) public onlyOwner {
    _requireSignature = requireSignature;
  }

  function setMinDudesMintableMultiple(uint256 minDudes) public onlyOwner {
    minDudesMintableMultiple = minDudes;
  }

  function setMintableMultiplePrice(uint256 mulPrice) public onlyOwner {
    mintableMultiplePrice = mulPrice;
  }

  function mint(
    uint256 _tokenId,
    uint256 _price,
    bytes32 hash,
    bytes memory signature
  ) public payable whenNotPaused nonReentrant {
    uint256 currentTokenId = getCurrentTokenId();
    require(_tokenId == currentTokenId, "Id already minted or wrong");
    require(msg.value >= _price, "Ether sent is not enough");
    if (_requireSignature) {
      require(
        hash ==
          keccak256(abi.encode(msg.sender, _tokenId, address(this), _price)),
        "Invalid hash"
      );
      require(
        ECDSA.recover(ECDSA.toEthSignedMessageHash(hash), signature) == _d,
        "Invalid signature"
      );
    } else {
      // If not signature required we need to use the mintMultiple method
      require(false, "Method not available");
    }

    handleMint(1, _msgSender());
  }

  function mintMultiple(uint256 _num) public payable nonReentrant {
    require(minDudesMintableMultiple > 0, "Mint multiple not allowed");
    require(_num >= minDudesMintableMultiple, "Minimum tokens not met");
    require(_num <= _maxMintAmount, "You can mint a max of 20 dudes");
    require(
      msg.value >= mintableMultiplePrice * _num,
      "Ether sent is not enough"
    );

    handleMint(_num, _msgSender());
  }

  function minterRoleMint(uint256 _num, address to)
    public
    nonReentrant
    onlyRole(MINTER_ROLE)
  {
    handleMint(_num, to);
  }

  function handleMint(uint256 num, address to) private {
    if (isAuctionMode) {
      emit AuctionEnded(getCurrentTokenId() + num - 1, to);
      handleRestartAuction();
    }
    dudesContract.ownerClaimMultiple(num, to);
  }

  function ownerWithdraw() external onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }

  function pause() public onlyOwner {
    _pause();
    emit AuctionPaused(getCurrentTokenId());
  }

  function unpause() public onlyOwner {
    handleRestartAuction();
    _unpause();
    emit AuctionUnpaused(getCurrentTokenId());
  }

  receive() external payable {
    //
  }
}

