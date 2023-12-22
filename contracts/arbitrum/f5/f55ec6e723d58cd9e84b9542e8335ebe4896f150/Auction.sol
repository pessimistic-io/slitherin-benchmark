// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {ERC721Upgradeable} from "./ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IPoolFactory} from "./IPoolFactory.sol";
import {IPoolMaster} from "./IPoolMaster.sol";
import {IAuction} from "./IAuction.sol";
import {Decimal} from "./Decimal.sol";

/// @notice This contract is responsible for processing pool default auctions
contract Auction is IAuction, ERC721Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using Decimal for uint256;

  /// @notice PoolFactory contract
  IPoolFactory public factory;

  /// @notice Debt auction duration (in seconds)
  uint256 public auctionDuration;

  /// @notice Minimal ratio of initial bid to pool insurance (as 18-digit decimal)
  uint256 public minBidFactor;

  /// @notice Mapping of addresses to flags if they are whitelisted bidders
  mapping(address => bool) public isWhitelistedBidder;

  /// @notice Structure storing information about auction for some pool
  struct AuctionInfo {
    uint96 tokenId;
    address lastBidder;
    uint256 lastBid;
    uint256 lastBlock;
    uint256 start;
    uint256 end;
    uint256 incrementalAmount;
  }

  /// @notice Mapping of pool addresses to their debt auction info
  mapping(address => AuctionInfo) public auctionInfo;

  /// @notice Structure storing details of some token, representint pool debt
  struct TokenInfo {
    address pool;
    uint256 borrowsAtClaim;
    uint256 interestRate;
  }

  /// @notice Mapping of token IDs to their token info
  mapping(uint256 => TokenInfo) public tokenInfo;

  /// @notice Last debt token ID
  uint96 public lastTokenId;

  struct AuctionIncrementInfo {
    uint256 percent;
    uint256 maxAmount;
  }
  AuctionIncrementInfo public bidIncrementInfo;

  // EVENTS

  /// @notice Event emitted when debt auction is started for some pool
  /// @param pool Address of the pool
  /// @param bidder Account who initiated auction by placing first bid
  event AuctionStarted(address indexed pool, address indexed bidder);

  /// @notice Event emitted when bid is placed for some pool
  /// @param pool Address of the pool
  /// @param bidder Account who made bid
  /// @param amount Amount of the bid in pool's currency
  event Bid(address indexed pool, address indexed bidder, uint256 amount);

  /// @notice Event emitted when some address status as whitelisted bidder is changed
  /// @param bidder Account who's status was changed
  /// @param whitelisted True if account was whitelisted, false otherwise
  event WhitelistedBidderSet(address bidder, bool whitelisted);

  /// @notice Event emitted when auction duration is set
  /// @param duration New auction duration in seconds
  event AuctionDurationSet(uint256 duration);

  /// @notice Event emitted when auction is resolved
  /// @param pool Address of the pool
  /// @param resolution True if auction was resolved, false otherwise
  /// @param winner Account who won the auction
  event AuctionResolved(address pool, bool resolution, address winner);

  /// @notice Event emitted when auction `bidIncrementInfo.percent` is changed
  /// @param percent Value of incremental percent in mantissa
  event BidIncrementalPercentChanged(uint256 percent);

  /// @notice Event emitted when auction `bidIncrementInfo.maxAmount` is changed
  /// @param maxAmount Value of incremental max amount
  event BidIncrementalMaxAmountChanged(uint256 maxAmount);

  // CONSTRUCTOR

  /// @notice Upgradeable contract constructor
  /// @param factory_ Address of the PoolFactory
  /// @param auctionDuration_ Auction duration value
  /// @param minBidFactor_ Min bid factor value
  /// @param incrementInfo_ Increment info
  function initialize(
    address factory_,
    uint256 auctionDuration_,
    uint256 minBidFactor_,
    AuctionIncrementInfo calldata incrementInfo_
  ) external initializer {
    require(
      (incrementInfo_.percent >= 1e16 && incrementInfo_.percent <= 1e18) &&
        incrementInfo_.maxAmount != 0,
      'IVL'
    ); // 1% - 100%

    __Ownable_init();
    __ERC721_init('Clearpool Debt', 'CPDEBT');
    __ReentrancyGuard_init();

    factory = IPoolFactory(factory_);
    auctionDuration = auctionDuration_;
    minBidFactor = minBidFactor_;
    bidIncrementInfo = incrementInfo_;
  }

  // PUBLIC FUNCTIONS

  /// @notice Makes a bid on a pool
  /// @param pool Address of a pool
  /// @param amount Amount of the bid
  function bid(
    address pool,
    uint256 amount
  ) external nonReentrant checkBidder(pool) onlyPoolAddr(pool) {
    AuctionInfo storage currentAuction = auctionInfo[pool];

    require(amount > currentAuction.lastBid, 'NBG');
    require(currentAuction.lastBidder != msg.sender, 'COY');

    IERC20Upgradeable currency = IERC20Upgradeable(IPoolMaster(pool).currency());

    // If no bids available yet, start the auction
    if (currentAuction.lastBidder == address(0)) {
      _startAuction(pool, amount);
    } else {
      currency.safeTransfer(currentAuction.lastBidder, currentAuction.lastBid);
      require(block.timestamp < currentAuction.end, 'AF');
      require(amount >= currentAuction.lastBid + currentAuction.incrementalAmount, 'LBA');
    }

    currency.safeTransferFrom(msg.sender, address(this), amount);

    if (currentAuction.end - block.timestamp <= 12 hours) {
      currentAuction.end += 1 days;
    }

    currentAuction.lastBidder = msg.sender;
    (currentAuction.lastBid, currentAuction.lastBlock) = (amount, block.number);

    emit Bid(pool, msg.sender, amount);
  }

  /// @notice Increases bid on a pool
  /// @param pool Address of a pool
  /// @param amount Amount to add
  function increaseBid(
    address pool,
    uint256 amount
  ) external nonReentrant onActiveAuction(pool) checkBidder(pool) onlyPoolAddr(pool) {
    AuctionInfo storage currentAuction = auctionInfo[pool];

    require(amount != 0, 'ZAM');

    IERC20Upgradeable currency = IERC20Upgradeable(IPoolMaster(pool).currency());

    if (msg.sender == currentAuction.lastBidder) {
      require(amount >= currentAuction.incrementalAmount, 'LBA');
      currency.safeTransferFrom(msg.sender, address(this), amount);

      currentAuction.lastBid += amount;
      currentAuction.lastBlock = block.number;

      if (currentAuction.end - block.timestamp <= 12 hours) {
        currentAuction.end += 1 days;
      }

      emit Bid(pool, msg.sender, currentAuction.lastBid);
    } else {
      revert('NBD');
    }
  }

  /// @notice Resolves auction in case there is no goverment decision for 10 days
  /// @param pool Address of a pool
  function resolveAuctionWithoutGoverment(address pool) external nonReentrant {
    AuctionInfo storage currentAuction = auctionInfo[pool];

    require(currentAuction.tokenId == 0, 'AC');
    require(currentAuction.end != 0, 'NAE');
    require(block.timestamp >= currentAuction.end, 'ANF');
    require(block.timestamp - currentAuction.end >= 10 days, 'TNP');

    IERC20Upgradeable currency = IERC20Upgradeable(IPoolMaster(pool).currency());

    currency.safeTransfer(currentAuction.lastBidder, currentAuction.lastBid);

    delete auctionInfo[pool];
    auctionInfo[pool].tokenId = type(uint96).max;

    IPoolMaster(pool).processDebtClaim();

    emit AuctionResolved(pool, false, address(0));
  }

  // RESTRICTED FUNCTIONS

  /// @notice Resolves auction after it's end - accepts or rejects winning bid
  /// @param pool Address of a pool
  /// @param resolution True to accept, false to reject
  function resolveAuction(address pool, bool resolution) external nonReentrant onlyOwner {
    AuctionInfo storage currentAuction = auctionInfo[pool];

    require(block.timestamp >= currentAuction.end, 'ANF');

    require(currentAuction.lastBidder != address(0), 'NAE');
    require(currentAuction.tokenId == 0, 'AC');

    IERC20Upgradeable currency = IERC20Upgradeable(IPoolMaster(pool).currency());

    if (resolution) {
      // In case of acceptance, mint debt NFT and transfer bid to the pool
      lastTokenId++;

      tokenInfo[lastTokenId] = TokenInfo({
        pool: pool,
        borrowsAtClaim: IPoolMaster(pool).borrows(),
        interestRate: IPoolMaster(pool).getBorrowRate()
      });
      currentAuction.tokenId = lastTokenId;

      currency.safeTransfer(pool, currentAuction.lastBid);
      _mint(auctionInfo[pool].lastBidder, lastTokenId);

      emit AuctionResolved(pool, resolution, auctionInfo[pool].lastBidder);
    } else {
      // In case of rejection, distribute remaining cash between lenders and refund bids
      currency.safeTransfer(currentAuction.lastBidder, currentAuction.lastBid);
      delete auctionInfo[pool];

      auctionInfo[pool].tokenId = type(uint96).max;
      emit AuctionResolved(pool, resolution, address(0));
    }
    IPoolMaster(pool).processDebtClaim();
  }

  /// @notice Function is used to set whitelisted status for some bidder (restricted to owner)
  /// @param bidder Address of the bidder
  /// @param whitelisted True if bidder should be whitelisted false otherwise
  function setWhitelistedBidder(address bidder, bool whitelisted) external onlyOwner {
    isWhitelistedBidder[bidder] = whitelisted;
    emit WhitelistedBidderSet(bidder, whitelisted);
  }

  /// @notice Function is used to set new value for auction duration
  /// @param auctionDuration_ Auction duration in seconds
  function setAuctionDuration(uint256 auctionDuration_) external onlyOwner {
    auctionDuration = auctionDuration_;
    emit AuctionDurationSet(auctionDuration_);
  }

  /// @notice Function is used to set new value for bid incremental percent
  /// @param bidIncrementalPercent_ Percent value in mantissa
  function setBidIncrementalPercent(uint256 bidIncrementalPercent_) external onlyOwner {
    require(bidIncrementalPercent_ >= 1e16 && bidIncrementalPercent_ <= 1e18, 'IVL'); // 1% - 100%
    bidIncrementInfo.percent = bidIncrementalPercent_;
    emit BidIncrementalPercentChanged(bidIncrementalPercent_);
  }

  /// @notice Function is used to set new value for bid incremental max amount
  /// @param bidIncrementMaxAmount_ value
  function setBidIncrementalMaxAmount(uint256 bidIncrementMaxAmount_) external onlyOwner {
    require(bidIncrementMaxAmount_ != 0, 'IVL');
    bidIncrementInfo.maxAmount = bidIncrementMaxAmount_;
    emit BidIncrementalMaxAmountChanged(bidIncrementMaxAmount_);
  }

  // VIEW FUNCTIONS

  /// @notice Returns owner of a debt
  /// @param pool Address of a pool
  /// @return Address of the owner
  function ownerOfDebt(address pool) external view returns (address) {
    uint96 tokenId = auctionInfo[pool].tokenId;
    return
      (tokenId != 0 && tokenId != type(uint96).max)
        ? ownerOf(auctionInfo[pool].tokenId)
        : address(0);
  }

  /// @notice Returns state of a pool auction
  /// @param pool Address of a pool
  /// @return state of a pool auction
  function state(address pool) external view returns (State) {
    if (IPoolMaster(pool).state() != IPoolMaster.State.Default) {
      return State.None;
    } else if (auctionInfo[pool].lastBidder == address(0)) {
      return State.NotStarted;
    } else if (block.timestamp < auctionInfo[pool].end) {
      return State.Active;
    } else if (block.timestamp >= auctionInfo[pool].end && auctionInfo[pool].tokenId == 0) {
      return State.Finished;
    } else {
      return State.Closed;
    }
  }

  // PRIVATE FUNCTIONS

  /// @notice Private function that starts auction for a pool
  /// @param poolAddress Address of the pool
  /// @param amount Amount of the initial bid
  function _startAuction(address poolAddress, uint256 amount) private {
    IPoolMaster pool = IPoolMaster(poolAddress);

    require(pool.state() == IPoolMaster.State.Default, 'NID');
    require(amount >= pool.insurance().mulDecimal(minBidFactor), 'LMB');

    AuctionInfo storage info = auctionInfo[poolAddress];

    pool.processAuctionStart();
    uint256 poolDecimals = pool.decimals(); // e.g. 6 for USDC
    uint256 maxAmount = bidIncrementInfo.maxAmount; // is in 18 decimals

    uint256 weiPoolSize = toWei(pool.poolSize(), poolDecimals); // 18 decimals amount
    uint256 incrementalAmount = weiPoolSize.mulDecimal(bidIncrementInfo.percent);
    if (incrementalAmount > maxAmount) {
      info.incrementalAmount = fromWei(maxAmount, poolDecimals);
    } else {
      info.incrementalAmount = fromWei(incrementalAmount, poolDecimals);
    }

    info.start = block.timestamp;
    info.end = block.timestamp + auctionDuration;

    emit AuctionStarted(poolAddress, msg.sender);
  }

  function toWei(uint256 amount_, uint256 decimals) internal pure returns (uint256) {
    return amount_ * 10 ** (18 - decimals);
  }

  function fromWei(uint256 amount_, uint256 decimals) internal pure returns (uint256) {
    return amount_ / 10 ** (18 - decimals);
  }

  modifier onActiveAuction(address pool) {
    require(block.timestamp < auctionInfo[pool].end, 'AF');
    _;
  }

  modifier onlyPoolAddr(address pool) {
    require(factory.isPool(pool), 'PNE');
    _;
  }

  modifier checkBidder(address pool) {
    require(msg.sender != IPoolMaster(pool).manager(), 'NPM');
    require(isWhitelistedBidder[msg.sender], 'NWB');
    _;
  }
}

