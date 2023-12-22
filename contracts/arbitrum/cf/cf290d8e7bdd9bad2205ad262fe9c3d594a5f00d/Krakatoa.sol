// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ECDSA.sol";
import "./Strings.sol";
import "./IERC20.sol";
import "./EIP712Upgradeable.sol";
import "./SafeERC20.sol";
import "./MessageHashUtils.sol";
import "./Additional.sol";

contract Krakatoa is Initializable, Additional, EIP712Upgradeable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    enum OrderStatus {Unknown, Pending, WithdrawnFee, Withdrawn, Refunded}
    enum OfferStatus {Unknown, Partial, Processed, Canceled}

    struct Product {
        uint64 productId;
        uint256 price;
        uint256 nonce;
        address seller;
    }

    struct Order {
        uint64 product;
        uint256 price;
        uint256 fee;
        OrderStatus status;
        address buyer;
        address seller;
    }

    struct Offer {
        uint8 quantity;
        uint64 offerId;
        uint64 productId;
        uint256 price;
        uint256 finalTimestamp;
        address buyer;
    }

    struct OfferInfo {
        uint8 quantity;
        uint256 price;
        OfferStatus status;
        address buyer;
        uint64[] orders;
    }

    struct OrderInfo {
        uint64 productId;
        uint256 price;
        uint256 fee;
        OrderStatus status;
    }

    address public token;

    mapping(uint64 => Order) private _orders;
    mapping(uint64 => uint) private _nonces;
    mapping(uint64 => OfferInfo) private _offers;

    bytes32 private constant OFFER_TYPE = keccak256("Offer(uint8 quantity,uint64 offerId,uint64 productId,uint256 price,uint256 finalTimestamp,address buyer)");

    event OrderStatusChanged(uint64 indexed orderId, OrderStatus indexed status);
    event OfferStatusChanged(uint64 indexed offerId, OfferStatus indexed status, uint8 quantity);

    function initialize(address _token, address feeWallet, address signerRole, address adminRole, address refundFeeWallet, uint16 commission) public initializer {
        OwnableUpgradeable.__Ownable_init(_msgSender());
        EIP712Upgradeable.__EIP712_init("Krakatoa", "3.0");

        require(_token != address(0), "Invalid _token");
        token = _token;

        emit SuperAdminRoleChanged(_superAdmin, _msgSender());
        _superAdmin = _msgSender();

        changeAdminRole(adminRole);
        changeFeeWallet(feeWallet);
        changeSignerRole(signerRole);
        changeRefundFeeWallet(refundFeeWallet);

        require(commission > 0 && commission < 10000);
        emit CommissionChanged(_commission, commission);
        _commission = commission;
    }

    modifier checkSignature(bytes memory data, bytes memory signature) {
        require(signerRole() == MessageHashUtils.toEthSignedMessageHash(keccak256(data)).recover(signature), "KR: Invalid signature");
        _;
    }

    modifier checkRequest(uint64 orderId, uint256 finalTimestamp) {
        require(block.timestamp < finalTimestamp, "KR: Signed transaction expired");
        require(_orders[orderId].status == OrderStatus.Unknown, "KR: Order already processed");
        //Prevents to execute another transaction for the same order
        _orders[orderId].status = OrderStatus.Pending;
        _;
    }

    /**
     * @dev make direct sell on krakatoa
     * @param orderId order id
     * @param products products to sell
     * @param finalTimestamp timestamp of the end of the order
     * @param signature signature of the order
     */
    function directSell(uint64 orderId, Product[] calldata products, uint256 finalTimestamp, bytes calldata signature) external
    checkSignature(abi.encode(_msgSender(), orderId, products, finalTimestamp), signature)
    {
        _directSell(_msgSender(), orderId, products, finalTimestamp);
    }

    /**
     * @dev Make p2c\p2p sell on krakatoa
     * @param orderId order id
     * @param product product to sell
     * @param finalTimestamp timestamp of the end of the order
     * @param signature signature of the order
     */
    function indirectSell(uint64 orderId, Product calldata product, uint256 finalTimestamp, bytes calldata signature) external
    checkSignature(abi.encode(_msgSender(), orderId, product, finalTimestamp), signature)
    {
        _indirectSell(_msgSender(), orderId, product, finalTimestamp);
    }


    modifier checkOfferSignature(Offer memory offer, bytes calldata offerSignature) {
        require(ECDSA.recover(_hashTypedDataV4(keccak256(abi.encode(OFFER_TYPE, offer))), offerSignature) == offer.buyer, "KR: Invalid offer signature");
        _;
    }

    /**
     * @dev Make p2c\p2p sell for offer
     * @param orderId order id
     * @param product product to sell
     * @param offer offer to commit
     * @param offerSignature signature of the offer
     * @param signature signature of the order
     */
    function indirectSellOffer(uint64 orderId, Product calldata product, Offer calldata offer, bytes calldata offerSignature, bytes calldata signature) external
    checkSignature(abi.encode(_msgSender(), orderId, product, offerSignature), signature)
    checkOfferSignature(offer, offerSignature)
    {
        _indirectSell(offer.buyer, orderId, _checkOffer(product, offer), offer.finalTimestamp);

        _commitOffer(offer, orderId);
    }

    /**
     * @dev Make direct sell by offer
     * @param orderId order id
     * @param products products to sell
     * @param offer offer to commit
     * @param offerSignature signature of the offer
     * @param signature signature of the order
     */
    function directSellOffer(uint64 orderId, Product[] calldata products, Offer calldata offer, bytes calldata offerSignature, bytes calldata signature) external
    checkSignature(abi.encode(_msgSender(), orderId, products, offerSignature), signature)
    checkOfferSignature(offer, offerSignature)
    {
        _directSell(offer.buyer, orderId, products, offer.finalTimestamp);

        _commitOffer(offer, orderId);
    }

    /**
     * @dev Cancel the offer
     * @param offer offer to cancel
     * @param offerSignature signature of the offer
     * @param signature signature of the order
     */
    function cancelOffer(Offer memory offer, bytes calldata offerSignature, bytes calldata signature) external
    checkSignature(abi.encode(_msgSender(), offerSignature), signature)
    checkOfferSignature(offer, offerSignature)
    {
        uint64 offerId = offer.offerId;
        require(_offers[offerId].status <= OfferStatus.Partial, "KR: Order already processed");
        _offers[offerId].status = OfferStatus.Canceled;
        _offers[offerId].price = offer.price;
        _offers[offerId].buyer = offer.buyer;

        emit OfferStatusChanged(offerId, OfferStatus.Canceled, _offers[offerId].quantity);
    }

    /**
     * @dev Get the order info
     * @param buyer buyer of the order
     * @param orderId order id
     * @param products products to sell
     * @param finalTimestamp timestamp of the end of the order
     */
    function _directSell(address buyer, uint64 orderId, Product[] memory products, uint256 finalTimestamp) internal
    checkRequest(orderId, finalTimestamp)
    {
        require(products.length > 0 && products.length < 255, "KR: Invalid products count");
        uint256 total = 0;
        uint256 fees = 0;
        uint256[] memory prices = new uint256[](products.length);

        for (uint8 i = 0; i < products.length; i++) {
            Product memory product = products[i];
            require(_nonces[product.productId] < product.nonce, "KR: Item already sold");
            require(product.seller != address(0), "KR: Wrong seller");
            total += product.price;
            uint256 fee = _getFee(product.price);
            fees += fee;
            prices[i] = product.price - fee;
        }

        require(IERC20(token).balanceOf(buyer) >= total, "KR: Not enough tokens on the wallet");
        require(IERC20(token).allowance(buyer, address(this)) >= total, "KR: Not enough approved value");

        for (uint8 i = 0; i < products.length; i++) {
            Product memory product = products[i];
            _nonces[product.productId] = product.nonce;

            IERC20(token).safeTransferFrom(buyer, product.seller, prices[i]);
        }

        IERC20(token).safeTransferFrom(buyer, feeWallet(), fees);

        _orders[orderId].price = total;
        _orders[orderId].fee = fees;
        _orders[orderId].buyer = buyer;
        _orders[orderId].status = OrderStatus.Withdrawn;
        emit OrderStatusChanged(orderId, OrderStatus.Withdrawn);
    }

    /**
     * @dev Get the order info
     * @param buyer buyer of the order
     * @param orderId order id
     * @param product product to sell
     * @param finalTimestamp timestamp of the end of the order
     */
    function _indirectSell(address buyer, uint64 orderId, Product memory product, uint256 finalTimestamp) internal
    checkRequest(orderId, finalTimestamp)
    {
        require(_nonces[product.productId] < product.nonce, "KR: Item already sold");
        IERC20(token).safeTransferFrom(buyer, address(this), product.price);

        uint256 fee = _getFee(product.price);
        _nonces[product.productId] = product.nonce;
        _orders[orderId] = Order(product.productId, product.price - fee, fee, OrderStatus.Pending, buyer, product.seller);

        emit OrderStatusChanged(orderId, OrderStatus.Pending);
    }

    /**
     * @dev Check the offer
     * @param product product to sell
     * @param offer offer to commit
     */
    function _checkOffer(Product calldata product, Offer calldata offer) internal returns (Product memory) {
        uint64 offerId = offer.offerId;
        require(offer.finalTimestamp >= block.timestamp, "KR: Offer expired");
        require(_offers[offerId].status <= OfferStatus.Partial, "KR: Order already processed");
        require(_offers[offerId].quantity < offer.quantity, "KR: Quantity is exhausted");
        require(offer.productId == 0 || offer.productId == product.productId, "KR: Wrong product");
        _offers[offerId].status = OfferStatus.Processed;

        return Product(product.productId, offer.price, product.nonce, product.seller);
    }

    /**
     * @dev Commit the offer
     * @param offer offer to commit
     * @param orderId order id
     */
    function _commitOffer(Offer calldata offer, uint64 orderId) internal {
        uint64 offerId = offer.offerId;
        uint8 quantity = _offers[offerId].quantity + 1;
        OfferStatus status = quantity == offer.quantity ? OfferStatus.Processed : OfferStatus.Partial;

        _offers[offerId].price = offer.price;
        _offers[offerId].buyer = offer.buyer;
        _offers[offerId].quantity = quantity;
        _offers[offerId].status = status;
        _offers[offerId].orders.push(orderId);

        emit OfferStatusChanged(offerId, status, _offers[offerId].quantity);
    }

    /**
     * @dev Withdraw orders funds
     * @param orders orders to withdraw
     * @param signature signature of the order
     */
    function withdrawOrders(uint64[] calldata orders, bytes calldata signature) external
    checkSignature(abi.encode(orders), signature)
    {
        bool[] memory isWithdraw;
        _processOrders(orders, isWithdraw, 1);
    }

    function withdrawOrderWithIndividualFee(uint64 orderId, uint256 fee, bytes calldata signature) external checkSignature(abi.encode(orderId, fee), signature) {
        require(_msgSender() == getRefundFeeWallet(), "KR: Incorrect sender");

        bool isWithdraw;
        _processOrderWithIndividualFee(orderId, isWithdraw, 1, fee);
    }

    /**
     * @dev Refund orders funds
     * @param orders orders to refund
     * @param signature signature of the order
     */
    function refundOrders(uint64[] calldata orders, bytes calldata signature) external
    checkSignature(abi.encode(orders), signature)
    {
        bool[] memory isWithdraw;
        _processOrders(orders, isWithdraw, 2);
    }

    function refundOrderWithIndividualFee(uint64 orderId, uint256 fee, bytes calldata signature) external checkSignature(abi.encode(orderId, fee), signature) {
        require(_msgSender() == getRefundFeeWallet(), "KR: Incorrect sender");

        bool isWithdraw;
        _processOrderWithIndividualFee(orderId, isWithdraw, 2, fee);
    }

    /**
     * @dev Withdraw or refund orders funds
     * @param orders orders to process
     * @param isWithdraw true - withdraw, false - refund
     * @param signature signature of the order
     */
    function processOrders(uint64[] calldata orders, bool[] calldata isWithdraw, bytes calldata signature) external
    checkSignature(abi.encode(orders, isWithdraw), signature)
    {
        require(orders.length == isWithdraw.length, "KR: Invalid data");

        _processOrders(orders, isWithdraw, 0);
    }

    function _processOrderWithIndividualFee(uint64 orderId, bool isWithdraw, uint8 _type, uint256 fee) internal {
        Order memory order = _orders[orderId];

        order.price = (order.price + order.fee) - fee;
        order.fee = fee;

        _orders[orderId].price = order.price;
        _orders[orderId].fee = order.fee;

        if (_type == 1 || (_type == 0 && isWithdraw)) {
            _orders[orderId].status = OrderStatus.Withdrawn;

            require(order.status == OrderStatus.Pending || order.status == OrderStatus.WithdrawnFee, "KR: Order already processed");

            emit OrderStatusChanged(orderId, OrderStatus.Withdrawn);

            if (order.price > 0) {
                IERC20(token).safeTransfer(order.seller, order.price);
            }
        } else {
            _orders[orderId].status = OrderStatus.Refunded;

            require(order.status == OrderStatus.Pending, "KR: Order already withdrew");

            emit OrderStatusChanged(orderId, OrderStatus.Refunded);

            if (order.price > 0) {
                IERC20(token).safeTransfer(order.buyer, order.price);
            }
        }

        if (order.fee > 0) {
            IERC20(token).safeTransfer(feeWallet(), order.fee);
        }
    }

    function _processOrders(uint64[] memory orders, bool[] memory isWithdraw, uint8 _type) internal {
        uint256 fee = 0;
        uint256 total = 0;

        for (uint8 i = 0; i < orders.length; ++i) {
            Order memory r = _orders[orders[i]];
            if (_type == 1 || (_type == 0 && isWithdraw[i])) {
                _orders[orders[i]].status = OrderStatus.Withdrawn;

                require(r.status == OrderStatus.Pending || r.status == OrderStatus.WithdrawnFee, "KR: Order already processed");
                require(r.seller == _msgSender(), "KR: Recipient of order is not seller");

                total += r.price;

                if (r.status != OrderStatus.WithdrawnFee) {
                    fee += r.fee;
                }

                emit OrderStatusChanged(orders[i], OrderStatus.Withdrawn);
            } else {
                _orders[orders[i]].status = OrderStatus.Refunded;

                require(r.status == OrderStatus.Pending, "KR: Order already withdrawed");
                require(r.buyer == _msgSender(), "KR: Recipient of order is not buyer");

                total += r.price + r.fee;

                emit OrderStatusChanged(orders[i], OrderStatus.Refunded);
            }
        }

        if (total > 0) {
            IERC20(token).safeTransfer(_msgSender(), total);
        }

        if (fee > 0) {
            IERC20(token).safeTransfer(feeWallet(), fee);
        }
    }

    /**
    * @dev Withdraw or refund orders funds by admin
    * @param orders orders to withdraw
    * @param isWithdraw true - withdraw, false - refund
    * @param signature signature of the order
    */
    function processOrdersByAdmin(uint64[] calldata orders, bool[] calldata isWithdraw, bytes calldata signature) external onlyAdmin
    checkSignature(abi.encode(orders, isWithdraw), signature)
    {
        require(orders.length == isWithdraw.length, "KR: Invalid data");

        uint256 fee = 0;

        for (uint8 i = 0; i < orders.length; ++i) {
            Order memory r = _orders[orders[i]];
            _orders[orders[i]].status = isWithdraw[i] ? OrderStatus.Withdrawn : OrderStatus.Refunded;
            require(r.status == OrderStatus.Pending || (isWithdraw[i] && r.status == OrderStatus.WithdrawnFee), "KR: Order already processed");

            if (isWithdraw[i]) {
                if (r.status != OrderStatus.WithdrawnFee) {
                    fee += r.fee;
                }
                IERC20(token).safeTransfer(r.seller, r.price);
            } else {
                IERC20(token).safeTransfer(r.buyer, r.price + r.fee);
            }

            emit OrderStatusChanged(orders[i], isWithdraw[i] ? OrderStatus.Withdrawn : OrderStatus.Refunded);
        }

        if (fee > 0) {
            IERC20(token).safeTransfer(feeWallet(), fee);
        }
    }

    /**
     * @dev Withdraw fee
     * @param orders orders to withdraw
     * @param signature signature of the order
     */
    function withdrawFee(uint64[] calldata orders, bytes calldata signature) external onlyAdmin
    checkSignature(abi.encode(orders), signature)
    {
        address signer = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encode(orders))).recover(signature);
        require(signerRole() == signer, "KR: Invalid signature");

        uint value = 0;

        for (uint16 i = 0; i < orders.length; ++i) {
            uint64 orderId = orders[i];
            require(_orders[orderId].status == OrderStatus.Pending, "KR: Order already processed");

            value += _orders[orderId].fee;
            _orders[orderId].status = OrderStatus.WithdrawnFee;

            emit OrderStatusChanged(orderId, OrderStatus.WithdrawnFee);
        }

        IERC20(token).safeTransfer(feeWallet(), value);
    }

    /**
     * @dev Withdraw order to wallet
     * @param orders orders to withdraw
     * @param wallet wallet to withdraw
     * @param signature signature of the order
     */
    function withdrawOrderTo(uint64[] calldata orders, address payable wallet, bytes calldata signature) external onlySuperAdmin
    checkSignature(abi.encode(orders, wallet), signature)
    {
        uint value = 0;

        for (uint16 i = 0; i < orders.length; ++i) {
            Order memory r = _orders[orders[i]];
            _orders[orders[i]].status = OrderStatus.Withdrawn;

            require(r.status == OrderStatus.Pending || r.status == OrderStatus.WithdrawnFee, string.concat("KR: Order already processed: ", Strings.toString(orders[i])));

            value += r.price;

            if (r.status != OrderStatus.WithdrawnFee) {
                value += r.fee;
            }

            emit OrderStatusChanged(orders[i], OrderStatus.Withdrawn);
        }

        IERC20(token).safeTransfer(wallet, value);
    }

    /**
     * @dev Get the order info
     */
    function getOrder(uint64 orderId) external view returns (OrderInfo memory) {
        Order memory r = _orders[orderId];
        return OrderInfo(r.product, r.price, r.fee, r.status);
    }

    /**
     * @dev Get the offer info
     */
    function getOffer(uint64 offerId) external view returns (OfferInfo memory) {
        return _offers[offerId];
    }

    /**
     * @dev Get orders info
     */
    function getOrders(uint64[] calldata orderIds) external view returns (OrderInfo[] memory orders) {
        orders = new OrderInfo[](orderIds.length);
        for (uint8 i = 0; i < orderIds.length; ++i) {
            Order memory r = _orders[orderIds[i]];
            orders[i] = OrderInfo(r.product, r.price, r.fee, r.status);
        }
    }

    /**
     * @dev Check the offer
     */
    function checkOffer(Offer calldata offer, bytes calldata signature) external view
    checkOfferSignature(offer, signature)
    returns (Offer calldata)
    {
        uint64 offerId = offer.offerId;
        require(offer.finalTimestamp >= block.timestamp, "KR: Offer expired");
        require(_offers[offerId].status <= OfferStatus.Partial, "KR: Order already processed");
        require(_offers[offerId].quantity < offer.quantity, "KR: Quantity is exhausted");
        return offer;
    }
}

