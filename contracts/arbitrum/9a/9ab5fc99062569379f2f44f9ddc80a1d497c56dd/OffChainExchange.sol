// SPDX-License-Identifier: MIT
pragma solidity 0.4.26;

import "./OKRoyaltyFeeManager.sol";
import "./SafeMath.sol";
import "./MyTools.sol";
import "./ArrayUtils.sol";
import "./SaleKindInterface.sol";
import "./TransferNFTManager.sol";
import "./TokenRecipient.sol";
import "./Proxy.sol";
import "./ReentrancyGuarded.sol";
import "./ProxyRegistry.sol";
import "./OwnedUpgradeabilityStorage.sol";
import "./AuthenticatedProxy.sol";
import "./SecurityBaseFor4.sol";
import "./IApproveProxy.sol";
import "./ICancelOrder_v4.sol";

/**
 * @title ExchangeCore
 * @author Project Wyvern Developers
 */
contract ExchangeCore is ReentrancyGuarded, SecurityBaseFor4 {
    /* The token used to pay exchange fees.

    */
    ERC20 public exchangeToken;

    /* User registry. */
    ProxyRegistry public registry;

    /* Token transfer proxy. */
    TokenTransferProxy public tokenTransferProxy;

    /* Cancelled / finalized orders, by hash. */
    mapping(bytes32 => bool) public cancelledOrFinalized;

    /* Orders verified by on-chain approval (alternative to ECDSA signatures so that smart contracts can place orders directly). */
    mapping(bytes32 => bool) public approvedOrders;

    OKRoyaltyFeeManager public okRoyaltyFeeManager;

    /* For split fee orders, minimum required protocol maker fee, in basis points. Paid to owner (who can change it). */
    uint256 public minimumMakerProtocolFee = 0;

    /* For split fee orders, minimum required protocol taker fee, in basis points. Paid to owner (who can change it). */
    uint256 public minimumTakerProtocolFee = 0;

    /* Recipient of protocol fees. */
    address public protocolFeeRecipient;

    /* Fee method: protocol fee or split fee. */
    enum FeeMethod {
        ProtocolFee,
        SplitFee
    }

    /* Inverse basis point. */
    uint256 public constant INVERSE_BASIS_POINT = 10000;

    struct TempData {
        address nftOwner;
        address buyerAddress;
        address nftContract;
        uint256 transferTokenIdSell;
        uint256 transferTokenIdBuy;
        bytes functionName;
        bytes result;
        bytes calldataValue;
        uint256 tokenId;
        uint256 sellAmount;
        uint256 buyAmount;
        bytes4 functionNameToBytes4;
    }

    TempData tempData;

    /*
     *     1 v 1 automic Match function selector
     *
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,uint256,bytes)')) == 0xf242432a
     *     bytes4(keccak256('safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)')) == 0x2eb2c2d6
     */
    bytes4 private constant FUNCTION_TRANSFERFROM = 0x23b872dd;
    bytes4 private constant FUNCTION_SAFETRANSFERFROM = 0x42842e0e;
    bytes4 private constant FUNCTION_SAFETRANSFERFROM_CALL = 0xb88d4fde;

    bytes4 private constant FUNCTION_SAFETRANSFERFROM_1155 = 0xf242432a;
    bytes4 private constant FUNCTION_SAFEBATCHTRANSFERFROM_1155 = 0x2eb2c2d6;

    //OKX union approve address
    address public approveProxyAddr;

    bool enableApproveProxy;
    using SafeMath for uint256;

    /* An ECDSA signature. */
    struct Sig {
        /* v parameter */
        uint8 v;
        /* r parameter */
        bytes32 r;
        /* s parameter */
        bytes32 s;
    }

    /* An order on the exchange. */
    struct Order {
        /* Exchange address, intended as a versioning mechanism. */
        address exchange;
        /* Order maker address. */
        address maker;
        /* Order taker address, if specified. */
        address taker;
        /* Maker relayer fee of the order, unused for taker order. */
        uint256 makerRelayerFee;
        /* Taker relayer fee of the order, or maximum taker fee for a taker order. */
        uint256 takerRelayerFee;
        /* Maker protocol fee of the order, unused for taker order. */
        uint256 makerProtocolFee;
        /* Taker protocol fee of the order, or maximum taker fee for a taker order. */
        uint256 takerProtocolFee;
        /* Order fee recipient or zero address for taker order. */
        address feeRecipient;
        /* Fee method (protocol token or split fee). */
        FeeMethod feeMethod;
        /* Side (buy/sell). */
        SaleKindInterface.Side side;
        /* Kind of sale. */
        SaleKindInterface.SaleKind saleKind;
        /* Target. */
        address target;
        /* HowToCall. */
        AuthenticatedProxy.HowToCall howToCall;
        /* Calldata. */
        bytes calldata;
        /* Calldata replacement pattern, or an empty byte array for no replacement. */
        bytes replacementPattern;
        /* Static call target, zero-address for no static call. */
        address staticTarget;
        /* Static call extra data. */
        bytes staticExtradata;
        /* Token used to pay for the order, or the zero-address as a sentinel value for Ether. */
        address paymentToken;
        /* Base price of the order (in paymentTokens). */
        uint256 basePrice;
        /* Auction extra parameter - minimum bid increment for English auctions, starting/ending price difference. */
        uint256 extra;
        /* Listing timestamp. */
        uint256 listingTime;
        /* Expiration timestamp - 0 for no expiry. */
        uint256 expirationTime;
        /* Order salt, used to prevent duplicate hashes. */
        uint256 salt;
    }
    TransferNFTManager public transferManager;

    address public cancelOrderAddr;
    
    event OrderCancelled(bytes32 indexed hash);
    event OrdersMatched(
        bytes32 buyHash,
        bytes32 sellHash,
        address indexed maker,
        address indexed taker,
        uint256 price,
        bytes32 indexed metadata
    );

    function setupCopyrightMap(OKRoyaltyFeeManager feeManager)
        public
        onlyWhitelist
    {
        okRoyaltyFeeManager = feeManager;
    }

    function setEnableApproveProxy(bool _enableApproveProxy) public onlyWhitelist {
        enableApproveProxy = _enableApproveProxy;
    }

    /**
     * @dev Change the minimum maker fee paid to the protocol (owner only)
     * @param newMinimumMakerProtocolFee New fee to set in basis points
     */
    function changeMinimumMakerProtocolFee(uint256 newMinimumMakerProtocolFee)
        public
        onlyWhitelist
    {
        minimumMakerProtocolFee = newMinimumMakerProtocolFee;
    }

    /**
     * @dev Change the minimum taker fee paid to the protocol (owner only)
     * @param newMinimumTakerProtocolFee New fee to set in basis points
     */
    function changeMinimumTakerProtocolFee(uint256 newMinimumTakerProtocolFee)
        public
        onlyWhitelist
    {
        minimumTakerProtocolFee = newMinimumTakerProtocolFee;
    }

    /**
     * @dev Change the protocol fee recipient (owner only)
     * @param newProtocolFeeRecipient New protocol fee recipient address
     */
    function changeProtocolFeeRecipient(address newProtocolFeeRecipient)
        public
        onlyWhitelist
    {
        protocolFeeRecipient = newProtocolFeeRecipient;
    }

    function setupApproveProxy(address _approveProxyAddr) external onlyWhitelist {
        approveProxyAddr = _approveProxyAddr;
    }

    function setupCancelOrder(address _cancelOrderAddr)
    external
    onlyWhitelist
    {
        cancelOrderAddr = _cancelOrderAddr;
    }

    /**
     * @dev Transfer tokens
     * @param token Token to transfer
     * @param from Address to charge fees
     * @param to Address to receive fees
     * @param amount Amount of protocol tokens to charge
     */
    function transferTokens(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            address approveAddr = IApproveProxy(approveProxyAddr)
                .tokenApprove();
            //new proxy address has approved
            uint256 spendAmount = IERC20(token).allowance(from, approveAddr);
            //because FE not upgrade,need to be compatible with current version
            //so spendAmount greater than zero trigger new feature
            if (enableApproveProxy == true) {
                require(
                    spendAmount >= amount,
                    "allowance must greater than amount"
                );
                IApproveProxy(approveProxyAddr).claimTokens(
                    token,
                    from,
                    to,
                    amount
                );
            } else {
                require(
                    tokenTransferProxy.transferFrom(token, from, to, amount),
                    "cost erc20 failed!"
                );
            }
        }
    }

    /**
     * @dev Execute a STATICCALL (introduced with Ethereum Metropolis, non-state-modifying external call)
     * @param target Contract to call
     * @param calldata Calldata (appended to extradata)
     * @param extradata Base data for STATICCALL (probably function selector and argument encoding)
     * @return The result of the call (success or failure)
     */
    function staticCall(
        address target,
        bytes memory calldata,
        bytes memory extradata
    ) public view returns (bool result) {
        bytes memory combined = new bytes(calldata.length + extradata.length);
        uint256 index;
        assembly {
            index := add(combined, 0x20)
        }
        index = ArrayUtils.unsafeWriteBytes(index, extradata);
        ArrayUtils.unsafeWriteBytes(index, calldata);
        assembly {
            result := staticcall(
                gas,
                target,
                add(combined, 0x20),
                mload(combined),
                mload(0x40),
                0
            )
        }
        return result;
    }

    /**
     * Calculate size of an order struct when tightly packed
     *
     * @param order Order to calculate size of
     * @return Size in bytes
     */
    function sizeOf(Order memory order) internal pure returns (uint256) {
        return ((0x14 * 7) +
            (0x20 * 9) +
            4 +
            order.calldata.length +
            order.replacementPattern.length +
            order.staticExtradata.length);
    }

    /**
     * @dev Hash an order, returning the canonical order hash, without the message prefix
     * @param order Order to hash
     * @return Hash of order
     */
    function hashOrder(Order memory order)
        internal
        pure
        returns (bytes32 hash)
    {
        /* Unfortunately abi.encodePacked doesn't work here, stack size constraints. */
        uint256 size = sizeOf(order);
        bytes memory array = new bytes(size);
        uint256 index;
        assembly {
            index := add(array, 0x20)
        }
        index = ArrayUtils.unsafeWriteAddress(index, order.exchange);
        index = ArrayUtils.unsafeWriteAddress(index, order.maker);
        index = ArrayUtils.unsafeWriteAddress(index, order.taker);
        index = ArrayUtils.unsafeWriteUint(index, order.makerRelayerFee);
        index = ArrayUtils.unsafeWriteUint(index, order.takerRelayerFee);
        index = ArrayUtils.unsafeWriteUint(index, order.makerProtocolFee);
        index = ArrayUtils.unsafeWriteUint(index, order.takerProtocolFee);
        index = ArrayUtils.unsafeWriteAddress(index, order.feeRecipient);
        index = ArrayUtils.unsafeWriteUint8(index, uint8(order.feeMethod));
        index = ArrayUtils.unsafeWriteUint8(index, uint8(order.side));
        index = ArrayUtils.unsafeWriteUint8(index, uint8(order.saleKind));
        index = ArrayUtils.unsafeWriteAddress(index, order.target);
        index = ArrayUtils.unsafeWriteUint8(index, uint8(order.howToCall));
        index = ArrayUtils.unsafeWriteBytes(index, order.calldata);
        index = ArrayUtils.unsafeWriteBytes(index, order.replacementPattern);
        index = ArrayUtils.unsafeWriteAddress(index, order.staticTarget);
        index = ArrayUtils.unsafeWriteBytes(index, order.staticExtradata);
        index = ArrayUtils.unsafeWriteAddress(index, order.paymentToken);
        index = ArrayUtils.unsafeWriteUint(index, order.basePrice);
        index = ArrayUtils.unsafeWriteUint(index, order.extra);
        index = ArrayUtils.unsafeWriteUint(index, order.listingTime);
        index = ArrayUtils.unsafeWriteUint(index, order.expirationTime);
        index = ArrayUtils.unsafeWriteUint(index, order.salt);
        assembly {
            hash := keccak256(add(array, 0x20), size)
        }
        return hash;
    }

    /**
     * @dev Hash an order, returning the hash that a client must sign, including the standard message prefix
     * @param order Order to hash
     * @return Hash of message prefix and order hash per Ethereum format
     */
    function hashToSign(Order memory order) internal pure returns (bytes32) {
        return keccak256("\x19Ethereum Signed Message:\n32", hashOrder(order));
    }

    /**
     * @dev Assert an order is valid and return its hash
     * @param order Order to validate
     * @param sig ECDSA signature
     */
    function requireValidOrder(Order memory order, Sig memory sig)
        internal
        view
        returns (bytes32)
    {
        bytes32 hash = hashToSign(order);
        require(validateOrder(hash, order, sig));
        return hash;
    }

    /**
     * @dev Validate order parameters (does *not* check signature validity)
     * @param order Order to validate
     */
    function validateOrderParameters(Order memory order)
        internal
        view
        returns (bool)
    {
        /* Order must be targeted at this protocol version (this Exchange contract). */
        if (order.exchange != address(this)) {
            return false;
        }

        /* Order must possess valid sale kind parameter combination. */
        if (
            !SaleKindInterface.validateParameters(
                order.saleKind,
                order.expirationTime
            )
        ) {
            return false;
        }

        /* If using the split fee method, order must have sufficient protocol fees. */
        if (
            order.feeMethod == FeeMethod.SplitFee &&
            (order.makerProtocolFee < minimumMakerProtocolFee ||
                order.takerProtocolFee < minimumTakerProtocolFee)
        ) {
            return false;
        }

        return true;
    }

    /**
     * @dev Validate a provided previously approved / signed order, hash, and signature.
     * @param hash Order hash (already calculated, passed to avoid recalculation)
     * @param order Order to validate
     * @param sig ECDSA signature
     */
    function validateOrder(
        bytes32 hash,
        Order memory order,
        Sig memory sig
    ) internal view returns (bool) {
        /* Not done in an if-conditional to prevent unnecessary ecrecover evaluation, which seems to happen even though it should short-circuit. */

        /* Order must have valid parameters. */
        if (!validateOrderParameters(order) ) {
            return false;
        }

        /* Order must have not been canceled or already filled. */
        if (cancelledOrFinalized[hash] || ICancelOrder_v4(cancelOrderAddr).getOrderStatus(hash)) {
            return false;
        }

        /* or (b) ECDSA-signed by maker. */
        if (ecrecover(hash, sig.v, sig.r, sig.s) == order.maker) {
            return true;
        }

        return false;
    }

    /**
     * @dev Cancel an order, preventing it from being matched. Must be called by the maker of the order
     * @param order Order to cancel
     * @param sig ECDSA signature
     */
    function cancelOrder(Order memory order, Sig memory sig) internal {
        /* CHECKS */

        /* Calculate order hash. */
        bytes32 hash = requireValidOrder(order, sig);

        /* Assert sender is authorized to cancel order. */
        require(msg.sender == order.maker);

        /* EFFECTS */

        /* Mark order as cancelled, preventing it from being matched. */
        cancelledOrFinalized[hash] = true;

        /* Log cancel event. */
        emit OrderCancelled(hash);
    }

    /**
     * @dev Calculate the current price of an order (convenience function)
     * @param order Order to calculate the price of
     * @return The current price of the order
     */
    function calculateCurrentPrice(Order memory order)
        internal
        view
        returns (uint256)
    {
        return
            SaleKindInterface.calculateFinalPrice(
                order.side,
                order.saleKind,
                order.basePrice,
                order.extra,
                order.listingTime,
                order.expirationTime
            );
    }

    /**
     * @dev Calculate the price two orders would match at, if in fact they would match (otherwise fail)
     * @param buy Buy-side order
     * @param sell Sell-side order
     * @return Match price
     */
    function calculateMatchPrice(Order memory buy, Order memory sell)
        internal
        view
        returns (uint256)
    {
        /* Calculate sell price. */
        uint256 sellPrice = SaleKindInterface.calculateFinalPrice(
            sell.side,
            sell.saleKind,
            sell.basePrice,
            sell.extra,
            sell.listingTime,
            sell.expirationTime
        );

        /* Calculate buy price. */
        uint256 buyPrice = SaleKindInterface.calculateFinalPrice(
            buy.side,
            buy.saleKind,
            buy.basePrice,
            buy.extra,
            buy.listingTime,
            buy.expirationTime
        );

        /* Require price cross. */
        require(buyPrice >= sellPrice);

        /* Maker/taker priority. */
        return sell.feeRecipient != address(0) ? sellPrice : buyPrice;
    }

    /**
     * @dev Execute all ERC20 token / Ether transfers associated with an order match (fees and buyer => seller transfer)
     * @param buy Buy-side order
     * @param sell Sell-side order
     */
    function executeFundsTransfer(Order memory buy, Order memory sell)
        internal
        returns (uint256)
    {
        /* Only payable in the special case of unwrapped Ether. */
        if (sell.paymentToken != address(0)) {
            require(msg.value == 0);
        }

        /* Calculate match price. */
        uint256 price = calculateMatchPrice(buy, sell);

        /* Amount that will be received by seller (for Ether). */
        uint256 receiveAmount = price;

        /* Amount that must be sent by buyer (for Ether). */
        uint256 requiredAmount = price;

        /* seller makes order, buyer takes order. (sell.feeRecipient does not zero address) */
        if (sell.feeRecipient != address(0)) {
            require(sell.takerRelayerFee <= buy.takerRelayerFee);

            tempData.calldataValue = sell.calldata;
            tempData.result = MyTools.getSlice(69, 100, tempData.calldataValue);
            tempData.tokenId = MyTools.bytesToUint(tempData.result);

            // step1 - Calculate royalty
            (
                address royaltyFeeRecipient,
                uint256 royaltyFeeAmount
            ) = okRoyaltyFeeManager.calculateRoyaltyFeeAndGetRecipient(
                    sell.target,
                    tempData.tokenId,
                    price
                );

            if (sell.feeMethod == FeeMethod.SplitFee) {
                receiveAmount = receiveAmount.sub(royaltyFeeAmount);
                if (price > 0 && sell.paymentToken == address(0)) {
                    royaltyFeeRecipient.transfer(royaltyFeeAmount);
                }
                if (price > 0 && sell.paymentToken != address(0)) {
                    // step2 - Transfer ERC20 royalty: buyer to royaltyReceiver
                    transferTokens(
                        sell.paymentToken,
                        buy.maker,
                        royaltyFeeRecipient,
                        royaltyFeeAmount
                    );
                }

                /* seller (who makes order) pays fee */
                if (sell.makerRelayerFee > 0) {
                    // step3 - Calculate fee
                    uint256 makerRelayerFee = sell
                        .makerRelayerFee
                        .mul(price)
                        .div(INVERSE_BASIS_POINT);
                    // Sub makerRelayerFee before all transfer, because of seller pays fee.
                    receiveAmount = receiveAmount.sub(makerRelayerFee);
                    if (sell.paymentToken == address(0)) {
                        sell.feeRecipient.transfer(makerRelayerFee);
                    } else {
                        // step4 - Transfer ERC20 fee: buyer to feeReceiver
                        transferTokens(
                            sell.paymentToken,
                            buy.maker,
                            sell.feeRecipient,
                            makerRelayerFee
                        );
                    }
                }

                /* buyer (who takes order) pays fee */
                if (sell.takerRelayerFee > 0) {
                    // step3 - Calculate fee
                    uint256 takerRelayerFee = sell
                        .takerRelayerFee
                        .mul(price)
                        .div(INVERSE_BASIS_POINT);

                    if (sell.paymentToken == address(0)) {
                        requiredAmount = requiredAmount.add(takerRelayerFee);
                        sell.feeRecipient.transfer(takerRelayerFee);
                    } else {
                        // step4 - Transfer ERC20 fee: buyer to feeReceiver
                        // No needs to sub makerRelayerFee, because of buyer pays fee.
                        transferTokens(
                            sell.paymentToken,
                            buy.maker,
                            sell.feeRecipient,
                            takerRelayerFee
                        );
                    }
                }
            } else {
                revert("Unsupported protocol fee mode!");
            }
        } else {
            /* buyer makes offer, seller takes offer. (buy.feeRecipient does not zero address) */
            require(buy.takerRelayerFee <= sell.takerRelayerFee);

            if (sell.feeMethod == FeeMethod.SplitFee) {
                require(sell.paymentToken != address(0));
                require(buy.takerProtocolFee <= sell.takerProtocolFee);

                // step1 - Calculate royalty
                (royaltyFeeRecipient, royaltyFeeAmount) = okRoyaltyFeeManager
                    .calculateRoyaltyFeeAndGetRecipient(
                        sell.target,
                        tempData.tokenId,
                        price
                    );

                // step2 - Transfer ERC20 royalty: buyer to royaltyReceiver
                if (price > 0 && sell.paymentToken != address(0)) {
                    receiveAmount = receiveAmount.sub(royaltyFeeAmount);
                    transferTokens(
                        sell.paymentToken,
                        buy.maker,
                        royaltyFeeRecipient,
                        royaltyFeeAmount
                    );
                }

                /* buyer (who makes offer) pays fee */
                if (buy.makerRelayerFee > 0) {
                    // step3 - Calculate fee
                    makerRelayerFee = SafeMath.div(
                        SafeMath.mul(buy.makerRelayerFee, price),
                        INVERSE_BASIS_POINT
                    );
                    // step4 - Transfer ERC20 fee: buyer to feeReceiver
                    transferTokens(
                        sell.paymentToken,
                        buy.maker,
                        buy.feeRecipient,
                        makerRelayerFee
                    );
                }

                /* seller (who taker offer) pays fee */
                if (buy.takerRelayerFee > 0) {
                    // step3 - Calculate fee
                    takerRelayerFee = SafeMath.div(
                        SafeMath.mul(buy.takerRelayerFee, price),
                        INVERSE_BASIS_POINT
                    );
                    // step4 - Transfer ERC20 fee: buyer to feeReceiver
                    receiveAmount = receiveAmount.sub(takerRelayerFee);
                    transferTokens(
                        sell.paymentToken,
                        buy.maker,
                        buy.feeRecipient,
                        takerRelayerFee
                    );
                }
            } else {
                revert("Unsupported protocol fee mode!");
            }
        }

        if (sell.paymentToken == address(0)) {
            /* Special-case Ether, order must be matched by buyer. */
            require(msg.value >= requiredAmount);
            sell.maker.transfer(receiveAmount);
            /* Allow overshoot for variable-price auctions, refund difference. */
            // uint diff = SafeMath.sub(msg.value, requiredAmount);
            uint256 diff = msg.value.sub(requiredAmount);
            if (diff > 0) {
                buy.maker.transfer(diff);
            }
        } else {
            // step5 - Transfer remains erc20: buyer to seller
            transferTokens(
                sell.paymentToken,
                buy.maker,
                sell.maker,
                receiveAmount
            );
        }

        /* This contract should never hold Ether, however, we cannot assert this, since it is impossible to prevent anyone from sending Ether e.g. with selfdestruct. */

        return price;
    }

    /**
     * @dev Return whether or not two orders can be matched with each other by basic parameters (does not check order signatures / calldata or perform static calls)
     * @param buy Buy-side order
     * @param sell Sell-side order
     * @return Whether or not the two orders can be matched
     */
    function ordersCanMatch(Order memory buy, Order memory sell)
        internal
        view
        returns (bool)
    {
        return (/* Must be opposite-side. */
        (buy.side == SaleKindInterface.Side.Buy &&
            sell.side == SaleKindInterface.Side.Sell) &&
            /* Must use same fee method. */
            (buy.feeMethod == sell.feeMethod) &&
            /* Must use same payment token. */
            (buy.paymentToken == sell.paymentToken) &&
            /* Must match maker/taker addresses. */
            (sell.taker == address(0) || sell.taker == buy.maker) &&
            (buy.taker == address(0) || buy.taker == sell.maker) &&
            /* One must be maker and the other must be taker (no bool XOR in Solidity). */
            ((sell.feeRecipient == address(0) &&
                buy.feeRecipient != address(0)) ||
                (sell.feeRecipient != address(0) &&
                    buy.feeRecipient == address(0))) &&
            /* Must match target. */
            (buy.target == sell.target) &&
            /* Must match howToCall. */
            (buy.howToCall == sell.howToCall) &&
            /* Buy-side order must be settleable. */
            SaleKindInterface.canSettleOrder(
                buy.listingTime,
                buy.expirationTime
            ) &&
            /* Sell-side order must be settleable. */
            SaleKindInterface.canSettleOrder(
                sell.listingTime,
                sell.expirationTime
            ));
    }


    function setTransferManager(TransferNFTManager _transferManager)
        public
        onlyWhitelist
    {
        transferManager = _transferManager;
    }

    /**
     * @dev Atomically match two orders, ensuring validity of the match, and execute all associated state transitions. Protected against reentrancy by a contract-global lock.
     * @param buy Buy-side order
     * @param buySig Buy-side order signature
     * @param sell Sell-side order
     * @param sellSig Sell-side order signature
     */
    function atomicMatch(
        Order memory buy,
        Sig memory buySig,
        Order memory sell,
        Sig memory sellSig,
        bytes32 metadata
    ) internal reentrancyGuard {
        /* CHECKS */

        /* Ensure buy order validity and calculate hash if necessary. */
        bytes32 buyHash;

        if (buy.maker == msg.sender) {
            require(validateOrderParameters(buy));
        } else {
            buyHash = requireValidOrder(buy, buySig);
        }

        /* Ensure sell order validity and calculate hash if necessary. */
        bytes32 sellHash;
        if (sell.maker == msg.sender) {
            require(validateOrderParameters(sell));
        } else {
            sellHash = requireValidOrder(sell, sellSig);
        }

        /* Must be matchable. */
        require(ordersCanMatch(buy, sell));

        /* Target must exist (prevent malicious selfdestructs just prior to order settlement). */
        uint256 size;
        address target = sell.target;
        assembly {
            size := extcodesize(target)
        }
        require(size > 0);

        /* Must match calldata after replacement, if specified. */
        if (buy.replacementPattern.length > 0) {
            ArrayUtils.guardedArrayReplace(
                buy.calldata,
                sell.calldata,
                buy.replacementPattern
            );
        }
        if (sell.replacementPattern.length > 0) {
            ArrayUtils.guardedArrayReplace(
                sell.calldata,
                buy.calldata,
                sell.replacementPattern
            );
        }

        require(ArrayUtils.arrayEq(buy.calldata, sell.calldata));

        /* Retrieve delegateProxy contract. */
        OwnableDelegateProxy delegateProxy = registry.proxies(sell.maker);

        /* EFFECTS */

        /* Mark previously signed or approved orders as finalized. */
        if (msg.sender != buy.maker) {
            cancelledOrFinalized[buyHash] = true;
        }
        if (msg.sender != sell.maker) {
            cancelledOrFinalized[sellHash] = true;
        }

        /* INTERACTIONS */

        /* Execute funds transfer and pay fees. */
        uint256 price = executeFundsTransfer(buy, sell);

        /*
            safe verify
            step 1. disable disable delegate mode
            step 2. verify calldata's content:from address must equals nft owner
            step 3. verify function selector
        */
        require(
            uint256(sell.howToCall) == 0,
            "DelegateCall mode is not supported"
        );

        //safeTransferFrom from  to tokenId
        //verify from
        tempData.functionName = MyTools.getSlice(1, 4, sell.calldata);

        tempData.result = MyTools.getSlice(5, 36, sell.calldata);
        tempData.result = MyTools.getSlice(13, 32, tempData.result);
        tempData.nftOwner = MyTools.bytesToAddress(tempData.result);
        require(
            sell.maker == tempData.nftOwner,
            "the sell's maker is not nftOwner!"
        );

        tempData.functionNameToBytes4 = MyTools.bytesToBytes4(
            tempData.functionName
        );
        //check function selector
        verifyFunctionSelecotr();

        /* Execute specified call through proxy. */
        //require(proxy.proxy(sell.target, sell.howToCall, sell.calldata));
        //address[4] should be explain by point a contract address
        if (delegateProxy != address(0)) {
            require(
                delegateProxy.implementation() ==
                    registry.delegateProxyImplementation()
            );

            AuthenticatedProxy proxy = AuthenticatedProxy(delegateProxy);

            require(proxy.proxy(sell.target, sell.howToCall, sell.calldata));
        } else {
            bool callResult = transferManager.proxy(
                sell.target,
                uint256(sell.howToCall),
                sell.calldata
            );
            require(callResult, "nft transfer failed");
        }

        /* Static calls are intentionally done after the effectful call so they can check resulting state. */

        /* Handle buy-side static call if specified. */
        if (buy.staticTarget != address(0)) {
            require(
                staticCall(buy.staticTarget, sell.calldata, buy.staticExtradata)
            );
        }

        /* Handle sell-side static call if specified. */
        if (sell.staticTarget != address(0)) {
            require(
                staticCall(
                    sell.staticTarget,
                    sell.calldata,
                    sell.staticExtradata
                )
            );
        }

        /* Log match event. */
        emit OrdersMatched(
            buyHash,
            sellHash,
            sell.feeRecipient != address(0) ? sell.maker : buy.maker,
            sell.feeRecipient != address(0) ? buy.maker : sell.maker,
            price,
            metadata
        );
    }

    function verifyFunctionSelecotr() internal {
        require(
            (tempData.functionNameToBytes4 == FUNCTION_TRANSFERFROM) ||
                (tempData.functionNameToBytes4 == FUNCTION_SAFETRANSFERFROM) ||
                (tempData.functionNameToBytes4 ==
                    FUNCTION_SAFETRANSFERFROM_CALL) ||
                (tempData.functionNameToBytes4 ==
                    FUNCTION_SAFETRANSFERFROM_1155) ||
                (tempData.functionNameToBytes4 ==
                    FUNCTION_SAFEBATCHTRANSFERFROM_1155),
            "function selector verify error!"
        );
    }
}

contract Exchange is ExchangeCore {
    /**
     * @dev Call guardedArrayReplace - library function exposed for testing.
     */
    function guardedArrayReplace(
        bytes array,
        bytes desired,
        bytes mask
    ) public pure returns (bytes) {
        ArrayUtils.guardedArrayReplace(array, desired, mask);
        return array;
    }

    /**
     * @dev Call calculateFinalPrice - library function exposed for testing.
     */
    function calculateFinalPrice(
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        uint256 basePrice,
        uint256 extra,
        uint256 listingTime,
        uint256 expirationTime
    ) public view returns (uint256) {
        return
            SaleKindInterface.calculateFinalPrice(
                side,
                saleKind,
                basePrice,
                extra,
                listingTime,
                expirationTime
            );
    }

    /**
     * @dev Call hashOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function hashOrder_(
        address[7] addrs,
        uint256[9] uints,
        FeeMethod feeMethod,
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        AuthenticatedProxy.HowToCall howToCall,
        bytes calldata,
        bytes replacementPattern,
        bytes staticExtradata
    ) public pure returns (bytes32) {
        return
            hashOrder(
                Order(
                    addrs[0],
                    addrs[1],
                    addrs[2],
                    uints[0],
                    uints[1],
                    uints[2],
                    uints[3],
                    addrs[3],
                    feeMethod,
                    side,
                    saleKind,
                    addrs[4],
                    howToCall,
                    calldata,
                    replacementPattern,
                    addrs[5],
                    staticExtradata,
                    ERC20(addrs[6]),
                    uints[4],
                    uints[5],
                    uints[6],
                    uints[7],
                    uints[8]
                )
            );
    }

    /**
     * @dev Call hashToSign - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function hashToSign_(
        address[7] addrs,
        uint256[9] uints,
        FeeMethod feeMethod,
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        AuthenticatedProxy.HowToCall howToCall,
        bytes calldata,
        bytes replacementPattern,
        bytes staticExtradata
    ) public pure returns (bytes32) {
        return
            hashToSign(
                Order(
                    addrs[0],
                    addrs[1],
                    addrs[2],
                    uints[0],
                    uints[1],
                    uints[2],
                    uints[3],
                    addrs[3],
                    feeMethod,
                    side,
                    saleKind,
                    addrs[4],
                    howToCall,
                    calldata,
                    replacementPattern,
                    addrs[5],
                    staticExtradata,
                    ERC20(addrs[6]),
                    uints[4],
                    uints[5],
                    uints[6],
                    uints[7],
                    uints[8]
                )
            );
    }

    /**
     * @dev Call validateOrderParameters - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function validateOrderParameters_(
        address[7] addrs,
        uint256[9] uints,
        FeeMethod feeMethod,
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        AuthenticatedProxy.HowToCall howToCall,
        bytes calldata,
        bytes replacementPattern,
        bytes staticExtradata
    ) public view returns (bool) {
        Order memory order = Order(
            addrs[0],
            addrs[1],
            addrs[2],
            uints[0],
            uints[1],
            uints[2],
            uints[3],
            addrs[3],
            feeMethod,
            side,
            saleKind,
            addrs[4],
            howToCall,
            calldata,
            replacementPattern,
            addrs[5],
            staticExtradata,
            ERC20(addrs[6]),
            uints[4],
            uints[5],
            uints[6],
            uints[7],
            uints[8]
        );
        return validateOrderParameters(order);
    }

    /**
     * @dev Call validateOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function validateOrder_(
        address[7] addrs,
        uint256[9] uints,
        FeeMethod feeMethod,
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        AuthenticatedProxy.HowToCall howToCall,
        bytes calldata,
        bytes replacementPattern,
        bytes staticExtradata,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public view returns (bool) {
        Order memory order = Order(
            addrs[0],
            addrs[1],
            addrs[2],
            uints[0],
            uints[1],
            uints[2],
            uints[3],
            addrs[3],
            feeMethod,
            side,
            saleKind,
            addrs[4],
            howToCall,
            calldata,
            replacementPattern,
            addrs[5],
            staticExtradata,
            ERC20(addrs[6]),
            uints[4],
            uints[5],
            uints[6],
            uints[7],
            uints[8]
        );
        return validateOrder(hashToSign(order), order, Sig(v, r, s));
    }

    /**
     * @dev Call cancelOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function cancelOrder_(
        address[7] addrs,
        uint256[9] uints,
        FeeMethod feeMethod,
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        AuthenticatedProxy.HowToCall howToCall,
        bytes calldata,
        bytes replacementPattern,
        bytes staticExtradata,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        return
            cancelOrder(
                Order(
                    addrs[0],
                    addrs[1],
                    addrs[2],
                    uints[0],
                    uints[1],
                    uints[2],
                    uints[3],
                    addrs[3],
                    feeMethod,
                    side,
                    saleKind,
                    addrs[4],
                    howToCall,
                    calldata,
                    replacementPattern,
                    addrs[5],
                    staticExtradata,
                    ERC20(addrs[6]),
                    uints[4],
                    uints[5],
                    uints[6],
                    uints[7],
                    uints[8]
                ),
                Sig(v, r, s)
            );
    }

    /**
     * @dev Call calculateCurrentPrice - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function calculateCurrentPrice_(
        address[7] addrs,
        uint256[9] uints,
        FeeMethod feeMethod,
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        AuthenticatedProxy.HowToCall howToCall,
        bytes calldata,
        bytes replacementPattern,
        bytes staticExtradata
    ) public view returns (uint256) {
        return
            calculateCurrentPrice(
                Order(
                    addrs[0],
                    addrs[1],
                    addrs[2],
                    uints[0],
                    uints[1],
                    uints[2],
                    uints[3],
                    addrs[3],
                    feeMethod,
                    side,
                    saleKind,
                    addrs[4],
                    howToCall,
                    calldata,
                    replacementPattern,
                    addrs[5],
                    staticExtradata,
                    ERC20(addrs[6]),
                    uints[4],
                    uints[5],
                    uints[6],
                    uints[7],
                    uints[8]
                )
            );
    }

    /**
     * @dev Call ordersCanMatch - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function ordersCanMatch_(
        address[14] addrs,
        uint256[18] uints,
        uint8[8] feeMethodsSidesKindsHowToCalls,
        bytes calldataBuy,
        bytes calldataSell,
        bytes replacementPatternBuy,
        bytes replacementPatternSell,
        bytes staticExtradataBuy,
        bytes staticExtradataSell
    ) public view returns (bool) {
        Order memory buy = Order(
            addrs[0],
            addrs[1],
            addrs[2],
            uints[0],
            uints[1],
            uints[2],
            uints[3],
            addrs[3],
            FeeMethod(feeMethodsSidesKindsHowToCalls[0]),
            SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[1]),
            SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[2]),
            addrs[4],
            AuthenticatedProxy.HowToCall(feeMethodsSidesKindsHowToCalls[3]),
            calldataBuy,
            replacementPatternBuy,
            addrs[5],
            staticExtradataBuy,
            ERC20(addrs[6]),
            uints[4],
            uints[5],
            uints[6],
            uints[7],
            uints[8]
        );
        Order memory sell = Order(
            addrs[7],
            addrs[8],
            addrs[9],
            uints[9],
            uints[10],
            uints[11],
            uints[12],
            addrs[10],
            FeeMethod(feeMethodsSidesKindsHowToCalls[4]),
            SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[5]),
            SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[6]),
            addrs[11],
            AuthenticatedProxy.HowToCall(feeMethodsSidesKindsHowToCalls[7]),
            calldataSell,
            replacementPatternSell,
            addrs[12],
            staticExtradataSell,
            ERC20(addrs[13]),
            uints[13],
            uints[14],
            uints[15],
            uints[16],
            uints[17]
        );
        return ordersCanMatch(buy, sell);
    }

    /**
     * @dev Return whether or not two orders' calldata specifications can match
     * @param buyCalldata Buy-side order calldata
     * @param buyReplacementPattern Buy-side order calldata replacement mask
     * @param sellCalldata Sell-side order calldata
     * @param sellReplacementPattern Sell-side order calldata replacement mask
     * @return Whether the orders' calldata can be matched
     */
    function orderCalldataCanMatch(
        bytes buyCalldata,
        bytes buyReplacementPattern,
        bytes sellCalldata,
        bytes sellReplacementPattern
    ) public pure returns (bool) {
        if (buyReplacementPattern.length > 0) {
            ArrayUtils.guardedArrayReplace(
                buyCalldata,
                sellCalldata,
                buyReplacementPattern
            );
        }
        if (sellReplacementPattern.length > 0) {
            ArrayUtils.guardedArrayReplace(
                sellCalldata,
                buyCalldata,
                sellReplacementPattern
            );
        }
        return ArrayUtils.arrayEq(buyCalldata, sellCalldata);
    }

    /**
     * @dev Call calculateMatchPrice - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function calculateMatchPrice_(
        address[14] addrs,
        uint256[18] uints,
        uint8[8] feeMethodsSidesKindsHowToCalls,
        bytes calldataBuy,
        bytes calldataSell,
        bytes replacementPatternBuy,
        bytes replacementPatternSell,
        bytes staticExtradataBuy,
        bytes staticExtradataSell
    ) public view returns (uint256) {
        Order memory buy = Order(
            addrs[0],
            addrs[1],
            addrs[2],
            uints[0],
            uints[1],
            uints[2],
            uints[3],
            addrs[3],
            FeeMethod(feeMethodsSidesKindsHowToCalls[0]),
            SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[1]),
            SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[2]),
            addrs[4],
            AuthenticatedProxy.HowToCall(feeMethodsSidesKindsHowToCalls[3]),
            calldataBuy,
            replacementPatternBuy,
            addrs[5],
            staticExtradataBuy,
            ERC20(addrs[6]),
            uints[4],
            uints[5],
            uints[6],
            uints[7],
            uints[8]
        );
        Order memory sell = Order(
            addrs[7],
            addrs[8],
            addrs[9],
            uints[9],
            uints[10],
            uints[11],
            uints[12],
            addrs[10],
            FeeMethod(feeMethodsSidesKindsHowToCalls[4]),
            SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[5]),
            SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[6]),
            addrs[11],
            AuthenticatedProxy.HowToCall(feeMethodsSidesKindsHowToCalls[7]),
            calldataSell,
            replacementPatternSell,
            addrs[12],
            staticExtradataSell,
            ERC20(addrs[13]),
            uints[13],
            uints[14],
            uints[15],
            uints[16],
            uints[17]
        );
        return calculateMatchPrice(buy, sell);
    }

    /**
     * @dev Call atomicMatch - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function atomicMatch_(
        address[14] addrs,
        uint256[18] uints,
        uint8[8] feeMethodsSidesKindsHowToCalls,
        bytes calldataBuy,
        bytes calldataSell,
        bytes replacementPatternBuy,
        bytes replacementPatternSell,
        bytes staticExtradataBuy,
        bytes staticExtradataSell,
        uint8[2] vs,
        bytes32[5] rssMetadata
    ) public payable {
        return
            atomicMatch(
                Order(
                    addrs[0],
                    addrs[1],
                    addrs[2],
                    uints[0],
                    uints[1],
                    uints[2],
                    uints[3],
                    addrs[3],
                    FeeMethod(feeMethodsSidesKindsHowToCalls[0]),
                    SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[1]),
                    SaleKindInterface.SaleKind(
                        feeMethodsSidesKindsHowToCalls[2]
                    ),
                    addrs[4],
                    AuthenticatedProxy.HowToCall(
                        feeMethodsSidesKindsHowToCalls[3]
                    ),
                    calldataBuy,
                    replacementPatternBuy,
                    addrs[5],
                    staticExtradataBuy,
                    ERC20(addrs[6]),
                    uints[4],
                    uints[5],
                    uints[6],
                    uints[7],
                    uints[8]
                ),
                Sig(vs[0], rssMetadata[0], rssMetadata[1]),
                Order(
                    addrs[7],
                    addrs[8],
                    addrs[9],
                    uints[9],
                    uints[10],
                    uints[11],
                    uints[12],
                    addrs[10],
                    FeeMethod(feeMethodsSidesKindsHowToCalls[4]),
                    SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[5]),
                    SaleKindInterface.SaleKind(
                        feeMethodsSidesKindsHowToCalls[6]
                    ),
                    addrs[11],
                    AuthenticatedProxy.HowToCall(
                        feeMethodsSidesKindsHowToCalls[7]
                    ),
                    calldataSell,
                    replacementPatternSell,
                    addrs[12],
                    staticExtradataSell,
                    ERC20(addrs[13]),
                    uints[13],
                    uints[14],
                    uints[15],
                    uints[16],
                    uints[17]
                ),
                Sig(vs[1], rssMetadata[2], rssMetadata[3]),
                rssMetadata[4]
            );
    }

    function validateErc(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address maker
    ) public pure returns (bool) {
        if (ecrecover(hash, v, r, s) == maker) {
            return true;
        }
    }
}

contract OKOffChainExchange is Exchange {
    string public constant name = "OKEX OffChain Change";

    string public constant version = "0.1";

    string public constant codename = "Diego";

    function changeExchangeToken(ERC20 tokenAddress) public onlyWhitelist {
        exchangeToken = tokenAddress;
    }

    function changeCopyrightReceiver(address protocolFeeAddress)
        public
        onlyWhitelist
    {
        protocolFeeRecipient = protocolFeeAddress;
    }

    bool private onlyInitOnce;

    /**
     * @dev Initialize a WyvernExchange instance
     * @param registryAddress Address of the registry instance which this Exchange instance will use
     * @param tokenAddress Address of the token used for protocol fees
     */
    function init(
        ProxyRegistry registryAddress,
        TokenTransferProxy tokenTransferProxyAddress,
        ERC20 tokenAddress,
        address protocolFeeAddress
    ) public {
        require(!onlyInitOnce, "already initialized");
        onlyInitOnce = true;
        registry = registryAddress;
        tokenTransferProxy = tokenTransferProxyAddress;
        //use to pay fee token,but only protocol mode on active.now OKX nft marketplace use split mode
        //so exchangeToken unused
        exchangeToken = tokenAddress;
        //the value unused
        protocolFeeRecipient = protocolFeeAddress;
        owner = msg.sender;
    }
}

