// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IOptionScalp} from "./IOptionScalp.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";

import {ScalpLP} from "./ScalpLP.sol";

import {OptionScalp} from "./OptionScalp.sol";
import {ScalpPositionMinter} from "./ScalpPositionMinter.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC721} from "./IERC721.sol";
import {ERC721Holder} from "./ERC721Holder.sol";
import {Ownable} from "./Ownable.sol";

import {Pausable} from "./Pausable.sol";

contract LimitOrderManager is Ownable, Pausable, ReentrancyGuard, ContractWhitelist, ERC721Holder {
    using SafeERC20 for IERC20;

    uint256 MAX = 2**256 - 1;

    int24 maxTickSpaceMultiplier = 100;

    uint256 public maxFundingTime = 1 hours;

    uint256 public fundingRate = 1825000000; // 18.25% annualized (0.002% per hour)

    // Used for percentages
    uint256 public constant divisor = 1e8;

    OptionScalp optionScalp;

    mapping (uint => OpenOrder) public openOrders; // identifier -> openOrder

    mapping (uint => CloseOrder) public closeOrders; // identifier -> closeOrder

    mapping(uint => uint) public closeOrderCreatedForPosition;

    IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    uint public openOrdersCount = 1;
    uint public closeOrdersCount = 1;

    // Create open order event
    event CreateOpenOrder(uint256 id, address indexed user);

    // Cancel open order event
    event CancelOpenOrder(uint256 id, address indexed user);

    // Create close order event
    event CreateCloseOrder(uint256 id, address indexed user);

    // Cancel close order event
    event CancelCloseOrder(uint256 id, address indexed user);

    // Emergency withdraw
    event EmergencyWithdraw(address indexed receiver);

    struct OpenOrder {
      address user;
      bool isShort;
      bool filled;
      bool cancelled;
      uint256 size;
      uint256 timeframeIndex;
      uint256 collateral;
      uint256 lockedLiquidity;
      uint256 nftPositionId;
      uint256 timestamp;
    }

    struct CloseOrder {
      bool filled;
      uint256 nftPositionId;
      uint256 scalpPositionId;
    }

    /// @notice Admin function to add an option scalp
    function attachOptionScalp(address _optionScalp) external onlyOwner {
      require(_optionScalp != address(0), "Invalid option scalp address");

      IERC20(OptionScalp(_optionScalp).quote()).safeApprove(_optionScalp, MAX);
      IERC20(OptionScalp(_optionScalp).base()).safeApprove(_optionScalp, MAX);
      optionScalp = OptionScalp(_optionScalp);
    }

    /// @notice Internal function to calc. amounts to deposit given a locked liquidity target
    /// @param lockedLiquidity Amount of target locked liquidity
    /// @param isShort If true the position will be a short
    /// @param tick0 Start tick of the position to create
    /// @param tick1 End tick of the position to create
    function calcAmounts(uint256 lockedLiquidity, bool isShort, int24 tick0, int24 tick1) internal view returns (address token0, address token1, uint256 amount0, uint256 amount1) {
          address base = address(optionScalp.base());
          address quote = address(optionScalp.quote());
          IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.getPool(base, quote, 500));
          token0 = pool.token0();
          token1 = pool.token1();

          int24 tickSpacing = pool.tickSpacing();
          (,int24 tick,,,,,) = pool.slot0();

          if (tick > tick0) require(tick - tick0 <= tickSpacing * maxTickSpaceMultiplier, "Price is too far");
          else require(tick0 - tick <= tickSpacing * maxTickSpaceMultiplier, "Price is too far");

          require(tick1 - tick0 == tickSpacing, "Invalid ticks");

          if (base == token0) {
              // amount0 is base
              // amount1 is quote
              if (isShort) amount0 = lockedLiquidity;
              else amount1 = lockedLiquidity;
          }  else {
              // amount0 is quote
              // amount1 is base
              if (isShort) amount1 = lockedLiquidity;
              else amount0 = lockedLiquidity;
          }
    }

    /// @notice Internal function to create a new Uniswap V3 position
    /// @param tick0 Start tick of the position to create
    /// @param tick1 End tick of the position to create
    /// @param amount Amount to deposit
    /// @param isShort If true the position will be a short
    function createPosition(int24 tick0, int24 tick1, uint256 amount, bool isShort) internal returns (uint256 nftPositionId) {
          (address token0, address token1, uint256 amount0, uint256 amount1) = calcAmounts(amount, isShort, tick0, tick1);

          nftPositionId = optionScalp.mintUniswapV3Position(
              token0,
              token1,
              tick0,
              tick1,
              amount0,
              amount1
          );
    }

    /// @notice Create a new OpenOrder
    /// @param isShort If true the position will be a short
    /// @param size Size of position (quoteDecimals)
    /// @param timeframeIndex Position of the array
    /// @param collateral Total collateral posted by user
    /// @param tick0 Start tick of the position to create
    /// @param tick1 End tick of the position to create
    function createOpenOrder(
      bool isShort,
      uint256 size,
      uint256 timeframeIndex,
      uint256 collateral, // margin + fees + premium
      int24 tick0,
      int24 tick1
    )
    nonReentrant
    external returns (uint256 orderId) {
      require(optionScalp.timeframes(timeframeIndex) != 0, "Invalid timeframe");
      require(collateral >= optionScalp.minimumMargin(), "Insufficient margin");
      require(size <= optionScalp.maxSize(), "Position exposure is too high");

      (optionScalp.quote()).safeTransferFrom(
          msg.sender,
          address(optionScalp),
          collateral
      );

      uint256 lockedLiquidity = isShort ? (10 ** optionScalp.baseDecimals()) * size / optionScalp.getMarkPrice() : size;

      (uint256 nftPositionId) = createPosition(
        tick0,
        tick1,
        lockedLiquidity,
        isShort
      );

      (isShort ? ScalpLP(optionScalp.baseLp()) : ScalpLP(optionScalp.quoteLp())).lockLiquidity(lockedLiquidity);

      orderId = openOrdersCount;

      openOrders[orderId] = OpenOrder({
        user: msg.sender,
        isShort: isShort,
        filled: false,
        cancelled: false,
        size: size,
        timeframeIndex: timeframeIndex,
        collateral: collateral,
        lockedLiquidity: lockedLiquidity,
        nftPositionId: nftPositionId,
        timestamp: block.timestamp
      });

      emit CreateOpenOrder(
        orderId,
        msg.sender
      );

      openOrdersCount++;
    }

    /// @notice Fill a OpenOrder
    /// @param _id ID of the OpenOrder
    function fillOpenOrder(uint _id)
    nonReentrant
    external {
      require(
        !openOrders[_id].filled &&
        !openOrders[_id].cancelled &&
        openOrders[_id].user != address(0),
        "Order is not active and unfilled"
      );

      IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.getPool(address(optionScalp.base()), address(optionScalp.quote()), 500));

      uint256 swapped = optionScalp.burnUniswapV3Position(
          pool,
          openOrders[_id].nftPositionId,
          openOrders[_id].isShort
      );

      uint256 id = optionScalp.openPositionFromLimitOrder(
          swapped,
          openOrders[_id].user,
          openOrders[_id].isShort,
          openOrders[_id].collateral,
          openOrders[_id].size,
          openOrders[_id].timeframeIndex,
          openOrders[_id].lockedLiquidity
      );

      openOrders[_id].filled = true;

      ScalpPositionMinter(optionScalp.scalpPositionMinter()).transferFrom(address(this), openOrders[_id].user, id);
    }

    /// @notice Create a CloseOrder
    /// @param scalpPositionId Scalp position id
    /// @param tick0 Start tick of the position to create
    /// @param tick1 End tick of the position to create
    function createCloseOrder(
        uint256 scalpPositionId,
        int24 tick0,
        int24 tick1
    )
    nonReentrant
    external returns (uint256 orderId) {
      OptionScalp.ScalpPosition memory scalpPosition = optionScalp.getPosition(scalpPositionId);
      address owner = optionScalp.positionOwner(scalpPositionId);
      require(msg.sender == owner, "Sender not authorized");
      require(closeOrderCreatedForPosition[scalpPositionId] == 0, "There is already an close order for this position");

      orderId = closeOrdersCount;

      closeOrderCreatedForPosition[scalpPositionId] = orderId;

      (uint256 nftPositionId) = createPosition(
        tick0,
        tick1,
        scalpPosition.amountOut,
        !scalpPosition.isShort
      );

      closeOrders[orderId] = CloseOrder({
        filled: false,
        nftPositionId: nftPositionId,
        scalpPositionId: scalpPositionId
      });

      closeOrdersCount++;

      emit CreateCloseOrder(
        orderId,
        owner
      );
    }

    /// @notice Fill a CloseOrder
    /// @param _id ID of the CloseOrder
    function fillCloseOrder(uint _id)
    nonReentrant
    public returns (bool) {

      CloseOrder memory order = closeOrders[_id];

      require(
        isCloseOrderActive(_id),
        "Order is not active and unfilled"
      );

      OptionScalp.ScalpPosition memory scalpPosition = optionScalp.getPosition(order.scalpPositionId);

      IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.getPool(address(optionScalp.base()), address(optionScalp.quote()), 500));

      uint256 swapped = optionScalp.burnUniswapV3Position(
          pool,
          closeOrders[_id].nftPositionId,
          !scalpPosition.isShort
      );

      optionScalp.closePositionFromLimitOrder(
          order.scalpPositionId,
          swapped
      );

      closeOrders[_id].filled = true;

      return true;
    }

    /// @notice Cancel OpenOrder
    /// @param _id ID of the OpenOrder
    function cancelOpenOrder(uint _id)
    nonReentrant
    external {
      require(
        !openOrders[_id].filled &&
        !openOrders[_id].cancelled,
        "Order is not active and unfilled"
      );

      if (openOrders[_id].timestamp + maxFundingTime > block.timestamp) require(msg.sender == openOrders[_id].user, "Only order creator can call cancel before expiry");
      openOrders[_id].cancelled = true;

      IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.getPool(address(optionScalp.base()), address(optionScalp.quote()), 500));

      optionScalp.burnUniswapV3Position(
          pool,
          openOrders[_id].nftPositionId,
          !openOrders[_id].isShort
      );

      uint256 fees = (openOrders[_id].collateral * fundingRate / divisor) / uint256(365 days);

      optionScalp.settleOpenOrderDeletion(openOrders[_id].user, openOrders[_id].isShort, openOrders[_id].collateral - fees, fees);

      (openOrders[_id].isShort ? ScalpLP(optionScalp.baseLp()) : ScalpLP(optionScalp.quoteLp())).unlockLiquidity(openOrders[_id].lockedLiquidity);

      emit CancelOpenOrder(_id, msg.sender);
    }

    /// @notice Cancel CloseOrder
    /// @param _id ID of the CloseOrder
    function cancelCloseOrder(uint _id)
    nonReentrant
    external {

      CloseOrder memory order = closeOrders[_id];

      require(
        isCloseOrderActive(_id),
        "Order is not active and unfilled"
      );

      require(msg.sender == optionScalp.positionOwner(order.scalpPositionId) || msg.sender == address(optionScalp), "Sender not authorized");

      OptionScalp.ScalpPosition memory scalpPosition = optionScalp.getPosition(order.scalpPositionId);

      IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.getPool(address(optionScalp.base()), address(optionScalp.quote()), 500));

      optionScalp.burnUniswapV3Position(
          pool,
          closeOrders[_id].nftPositionId,
          scalpPosition.isShort
      );

      delete closeOrders[_id];

      closeOrderCreatedForPosition[order.scalpPositionId] = 0;

      emit CancelCloseOrder(_id, msg.sender);
    }

    /// @notice Returns true is CloseOrder is active
    /// @param _id ID of the CloseOrder
    function isCloseOrderActive(uint256 _id) public view returns (bool) {
      CloseOrder memory order = closeOrders[_id];

      // Treat positions closed before limitOrder as inactive
      if(order.nftPositionId != 0) {
          if(!optionScalp.getPosition(order.scalpPositionId).isOpen) return false;
      }

      return !order.filled && order.nftPositionId != 0;
    }

    /// @notice Returns ticks of a valid nft position
    /// @param nftPositionId ID of the NFT
    function getNFTPositionTicks(uint256 nftPositionId) public view returns (int24 tickLower, int24 tickUpper) {
        (,,,,,tickLower, tickUpper,,,,,) = INonfungiblePositionManager(optionScalp.nonFungiblePositionManager()).positions(nftPositionId);
    }

    /// @notice Returns true if order can be filled
    /// @param id Open order ID
    function isOpenOrderFullFillable(uint256 id) public view returns (bool) {
        OpenOrder memory order = openOrders[id];

        if (order.filled || order.cancelled || block.timestamp > openOrders[id].timestamp + maxFundingTime) return false;

        (,,,,,int24 tickLower, int24 tickUpper,,,,,) = INonfungiblePositionManager(optionScalp.nonFungiblePositionManager()).positions(order.nftPositionId);
        address base = address(optionScalp.base());
        address quote = address(optionScalp.quote());
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.getPool(base, quote, 500));
        (,int24 tick,,,,,) = pool.slot0();

        return order.isShort ? tick > tickUpper : tick < tickLower;
    }

    /// @notice Returns true if can be filled
    /// @param id Close order ID
    function isCloseOrderFullFillable(uint256 id) public view returns (bool) {
        CloseOrder memory order = closeOrders[id];

        if (order.filled) return false;

        OptionScalp.ScalpPosition memory scalpPosition = optionScalp.getPosition(order.scalpPositionId);

        (,,,,,int24 tickLower, int24 tickUpper,,,,,) = INonfungiblePositionManager(optionScalp.nonFungiblePositionManager()).positions(order.nftPositionId);

        address base = address(optionScalp.base());
        address quote = address(optionScalp.quote());

        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.getPool(base, quote, 500));
        (,int24 tick,,,,,) = pool.slot0();

        return scalpPosition.isShort ? tick < tickLower : tick > tickUpper;
    }

    /// @notice Owner-only function to update config
    /// @param _maxTickSpaceMultiplier Configuration field which indicates how far limit orders prices can be compared to mark price
    /// @param _maxFundingTime Maximum duration of a OpenOrder
    /// @param _fundingRate funding apr paid by OpenOrder creator
    function updateConfig(int24 _maxTickSpaceMultiplier, uint256 _maxFundingTime, uint256 _fundingRate) public onlyOwner {
        maxTickSpaceMultiplier = _maxTickSpaceMultiplier;
        maxFundingTime = _maxFundingTime;
        fundingRate = _fundingRate;
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by the owner
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(
        address[] calldata tokens,
        bool transferNative
    ) external onlyOwner {
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        IERC20 token;

        for (uint256 i; i < tokens.length; ) {
            token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }

        emit EmergencyWithdraw(msg.sender);
    }

}
