// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";

/* 

      _____________________________________
     |                                     |
     |                  The                |
     |               ARBIDUDES             |
     |             Dutch Auction           |
     |      https://www.arbidudes.xyz/     |
     |          Twitter: @ArbiDudes        |
     |_____________________________________|


//////////////////////////////////////////////////
/////////////@@@@@@@@@@@//////////////////////////
/////////@@@@@@@@@@@@@@@@@////////////////////////
///////@@@@@@@@@@@@@@@@@@@@@//////////////////////
/////@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@///////
/////@@......@@@@@@/...................//////@@///
/////@@..........@@/...................//////@@///
/////@@....@@@@...............@@@@.....//////@@///
/////&&....@@@@...............@@@@.....//////&&///
/////@@....@@@@...............@@@@.....//////@@///
/////@@..****...................*****..//////@@///
/////@@....@@@@@@@@@@@@@@@@@@@@@.......//////@@///
/////@&................................//////@&///
/////@@......@@@@@@/...................//////@@///
/////@@..............................////////@@///
/////@@..............................////////@@///
/////&&...........................///////////&&///
///////@&//.....................///////////@@/////
/////////@@////////,......///////////////@@///////
///////////@@@@......./////////////////@&@@///////

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

contract ArbiDudesDutchAuction is Pausable, Ownable, ReentrancyGuard {
  IArbiDudesGenOne public dudesContract;

  uint256 private _auctionStartedAt;
  uint256 private _auctionMaxPrice;
  uint256 private _maxMintAmount = 20;
  mapping(uint256 => bool) private allowedAuctionMaxPrices;

  bool public isAuctionMode;
  uint256 public minDudesMintableMultiple;
  uint256 public mintableMultiplePrice;
  uint256 public mintableMultiplePriceStart; // When mintable multiple is allowed

  event AuctionEnded(uint256 indexed tokenId, address indexed owner);
  event AuctionPaused(uint256 indexed tokenId);
  event AuctionUnpaused(uint256 indexed tokenId);
  event ModeAuctionOn();
  event ModeClassicOn();

  constructor(IArbiDudesGenOne arbiDudes) {
    setDudesContract(arbiDudes);
    setMinDudesMintableMultiple(5);
    setMintableMultiplePrice(50000000000000000); //0.05 ETH
    setMintableMultiplePriceStart(70000000000000000); //0.07 ETH
    isAuctionMode = true;

    // Auction max prices
    allowedAuctionMaxPrices[2000000000000000000] = true;
    allowedAuctionMaxPrices[1000000000000000000] = true;
    allowedAuctionMaxPrices[500000000000000000] = true;
    allowedAuctionMaxPrices[100000000000000000] = true;
    allowedAuctionMaxPrices[50000000000000000] = true;
    allowedAuctionMaxPrices[20000000000000000] = true;
    allowedAuctionMaxPrices[15000000000000000] = true;
    allowedAuctionMaxPrices[10000000000000000] = true;
    allowedAuctionMaxPrices[0] = true;

    setAuctionMaxPrice(2000000000000000000); //2 ETH
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
    dudesContract.ownerClaimMultiple(amount, to);
  }

  // Dutch auction

  function auctionMode(bool auctionOn) public onlyOwner {
    require(auctionOn != isAuctionMode, "This mode is currently active");

    isAuctionMode = auctionOn;

    if (auctionOn) {
      // Turn On Auction - Stop Classic mode
      setMinDudesMintableMultiple(5);
      setMintableMultiplePrice(50000000000000000); // 0'05ETH
      setMintableMultiplePriceStart(70000000000000000); // 0'07ETH
      unpause();
      emit ModeAuctionOn();
    } else {
      // Turn off Auction - Start Classic mode
      pause();
      setMinDudesMintableMultiple(1);
      setMintableMultiplePrice(50000000000000000); // 0'05ETH
      setMintableMultiplePriceStart(0);
      emit ModeClassicOn();
    }
  }

  function setMinDudesMintableMultiple(uint256 minDudes) public onlyOwner {
    minDudesMintableMultiple = minDudes;
  }

  function setAuctionMaxPrice(uint256 maxPrice) public onlyOwner {
    require(allowedAuctionMaxPrices[maxPrice], "The price set is not allowed");
    _auctionMaxPrice = maxPrice;
  }

  function setMintableMultiplePrice(uint256 mulPrice) public onlyOwner {
    mintableMultiplePrice = mulPrice;
  }

  function setMintableMultiplePriceStart(uint256 mulPrice) public onlyOwner {
    mintableMultiplePriceStart = mulPrice;
  }

  function mint(uint256 _tokenId) public payable whenNotPaused nonReentrant {
    uint256 currentTokenId = getCurrentTokenId();
    require(_tokenId == currentTokenId, "Id already minted or wrong");
    require(msg.value >= mintPrice(), "Price not met");

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

    // Mint auction price must match this price
    if (mintableMultiplePriceStart > 0) {
      require(
        mintPrice() <= mintableMultiplePriceStart,
        "The auction did not reach the target price yet"
      );
    }

    handleMint(_num, _msgSender());
  }

  function handleMint(uint256 num, address to) private {
    if (isAuctionMode) {
      emit AuctionEnded(getCurrentTokenId() + num - 1, to);
      handleRestartAuction();
    }
    dudesContract.ownerClaimMultiple(num, to);
  }

  function handleRestartAuction() private {
    _auctionStartedAt = block.timestamp;
  }

  function secondsSinceAuctionStart() public view returns (uint256) {
    return (block.timestamp - _auctionStartedAt);
  }

  function mintPrice() public view returns (uint256) {
    return mintPriceSince(secondsSinceAuctionStart(), _auctionMaxPrice);
  }

  function offsetTimeForMaxPrice(uint256 maxPrice)
    private
    pure
    returns (uint256)
  {
    if (maxPrice == 2000000000000000000) return 0;
    if (maxPrice == 1000000000000000000) return 300;
    if (maxPrice == 500000000000000000) return 600;
    if (maxPrice == 100000000000000000) return 900;
    if (maxPrice == 50000000000000000) return 1200;
    if (maxPrice == 20000000000000000) return 2100;
    if (maxPrice == 15000000000000000) return 2400;
    if (maxPrice == 10000000000000000) return 3000;
    if (maxPrice == 0) return 3600;

    return 0;
  }

  function upper(uint256 num, uint256 bound) private pure returns (uint256) {
    if (num > bound) return bound;
    return num;
  }

  function safeSub(uint256 a, uint256 b) private pure returns (uint256) {
    if (a > b) return a - b;
    return 0;
  }

  function mintPriceSince(uint256 secondsAuction, uint256 maxPrice)
    public
    pure
    returns (uint256)
  {
    uint256 exponent = 5;
    uint256 offsetTime = offsetTimeForMaxPrice(maxPrice);

    if (secondsAuction < safeSub(300, offsetTime)) {
      // 1h - 55m // first 5 min - from 2 to 1
      return
        upper(
          (2 * 10**exponent - ((secondsAuction * 10**exponent) / 300)) *
            10**(18 - exponent),
          2000000000000000000
        );
    }

    if (secondsAuction < safeSub(600, offsetTime)) {
      // 55m - 50m // from 1 to 0,5
      // y = b + mx
      // price = 1.5 - (0.5/300)secondsAuction
      return
        upper(
          ((15 * 10**exponent) - ((secondsAuction * 5 * 10**exponent) / 300)) *
            10**(18 - exponent - 1),
          1000000000000000000
        );
    }

    if (secondsAuction < safeSub(900, offsetTime)) {
      // 50m - 45m // from 0,5 to 0,1
      // price = 1,3 - (4/300)secondsAuction

      return
        upper(
          ((13 * 10**exponent) -
            ((secondsAuction * 40 * 10**exponent) / 3000)) *
            10**(18 - exponent - 1),
          500000000000000000
        );
    }

    if (secondsAuction < safeSub(1200, offsetTime)) {
      // 45m - 40m // from 0,1 to 0,05
      // price = 0,25 - (0,05/300)secondsAuction
      return
        upper(
          ((25 * 10**(exponent - 1)) -
            ((secondsAuction * 5 * 10**(exponent - 1)) / 300)) *
            10**(18 - exponent - 1),
          100000000000000000
        );
    }

    if (secondsAuction < safeSub(2100, offsetTime)) {
      // 40m - 25m // from 0,05 to 0,02
      // price = 0,09 - (0,01/300)secondsAuction
      return
        upper(
          ((9 * 10**(exponent - 2)) -
            ((secondsAuction * 10**(exponent - 2)) / 300)) *
            10**(18 - exponent),
          50000000000000000
        );
    }

    if (secondsAuction < safeSub(2400, offsetTime)) {
      // 25m - 20m // from 0,02 to 0'015
      // price = 0,055 - (0,005/300)secondsAuction
      return
        upper(
          ((55 * 10**(exponent - 2)) -
            ((secondsAuction * 5 * 10**(exponent - 2)) / 300)) *
            10**(18 - exponent - 1),
          20000000000000000
        );
    }

    if (secondsAuction < safeSub(3000, offsetTime)) {
      // 20m - 10m // from 0,015 to 0,01
      // price = 0,035 - (0,005/600)secondsAuction
      return
        upper(
          ((35 * 10**(exponent - 2)) -
            ((secondsAuction * 5 * 10**(exponent - 2)) / 600)) *
            10**(18 - exponent - 1),
          15000000000000000
        );
    }

    if (secondsAuction < safeSub(3600, offsetTime)) {
      // 10m - 0m // from 0,01 to 0
      // price = 0,06 - (0,001/600)secondsAuction
      return
        upper(
          ((6 * 10**(exponent - 2)) -
            ((secondsAuction * 1 * 10**(exponent - 2)) / 600)) *
            10**(18 - exponent),
          10000000000000000
        );
    }

    return 0; // after 1h
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

