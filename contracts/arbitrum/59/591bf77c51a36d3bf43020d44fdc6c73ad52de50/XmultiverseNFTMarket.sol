//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./ERC721Holder.sol";
import "./IERC721.sol";
import "./ERC1155Holder.sol";
import "./IERC1155.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./IERC2981.sol";
import "./IMarket.sol";

contract XmultiverseNFTMarket is IMarket, Ownable, ERC1155Holder, ERC721Holder {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public tradeFeeRate = 500; // 0-2000, default 500
    uint256 public constant rateBase = 10000; // base is always 10000

    using Counters for Counters.Counter;
    Counters.Counter private _orderCounter;
    mapping(uint256 => Order) public orderStorage;
    mapping(uint256 => BidInfo) public bidStorage;
    mapping(address => EnumerableSet.UintSet) private _orderIds;
    mapping(address => mapping(uint256 => EnumerableSet.UintSet))
        private _nftOrderIds;

    /********** internal functions **********/

    function _sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "unable to send value, recipient may have reverted");
    }

    function _isEth(address token) internal pure returns (bool) {
        return token == address(0);
    }

    function _safeTransferERC20(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (from == address(this)) {
            IERC20(token).safeTransfer(to, amount);
        } else {
            IERC20(token).safeTransferFrom(from, to, amount);
        }
    }

    function _safeTransferERC721(
        address nftToken,
        address from,
        address to,
        uint256 tokenId
    ) internal {
        IERC721(nftToken).safeTransferFrom(from, to, tokenId);
    }

    function _safeTransferERC1155(
        address nftToken,
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) internal {
        IERC1155(nftToken).safeTransferFrom(from, to, id, amount, "");
    }

    function _addOrder(Order memory order) private {
        orderStorage[order.id] = order;
        _orderIds[order.orderOwner].add(order.id);
        _nftOrderIds[order.nftInfo.nftToken][order.nftInfo.tokenId].add(
            order.id
        );
    }

    function _deleteOrder(Order memory order) private {
        delete orderStorage[order.id];
        _orderIds[order.orderOwner].remove(order.id);
        _nftOrderIds[order.nftInfo.nftToken][order.nftInfo.tokenId].remove(
            order.id
        );
    }

    function _lockToken(address token, uint256 amount) internal {
        if (_isEth(token)) {
            require(msg.value == amount, "Value mismatch");
        } else {
            _safeTransferERC20(token, msg.sender, address(this), amount);
        }
    }

    function _unlockToken(
        address token,
        address to,
        uint256 amount
    ) internal {
        if (_isEth(token)) {
            _sendValue(payable(to), amount);
        } else {
            _safeTransferERC20(token, address(this), to, amount);
        }
    }

    function _auctionDeal(Order memory order) internal {
        require(order.id > 0, "Order not exist");
        require(block.timestamp > order.endTime, "Order is in auction time");
        require(order.orderType == OrderType.Auction, "OrderType invalid");
        BidInfo memory currentBid = bidStorage[order.id];
        require(currentBid.price > 0, "Bid not exist");

        uint256 totalFee = _chargeFee(
            order,
            order.nftInfo.tokenId,
            currentBid.price
        );
        _unlockToken(
            order.token,
            order.orderOwner,
            currentBid.price.sub(totalFee)
        );

        if (order.nftInfo.nftType == NFTType.ERC721) {
            _safeTransferERC721(
                order.nftInfo.nftToken,
                address(this),
                currentBid.bidder,
                order.nftInfo.tokenId
            );
        } else {
            _safeTransferERC1155(
                order.nftInfo.nftToken,
                address(this),
                currentBid.bidder,
                order.nftInfo.tokenId,
                order.nftInfo.tokenAmount
            );
        }
        emit CompleteOrder(
            order.id,
            uint256(order.orderType),
            order.orderOwner,
            msg.sender,
            currentBid.price,
            order
        );
        delete bidStorage[order.id];
        _deleteOrder(order);
    }

    function _cancelOrder(Order memory order) internal {
        require(order.id > 0, "Order not exist");
        if (
            order.orderType == OrderType.Buy ||
            order.orderType == OrderType.BuyCollection
        ) {
            // unlock token
            _unlockToken(order.token, order.orderOwner, order.price);
        } else {
            // unlock nft
            if (order.nftInfo.nftType == NFTType.ERC721) {
                _safeTransferERC721(
                    order.nftInfo.nftToken,
                    address(this),
                    order.orderOwner,
                    order.nftInfo.tokenId
                );
            } else {
                _safeTransferERC1155(
                    order.nftInfo.nftToken,
                    address(this),
                    order.orderOwner,
                    order.nftInfo.tokenId,
                    order.nftInfo.tokenAmount
                );
            }
        }

        emit CancelOrder(
            order.id,
            uint256(order.orderType),
            order.orderOwner,
            order.nftInfo.nftToken,
            order.nftInfo.tokenId
        );
        _deleteOrder(order);
    }

    function _chargeFee(
        Order memory order,
        uint256 tokenId,
        uint256 price
    ) internal returns (uint256) {
        uint256 totalFee = 0;
        // trade fee
        if (tradeFeeRate > 0) {
            uint256 tradeFee = price.mul(tradeFeeRate).div(rateBase);
            _unlockToken(order.token, owner(), tradeFee);
            totalFee = tradeFee;
        }

        // royalty fee, max 50%
        if (
            IERC721(order.nftInfo.nftToken).supportsInterface(
                type(IERC2981).interfaceId
            )
        ) {
            (address receiver, uint256 royaltyAmount) = IERC2981(
                order.nftInfo.nftToken
            ).royaltyInfo(tokenId, price);
            if (royaltyAmount > 0 && royaltyAmount <= price / 2) {
                totalFee += royaltyAmount;
                _unlockToken(order.token, receiver, royaltyAmount);
            }
        }
        return totalFee;
    }

    /********** mutable functions **********/

    receive() external payable {}

    fallback() external payable {}

    function setTradeFeeRate(uint256 newTradeFeeRate) external onlyOwner {
        require(tradeFeeRate <= 2000, "Trade fee rate exceed limit");
        tradeFeeRate = newTradeFeeRate;
    }

    function createOrder(
        OrderType orderType,
        NFTType nftType,
        address nftToken,
        uint256 tokenId,
        uint256 tokenAmount,
        address token,
        uint256 price,
        uint256 timeLimit,
        uint256 changeRate,
        uint256 minPrice
    ) external payable override returns (uint256) {
        require(price > 0, "Price invalid");
        require(timeLimit > 0, "TimeLimit invalid");
        // verify changeRate and minPrice
        if (
            orderType == OrderType.Buy ||
            orderType == OrderType.BuyCollection ||
            orderType == OrderType.Sell
        ) {
            changeRate = 0;
            minPrice = 0;
        } else if (orderType == OrderType.Auction) {
            require(changeRate > 0, "ChangeRate invalid");
            minPrice = 0;
        } else if (orderType == OrderType.DutchAuction) {
            require(changeRate > 0, "ChangeRate invalid");
            require(minPrice > 0 && minPrice < price, "MinPrice invalid");
        }

        _orderCounter.increment();
        uint256 orderId = _orderCounter.current();
        NftInfo memory nftInfo = NftInfo({
            nftType: nftType,
            nftToken: nftToken,
            tokenId: tokenId,
            tokenAmount: tokenAmount
        });
        Order memory order = Order({
            id: orderId,
            orderType: orderType,
            orderOwner: msg.sender,
            nftInfo: nftInfo,
            token: token,
            price: price,
            startTime: block.timestamp,
            endTime: block.timestamp.add(timeLimit),
            changeRate: changeRate,
            minPrice: minPrice
        });

        // token amount is always 1 for erc721
        if (nftType == NFTType.ERC721) {
            order.nftInfo.tokenAmount = 1;
        }
        // lock asset
        if (
            orderType == OrderType.Buy || orderType == OrderType.BuyCollection
        ) {
            _lockToken(token, order.price);
        } else if (nftType == NFTType.ERC721) {
            _safeTransferERC721(
                order.nftInfo.nftToken,
                msg.sender,
                address(this),
                order.nftInfo.tokenId
            );
        } else {
            _safeTransferERC1155(
                order.nftInfo.nftToken,
                msg.sender,
                address(this),
                order.nftInfo.tokenId,
                order.nftInfo.tokenAmount
            );
        }

        emit CreateOrder(
            order.id,
            uint256(order.orderType),
            order.orderOwner,
            order
        );
        _addOrder(order);
        return order.id;
    }

    function changeOrder(
        uint256 orderId,
        uint256 price,
        uint256 timeLimit
    ) external payable override {
        Order memory order = orderStorage[orderId];
        require(order.id > 0, "Order not exist");
        require(order.orderOwner == msg.sender, "Order owner mismatch");
        require(price > 0, "Price invalid");
        require(timeLimit > 0, "TimeLimit invalid");
        require(
            order.orderType != OrderType.Auction &&
                order.orderType != OrderType.DutchAuction,
            "Auction or DutchAuction change is not allowed"
        );

        // change locked token
        if (
            (order.orderType == OrderType.Buy ||
                order.orderType == OrderType.BuyCollection) &&
            order.price != price
        ) {
            if (price > order.price) {
                _lockToken(order.token, price - order.price);
            } else {
                _unlockToken(order.token, msg.sender, order.price - price);
            }
        }

        order.price = price;
        order.endTime = block.timestamp.add(timeLimit);
        emit ChangeOrder(
            order.id,
            uint256(order.orderType),
            order.orderOwner,
            order.token,
            order.price,
            order.startTime,
            order.endTime
        );
        orderStorage[order.id] = order;
    }

    function cancelOrder(uint256 orderId) external override {
        Order memory order = orderStorage[orderId];
        require(order.id > 0, "Order not exist");
        require(order.orderOwner == msg.sender, "Order owner not match");
        if (order.orderType == OrderType.Auction) {
            // check bid info
            BidInfo memory bidInfo = bidStorage[orderId];
            require(bidInfo.price == 0, "Bid should be Null");
        }
        _cancelOrder(order);
    }

    function fulfillOrder(
        uint256 orderId,
        uint256 price,
        uint256 tokenId
    ) external payable override {
        Order memory order = orderStorage[orderId];
        require(order.id > 0, "Order not exist");
        require(order.orderType != OrderType.Auction, "OrderType invalid");
        require(block.timestamp <= order.endTime, "Order expired");
        if (order.orderType == OrderType.DutchAuction) {
            require(price == getDutchPrice(order.id), "Price not match");
        } else {
            require(order.price == price, "Price not match");
        }
        if (order.orderType != OrderType.BuyCollection) {
            require(order.nftInfo.tokenId == tokenId, "TokenId not match");
        }

        if (
            order.orderType == OrderType.Sell ||
            order.orderType == OrderType.DutchAuction
        ) {
            _payToken(order, price);
        } else if (
            order.orderType == OrderType.Buy ||
            order.orderType == OrderType.BuyCollection
        ) {
            _payNft(order, price, tokenId);
        }

        emit CompleteOrder(
            order.id,
            uint256(order.orderType),
            order.orderOwner,
            msg.sender,
            price,
            order
        );
        _deleteOrder(order);
    }

    function _payToken(Order memory order, uint256 price) internal {
        // pay token
        _lockToken(order.token, price);
        uint256 totalFee = _chargeFee(order, order.nftInfo.tokenId, price);
        _unlockToken(order.token, order.orderOwner, price - totalFee);

        // get nft
        if (order.nftInfo.nftType == NFTType.ERC721) {
            _safeTransferERC721(
                order.nftInfo.nftToken,
                address(this),
                msg.sender,
                order.nftInfo.tokenId
            );
        } else {
            _safeTransferERC1155(
                order.nftInfo.nftToken,
                address(this),
                msg.sender,
                order.nftInfo.tokenId,
                order.nftInfo.tokenAmount
            );
        }
    }

    function _payNft(
        Order memory order,
        uint256 price,
        uint256 tokenId
    ) internal {
        // pay nft
        if (order.nftInfo.nftType == NFTType.ERC721) {
            _safeTransferERC721(
                order.nftInfo.nftToken,
                msg.sender,
                order.orderOwner,
                tokenId
            );
        } else {
            _safeTransferERC1155(
                order.nftInfo.nftToken,
                msg.sender,
                order.orderOwner,
                tokenId,
                order.nftInfo.tokenAmount
            );
        }
        // get token
        uint256 totalFee = _chargeFee(order, tokenId, price);
        _unlockToken(order.token, msg.sender, price - totalFee);
    }

    function bid(uint256 orderId, uint256 price) external payable override {
        Order memory order = orderStorage[orderId];
        require(order.id > 0, "Order not exist");
        require(price >= order.price, "Price needs to exceed reserve price");
        require(block.timestamp <= order.endTime, "Order expired");
        require(order.orderType == OrderType.Auction, "OrderType invalid");
        _lockToken(order.token, price);

        BidInfo memory preBid = bidStorage[orderId];
        if (preBid.price > 0) {
            uint256 minPrice = (preBid.price * (order.changeRate + rateBase)) /
                rateBase;
            require(price >= minPrice, "Bid price low");
            // refund current bid
            _unlockToken(order.token, preBid.bidder, preBid.price);
        }

        BidInfo memory bidInfo = BidInfo({bidder: msg.sender, price: price});
        bidStorage[order.id] = bidInfo;
        emit Bid(
            order.id,
            uint256(order.orderType),
            order.orderOwner,
            msg.sender,
            block.timestamp,
            order.token,
            bidInfo.price
        );
    }

    // cancelAll will cancel all the orders, only owner
    function cancelAll() external override onlyOwner {
        uint256 length = _orderCounter.current();
        for (uint256 i = 0; i < length; i++) {
            Order memory order = orderStorage[i + 1];
            if (order.id > 0) {
                if (order.orderType == OrderType.Auction) {
                    // check bid info
                    BidInfo memory bidInfo = bidStorage[order.id];
                    if (bidInfo.price > 0) {
                        if (block.timestamp > order.endTime) {
                            _auctionDeal(order);
                            return;
                        } else {
                            _unlockToken(
                                order.token,
                                bidInfo.bidder,
                                bidInfo.price
                            );
                        }
                    }
                }
                _cancelOrder(order);
            }
        }
    }

    // deal with the expired order
    // aution with bidder will claim, without bidder will refund
    function endOrder(uint256 orderId) external override {
        Order memory order = orderStorage[orderId];
        require(order.id > 0, "Order not exist");
        require(block.timestamp > order.endTime, "Order is not expired");
        if (order.orderType == OrderType.Auction) {
            // check bid info
            BidInfo memory bidInfo = bidStorage[order.id];
            if (bidInfo.price > 0) {
                _auctionDeal(order);
                return;
            }
        }
        _cancelOrder(order);
    }

    /********** view functions **********/

    function name() external pure override returns (string memory) {
        return "Xmultiverse NFT Market";
    }

    function getTradeFeeRate() external view override returns (uint256) {
        return tradeFeeRate;
    }

    function getOrder(uint256 orderId)
        external
        view
        override
        returns (Order memory)
    {
        return orderStorage[orderId];
    }

    function getDutchPrice(uint256 orderId)
        public
        view
        override
        returns (uint256)
    {
        Order memory order = orderStorage[orderId];
        require(order.id > 0, "Order not exist");
        require(
            order.orderType == OrderType.DutchAuction,
            "Order type invalid"
        );
        uint256 oneHour = 1 hours;
        uint256 decreasePrice = order
            .price
            .mul(order.changeRate)
            .mul(block.timestamp.sub(order.startTime).div(oneHour))
            .div(rateBase);
        if (decreasePrice.add(order.minPrice) > order.price) {
            return order.minPrice;
        }
        return order.price.sub(decreasePrice);
    }

    function getBidInfo(uint256 orderId)
        external
        view
        override
        returns (BidInfo memory)
    {
        return bidStorage[orderId];
    }

    function getOrdersByOwner(address orderOwner)
        external
        view
        override
        returns (Order[] memory)
    {
        uint256 length = _orderIds[orderOwner].length();
        Order[] memory list = new Order[](length);
        for (uint256 i = 0; i < length; i++) {
            list[i] = orderStorage[_orderIds[orderOwner].at(i)];
        }
        return list;
    }

    function getOrdersByNft(address nftToken, uint256 tokenId)
        external
        view
        override
        returns (Order[] memory)
    {
        uint256 length = _nftOrderIds[nftToken][tokenId].length();
        Order[] memory list = new Order[](length);
        for (uint256 i = 0; i < length; i++) {
            list[i] = orderStorage[_nftOrderIds[nftToken][tokenId].at(i)];
        }
        return list;
    }
}

