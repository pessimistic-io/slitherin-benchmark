// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC165Storage.sol";
import "./Multicall.sol";
import "./ReentrancyGuard.sol";

import "./AuctionInternal.sol";
import "./IAuction.sol";

/**
 * @title Knox Dutch Auction Contract
 * @dev deployed standalone and referenced by AuctionProxy
 */

contract Auction is AuctionInternal, IAuction, Multicall, ReentrancyGuard {
    using ABDKMath64x64 for int128;
    using AuctionStorage for AuctionStorage.Layout;
    using EnumerableSet for EnumerableSet.UintSet;
    using ERC165Storage for ERC165Storage.Layout;
    using OrderBook for OrderBook.Index;
    using SafeERC20 for IERC20;

    int128 private constant ONE_64x64 = 0x10000000000000000;

    constructor(
        bool isCall,
        address pool,
        address vault,
        address weth
    ) AuctionInternal(isCall, pool, vault, weth) {}

    /************************************************
     *  ADMIN
     ***********************************************/

    /**
     * @inheritdoc IAuction
     */
    function setDeltaOffset64x64(int128 newDeltaOffset64x64)
        external
        onlyOwner
    {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        require(newDeltaOffset64x64 > 0, "delta <= 0");
        require(newDeltaOffset64x64 < ONE_64x64, "delta > 1");

        emit DeltaOffsetSet(
            l.deltaOffset64x64,
            newDeltaOffset64x64,
            msg.sender
        );

        l.deltaOffset64x64 = newDeltaOffset64x64;
    }

    /**
     * @inheritdoc IAuction
     */
    function setExchangeHelper(address newExchangeHelper) external onlyOwner {
        AuctionStorage.Layout storage l = AuctionStorage.layout();

        require(newExchangeHelper != address(0), "address not provided");
        require(
            newExchangeHelper != address(l.Exchange),
            "new address equals old"
        );

        emit ExchangeHelperSet(
            address(l.Exchange),
            newExchangeHelper,
            msg.sender
        );

        l.Exchange = IExchangeHelper(newExchangeHelper);
    }

    /**
     * @inheritdoc IAuction
     */
    function setMinSize(uint256 newMinSize) external onlyOwner {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        require(newMinSize > 0, "value exceeds minimum");
        emit MinSizeSet(l.minSize, newMinSize, msg.sender);
        l.minSize = newMinSize;
    }

    /**
     * @inheritdoc IAuction
     */
    function setPricer(address newPricer) external onlyOwner {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        require(newPricer != address(0), "address not provided");
        require(newPricer != address(l.Pricer), "new address equals old");
        emit PricerSet(address(l.Pricer), newPricer, msg.sender);
        l.Pricer = IPricer(newPricer);
    }

    /************************************************
     *  INITIALIZE AUCTION
     ***********************************************/

    /**
     * @inheritdoc IAuction
     */
    function initialize(AuctionStorage.InitAuction memory initAuction)
        external
        onlyVault
    {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[initAuction.epoch];

        require(
            auction.status == AuctionStorage.Status.UNINITIALIZED,
            "status != uninitialized"
        );

        if (
            initAuction.startTime >= initAuction.endTime ||
            block.timestamp > initAuction.startTime ||
            block.timestamp > initAuction.expiry ||
            initAuction.strike64x64 <= 0 ||
            initAuction.longTokenId <= 0
        ) {
            // the auction is cancelled if the start time is greater than or equal to
            // the end time, the current time is greater than the start time, or the
            // option parameters are invalid
            _cancel(l.auctions[initAuction.epoch], initAuction.epoch);
        } else {
            auction.expiry = initAuction.expiry;
            auction.strike64x64 = initAuction.strike64x64;
            auction.startTime = initAuction.startTime;
            auction.endTime = initAuction.endTime;
            auction.longTokenId = initAuction.longTokenId;

            _updateStatus(
                auction,
                AuctionStorage.Status.INITIALIZED,
                initAuction.epoch
            );
        }
    }

    /**
     * @inheritdoc IAuction
     */
    function setAuctionPrices(uint64 epoch) external {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        require(
            AuctionStorage.Status.INITIALIZED == auction.status,
            "status != initialized"
        );

        require(
            block.timestamp > auction.startTime - 30 minutes,
            "price set too early"
        );

        require(
            auction.minPrice64x64 <= 0 || auction.maxPrice64x64 <= 0,
            "prices are already set"
        );

        if (auction.startTime > block.timestamp) {
            int128 spot64x64;
            int128 timeToMaturity64x64;

            // fetches the spot price of the underlying
            try l.Pricer.latestAnswer64x64() returns (int128 _spot64x64) {
                spot64x64 = _spot64x64;
            } catch Error(string memory message) {
                emit Log(message);
                spot64x64 = 0;
            }

            // fetches the time to maturity of the option
            try l.Pricer.getTimeToMaturity64x64(auction.expiry) returns (
                int128 _timeToMaturity64x64
            ) {
                timeToMaturity64x64 = _timeToMaturity64x64;
            } catch Error(string memory message) {
                emit Log(message);
                timeToMaturity64x64 = 0;
            }

            if (spot64x64 > 0 && timeToMaturity64x64 > 0) {
                _setAuctionPrices(
                    l,
                    auction,
                    epoch,
                    spot64x64,
                    timeToMaturity64x64
                );
            }
        }

        _validateAuctionPrices(auction, epoch);
    }

    /************************************************
     *  PRICING
     ***********************************************/

    /**
     * @inheritdoc IAuction
     */
    function lastPrice64x64(uint64 epoch) external view returns (int128) {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];
        return _lastPrice64x64(auction);
    }

    /**
     * @inheritdoc IAuction
     */
    function priceCurve64x64(uint64 epoch) external view returns (int128) {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];
        return _priceCurve64x64(auction);
    }

    /**
     * @inheritdoc IAuction
     */
    function clearingPrice64x64(uint64 epoch) external view returns (int128) {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];
        return _clearingPrice64x64(auction);
    }

    /************************************************
     *  PURCHASE
     ***********************************************/

    /**
     * @inheritdoc IAuction
     */
    function addLimitOrder(
        uint64 epoch,
        int128 price64x64,
        uint256 size
    ) external payable nonReentrant {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        _limitOrdersAllowed(auction);

        uint256 cost = _validateLimitOrder(l, price64x64, size);
        uint256 credited = _wrapNativeToken(cost);
        // an approve() by the msg.sender is required beforehand
        ERC20.safeTransferFrom(msg.sender, address(this), cost - credited);
        _addOrder(l, auction, epoch, price64x64, size, true);
    }

    /**
     * @inheritdoc IAuction
     */
    function swapAndAddLimitOrder(
        IExchangeHelper.SwapArgs calldata s,
        uint64 epoch,
        int128 price64x64,
        uint256 size
    ) external payable nonReentrant {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        _limitOrdersAllowed(auction);

        uint256 cost = _validateLimitOrder(l, price64x64, size);
        uint256 credited = _swapForPoolTokens(l.Exchange, s, address(ERC20));
        _transferAssets(credited, cost, msg.sender);
        _addOrder(l, auction, epoch, price64x64, size, true);
    }

    /**
     * @inheritdoc IAuction
     */
    function cancelLimitOrder(uint64 epoch, uint128 orderId)
        external
        nonReentrant
    {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        _limitOrdersAllowed(auction);

        require(orderId > 0, "invalid order id");

        OrderBook.Index storage orderbook = l.orderbooks[epoch];
        OrderBook.Data memory data = orderbook._getOrderById(orderId);

        require(data.buyer != address(0), "order does not exist");
        require(data.buyer == msg.sender, "buyer != msg.sender");

        orderbook._remove(orderId);
        // removes unique order id associated with epoch and id
        _removeUniqueOrderId(l, epoch, orderId);

        if (block.timestamp >= auction.startTime) {
            _finalizeAuction(l, auction, epoch);
        }

        uint256 cost = data.price64x64.mulu(data.size);
        ERC20.safeTransfer(msg.sender, cost);

        emit OrderCanceled(epoch, orderId, msg.sender);
    }

    /**
     * @inheritdoc IAuction
     */
    function addMarketOrder(
        uint64 epoch,
        uint256 size,
        uint256 maxCost
    ) external payable nonReentrant {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        _marketOrdersAllowed(auction);

        (int128 price64x64, uint256 cost) =
            _validateMarketOrder(l, auction, size, maxCost);

        uint256 credited = _wrapNativeToken(cost);
        // an approve() by the msg.sender is required beforehand
        ERC20.safeTransferFrom(msg.sender, address(this), cost - credited);
        _addOrder(l, auction, epoch, price64x64, size, false);
    }

    /**
     * @inheritdoc IAuction
     */
    function swapAndAddMarketOrder(
        IExchangeHelper.SwapArgs calldata s,
        uint64 epoch,
        uint256 size,
        uint256 maxCost
    ) external payable nonReentrant {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        _marketOrdersAllowed(auction);

        (int128 price64x64, uint256 cost) =
            _validateMarketOrder(l, auction, size, maxCost);

        uint256 credited = _swapForPoolTokens(l.Exchange, s, address(ERC20));
        _transferAssets(credited, cost, msg.sender);
        _addOrder(l, auction, epoch, price64x64, size, false);
    }

    /************************************************
     *  WITHDRAW
     ***********************************************/

    /**
     * @inheritdoc IAuction
     */
    function withdraw(uint64 epoch) external nonReentrant {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        require(
            AuctionStorage.Status.PROCESSED == auction.status ||
                AuctionStorage.Status.CANCELLED == auction.status,
            "status != processed || cancelled"
        );

        if (AuctionStorage.Status.PROCESSED == auction.status) {
            // long tokens are withheld for 24 hours after the auction has been processed, otherwise
            // if a long position is exercised within 24 hours of the position being underwritten
            // the collateral from the position will be moved to the pools "free liquidity" queue.
            require(
                block.timestamp >= auction.processedTime + 24 hours,
                "hold period has not ended"
            );
        }

        _withdraw(l, epoch);
    }

    /**
     * @inheritdoc IAuction
     */
    function previewWithdraw(uint64 epoch) external returns (uint256, uint256) {
        return _previewWithdraw(epoch, msg.sender);
    }

    /**
     * @inheritdoc IAuction
     */
    function previewWithdraw(uint64 epoch, address buyer)
        external
        returns (uint256, uint256)
    {
        return _previewWithdraw(epoch, buyer);
    }

    /************************************************
     *  FINALIZE AUCTION
     ***********************************************/

    /**
     * @inheritdoc IAuction
     */
    function finalizeAuction(uint64 epoch) external {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        if (
            block.timestamp > auction.endTime + 24 hours &&
            (auction.status == AuctionStorage.Status.INITIALIZED ||
                auction.status == AuctionStorage.Status.FINALIZED)
        ) {
            // cancel the auction if it has not been processed within 24 hours of the
            // auction end time so that buyers may withdraw their refunded amount
            _cancel(auction, epoch);
        } else if (
            block.timestamp >= auction.startTime &&
            auction.status == AuctionStorage.Status.INITIALIZED
        ) {
            // finalize the auction only if the auction has started
            _finalizeAuction(l, auction, epoch);
        }
    }

    /**
     * @inheritdoc IAuction
     */
    function processAuction(uint64 epoch)
        external
        onlyVault
        returns (uint256, uint256)
    {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        require(
            AuctionStorage.Status.FINALIZED == auction.status,
            "status != finalized"
        );

        auction.totalPremiums = _lastPrice64x64(auction).mulu(
            auction.totalContractsSold
        );

        ERC20.safeTransfer(address(Vault), auction.totalPremiums);

        auction.processedTime = block.timestamp;

        _updateStatus(auction, AuctionStorage.Status.PROCESSED, epoch);
        return (auction.totalPremiums, auction.totalContractsSold);
    }

    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @inheritdoc IAuction
     */
    function getAuction(uint64 epoch)
        external
        view
        returns (AuctionStorage.Auction memory)
    {
        return AuctionStorage._getAuction(epoch);
    }

    /**
     * @inheritdoc IAuction
     */
    function getDeltaOffset64x64() external view returns (int128) {
        return AuctionStorage._getDeltaOffset64x64();
    }

    /**
     * @inheritdoc IAuction
     */
    function getMinSize() external view returns (uint256) {
        return AuctionStorage._getMinSize();
    }

    /**
     * @inheritdoc IAuction
     */
    function getOrderById(uint64 epoch, uint128 orderId)
        external
        view
        returns (OrderBook.Data memory)
    {
        return AuctionStorage._getOrderById(epoch, orderId);
    }

    /**
     * @inheritdoc IAuction
     */
    function getStatus(uint64 epoch)
        external
        view
        returns (AuctionStorage.Status)
    {
        return AuctionStorage._getStatus(epoch);
    }

    /**
     * @inheritdoc IAuction
     */
    function getTotalContracts(uint64 epoch) external view returns (uint256) {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        // returns the stored total contracts if the auction has started
        if (auction.startTime > 0 && block.timestamp >= auction.startTime) {
            return AuctionStorage._getTotalContracts(epoch);
        }

        return 0;
    }

    /**
     * @inheritdoc IAuction
     */
    function getTotalContractsSold(uint64 epoch)
        external
        view
        returns (uint256)
    {
        return AuctionStorage._getTotalContractsSold(epoch);
    }

    /**
     * @inheritdoc IAuction
     */
    function getUniqueOrderIds(address buyer)
        external
        view
        returns (uint256[] memory)
    {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        EnumerableSet.UintSet storage uoids = l.uoids[buyer];

        uint256[] memory _uoids = new uint256[](uoids.length());

        unchecked {
            for (uint256 i; i < uoids.length(); ++i) {
                uint256 uoid = uoids.at(i);
                _uoids[i] = uoid;
            }
        }

        return _uoids;
    }

    /************************************************
     *  ERC165 SUPPORT
     ***********************************************/

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId)
        external
        view
        returns (bool)
    {
        return ERC165Storage.layout().isSupportedInterface(interfaceId);
    }

    /************************************************
     *  ERC1155 SUPPORT
     ***********************************************/

    /**
     * @inheritdoc IERC1155Receiver
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @inheritdoc IERC1155Receiver
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

