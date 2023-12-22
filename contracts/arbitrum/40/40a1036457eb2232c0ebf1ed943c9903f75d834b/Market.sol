//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./ERC1155Holder.sol";
import "./ReentrancyGuard.sol";
import "./IConditionalTokens.sol";

/**
 * @dev This contract is an on chain orderbook for 2 outcome markets. It is created and managed by the MarketFactory contract.
 * The market uses gnosis' ConditionalToken framework as the settlement layer.
 */
contract Market is Ownable, ReentrancyGuard, ERC1155Holder {

    struct BidData {
        uint256 price;
        uint256 amountShares;
        address creator;
        bytes32 nextBestOrderId;
        bool isConditionalTokenShares;
    }

    bytes32 public constant EMPTY_BYTES = bytes32(0);

    uint[] public BINARY_PARTITION = [1, 2];
    bool public isMarketActive = true;

    // The token all trades are settled in (USDC)
    address public collateralToken;
    // The conditional token for the market
    address public conditionalToken;
    // The conditionId of the market
    bytes32 public conditionId;
    // Collateral token decimals
    uint public collateralTokenDecimals;
    // Min amount of collateral per limit order
    uint public minAmount;
    // Fee on volume (in 1e6)
    uint public fee;
    // Fee recipient
    address feeRecipient;

    // outcome (0,1) => positionId (in conditional tokens)
    mapping (uint => uint) public outcomePositionIds;
    // outcome (0,1) => bidCount
    mapping (uint => uint) public outcomeBidCount;
    // outcome (0,1) => bestBid (id)
    mapping (uint => bytes32) public bestBid;
    // outcome (0,1) => orderId => BidData
    mapping(uint => mapping(bytes32 => BidData)) public outcomeBids;

    event NewBid(uint indexed outcome, uint price, uint amount, address indexed creator, bool isConditionalTokenShares);
    event NewBestBid(uint indexed outcome, uint price, uint amount, address indexed creator, bool isConditionalTokenShares, uint256 timestamp);

    modifier validPrice(uint price) {
        require(0 < price && price < 1e6, "E2");
        _;
    }

    constructor(
        address _collateralToken,
        address _conditionalToken,
        bytes32 _conditionId,
        uint _positionIdOutcome0,
        uint _positionIdOutcome1,
        uint _minAmount,
        uint _fee,
        address _feeRecipient
    ) {
        require(_fee <= 1e5, "Fee cannot be greater than 10%");
        collateralToken = _collateralToken;
        conditionalToken = _conditionalToken;
        conditionId = _conditionId;
        outcomePositionIds[0] = _positionIdOutcome0;
        outcomePositionIds[1] = _positionIdOutcome1;
        minAmount = _minAmount;
        fee = _fee;
        feeRecipient = _feeRecipient;
        collateralTokenDecimals = ERC20(_collateralToken).decimals();
        IERC20(_collateralToken).approve(_conditionalToken, type(uint256).max);
    }

    /**
     * @dev Places a limit order for a given outcome, fills any existing orders first if possible.
     * Amount in denominated in collateral token.
     * 
     * @param outcome The desired outcome to buy
     * @param price The desired price to buy outcome shares at
     * @param amountCollateral The desired amount of collateral to use
     */
    function limitOrderCollateral(uint outcome, uint price, uint amountCollateral) public nonReentrant validPrice(price) returns (bytes32) {
        require(amountCollateral >= minAmount, "E3");
        IERC20(collateralToken).transferFrom(msg.sender, address(this), amountCollateral);
        uint amountShares = (amountCollateral * 1e6) / price;

        return _limitOrder(outcome, price, amountShares);
    }

    /**
     * @dev Places a limit order for a given outcome, fills any existing orders first if possible.
     * Amount in denominated in conditional token shares. 
     * 
     * @param outcome The desired outcome to buy
     * @param price The desired price to buy outcome shares at
     * @param amountShares The desired amount of shares to buy
     */
    function limitOrder(uint outcome, uint price, uint amountShares) public nonReentrant validPrice(price) returns (bytes32) {
        uint amountCollateral = (amountShares * price) / 1e6;
        require(amountCollateral >= minAmount, "E3");
        IERC20(collateralToken).transferFrom(msg.sender, address(this), amountCollateral);

        return _limitOrder(outcome, price, amountShares);
    }

    /**
     * @dev Places a limit order for a given outcome, fills any existing orders first if possible.
     * 
     * @param outcome The desired outcome to buy
     * @param price The desired price to buy outcome shares at
     * @param amountShares The desired amount of shares to sell
     */
    function limitOrderSell(uint outcome, uint price, uint amountShares) public nonReentrant returns (bytes32) {
        require(isMarketActive, "E1");
        require(0 < price && price < 1e6, "E2");

        IConditionalTokens(conditionalToken).safeTransferFrom(
            msg.sender, 
            address(this),
            outcomePositionIds[outcome], 
            amountShares,
            new bytes(0)
        );

        uint collateralAmount = amountShares * price / 1e6;
        require(collateralAmount >= minAmount, "E3");

        amountShares = _fillOrdersShares(outcome, price, amountShares);
        if (amountShares == 0) return EMPTY_BYTES;
        uint oppositeOutcome = 1 - outcome;
        uint bidPrice = 1e6 - price;
        return _postOrder(oppositeOutcome, bidPrice, amountShares, true);
    }

    /**
     * @dev Sells a given amount of shares for the best price possible, for at.
     * 
     * @param outcome The desired outcome shares to sell
     * @param amountShares The desired amount of shares to sell
     * @param maxPrice The max price to sell shares at.
     */
    function marketSell(uint outcome, uint amountShares, uint maxPrice) public nonReentrant {
        require(isMarketActive, "E1");
        IConditionalTokens(conditionalToken).safeTransferFrom(
            msg.sender, 
            address(this),
            outcomePositionIds[outcome], 
            amountShares,
            new bytes(0)
        );
        require(bestBid[outcome] != bytes32(0), "E3");

        amountShares = _fillOrdersShares(outcome, 1e6 - maxPrice, amountShares);
        if (amountShares > 0) {
            IConditionalTokens(conditionalToken).safeTransferFrom(
                address(this),
                msg.sender, 
                outcomePositionIds[outcome], 
                amountShares,
                new bytes(0)
            );
        }
    }


    /**
     * @dev Buy a given amount of shares for the best price possible, for at most maxPrice.
     * 
     * @param outcome The desired outcome shares to buy
     * @param amount The desired amount of collateral tokens to buy with
     * @param maxPrice The max price to buy shares at.
     */
    function marketBuy(uint outcome, uint amount, uint maxPrice) public nonReentrant {
        require(isMarketActive, "E1");
        IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);
        uint oppositeOutcome = 1 - outcome;
        require(bestBid[oppositeOutcome] != bytes32(0), "E3");
        amount = _fillOrdersCollateralToken(outcome, maxPrice, amount);
        if (amount > 0) IERC20(collateralToken).transfer(msg.sender, amount);
    }

    /**
     * @dev Cancels an order.
     * 
     * @param outcome The outcome to cancel orders for
     * @param orderId The orderId of the order to cancel
     * @param prevBestOrderId The max price to buy shares at.
     */
    function cancelOrder(uint outcome, bytes32 orderId, bytes32 prevBestOrderId) external {
        require(outcomeBids[outcome][orderId].creator == msg.sender, "E5");
        if (prevBestOrderId == bytes32(0)) {
            require(bestBid[outcome] == orderId, "E6");
            bestBid[outcome] = outcomeBids[outcome][orderId].nextBestOrderId;
        } else {
            require(outcomeBids[outcome][prevBestOrderId].nextBestOrderId == orderId, "E7");
            outcomeBids[outcome][prevBestOrderId].nextBestOrderId = outcomeBids[outcome][orderId].nextBestOrderId;
        }

        uint amountShares = outcomeBids[outcome][orderId].amountShares;
        outcomeBids[outcome][orderId].amountShares = 0;
        if (outcomeBids[outcome][orderId].isConditionalTokenShares) {
            uint oppositeOutcome = 1 - outcome;
            IConditionalTokens(conditionalToken).safeTransferFrom(
                address(this),
                msg.sender, 
                outcomePositionIds[oppositeOutcome], 
                amountShares,
                new bytes(0)
            );
        } else {
            uint collateralAmount = amountShares * outcomeBids[outcome][orderId].price / 1e6;
            IERC20(collateralToken).transfer(msg.sender, collateralAmount);
        }
        outcomeBidCount[outcome]--;
    }

    /**
     * @dev Bulk cancels orders, owner only when market is paused.
     * 
     * @param limit The max number of orders to cancel
     */
    function bulkCancelOrders(uint limit) external onlyOwner {
        require(!isMarketActive, "E1");
        uint i = 0;
        uint outcome = 0;
        while (i < limit) {
            bytes32 orderId = bestBid[outcome];
            if (orderId == bytes32(0)) {
                outcome++;
                if (outcome == 2) break;
                continue; 
            }
            BidData memory bid = outcomeBids[outcome][orderId];
            outcomeBids[outcome][orderId].amountShares = 0;
            if (bid.isConditionalTokenShares) {
                uint oppositeOutcome = 1 - outcome;
                IConditionalTokens(conditionalToken).safeTransferFrom(
                    address(this),
                    bid.creator,
                    outcomePositionIds[oppositeOutcome], 
                    bid.amountShares,
                    new bytes(0)
                );
            } else {
                uint collateralAmount = bid.amountShares * bid.price / 1e6;
                IERC20(collateralToken).transfer(bid.creator, collateralAmount);
            }
            bestBid[outcome] = bid.nextBestOrderId;
            outcomeBidCount[outcome]--;
            i++;
        }
    }

    function _limitOrder(uint outcome, uint price, uint amountShares) internal returns (bytes32) {
        require(isMarketActive, "E1");
        require(0 < price && price < 1e6, "E2");

        amountShares = _fillOrders(outcome, 1e6 - price, amountShares);
        if (amountShares == 0) return EMPTY_BYTES;
        return _postOrder(outcome, price, amountShares, false);
    }

    function _postOrder(uint outcome, uint price, uint amount, bool isConditionalShares) internal returns (bytes32) {
        bytes32 orderId = keccak256(abi.encodePacked(outcome, msg.sender, price, amount));
        require(outcomeBids[outcome][orderId].amountShares == 0, "Order with these details already exists");

        bytes32 bestBidOrderId = bestBid[outcome];
        // If first bid
        if (bestBidOrderId == bytes32(0)) {
            bestBid[outcome] = orderId;
            outcomeBids[outcome][orderId] = BidData(price, amount, msg.sender, bytes32(0), isConditionalShares);
            emit NewBestBid(outcome, price, amount, msg.sender, isConditionalShares, block.timestamp);
        } else {
            // If best bid
            if (outcomeBids[outcome][bestBidOrderId].price < price) {
                outcomeBids[outcome][orderId] = BidData(price, amount, msg.sender, bestBidOrderId, isConditionalShares);
                bestBid[outcome] = orderId;
                emit NewBestBid(outcome, price, amount, msg.sender, isConditionalShares, block.timestamp );
            } else {
                // If not best bid
                bytes32 currentBestOrderId = bestBidOrderId;
                bytes32 nextBestOrderId = outcomeBids[outcome][currentBestOrderId].nextBestOrderId;
                while (nextBestOrderId != bytes32(0)) {
                    if (outcomeBids[outcome][nextBestOrderId].price < price) {
                        outcomeBids[outcome][currentBestOrderId].nextBestOrderId = orderId;
                        outcomeBids[outcome][orderId].nextBestOrderId = nextBestOrderId;
                        outcomeBids[outcome][orderId] = BidData(price, amount, msg.sender, nextBestOrderId, isConditionalShares);
                        break;
                    }
                    currentBestOrderId = nextBestOrderId;
                    nextBestOrderId = outcomeBids[outcome][currentBestOrderId].nextBestOrderId;
                }
                // If worst bid
                if (nextBestOrderId == bytes32(0)) {
                    outcomeBids[outcome][currentBestOrderId].nextBestOrderId = orderId;
                    outcomeBids[outcome][orderId] = BidData(price, amount, msg.sender, bytes32(0), isConditionalShares);
                }
            }
        }
        outcomeBidCount[outcome]++;
        emit NewBid(outcome, price, amount, msg.sender, isConditionalShares);
        return orderId;
    }

    /**
     * @dev Fills orders up until `maxPrice` and `amount` is reached. Returns the remaining amount.
     */
    function _fillOrdersShares(uint outcome, uint maxPrice, uint amountShares) internal returns (uint) {
        bytes32 bestBidOrderId = bestBid[outcome];

        while (amountShares > 0) {
            uint bestBidAmount = outcomeBids[outcome][bestBidOrderId].amountShares;
            uint bestBidPrice = outcomeBids[outcome][bestBidOrderId].price;
            if (bestBidAmount == 0 || bestBidPrice < maxPrice) break;

            uint finalAmountShares = bestBidAmount > amountShares ? amountShares : bestBidAmount;
            outcomeBids[outcome][bestBidOrderId].amountShares -= finalAmountShares;
            amountShares -= finalAmountShares;
            if (outcomeBids[outcome][bestBidOrderId].isConditionalTokenShares) {
                IConditionalTokens(conditionalToken).mergePositions(
                    collateralToken,
                    EMPTY_BYTES, 
                    conditionId,
                    BINARY_PARTITION,
                    finalAmountShares
                );
                _transferTokensWithFee(
                    outcomeBids[outcome][bestBidOrderId].creator,
                    outcomeBids[outcome][bestBidOrderId].price * 1e6 / finalAmountShares
                );
                _transferTokensWithFee(
                    msg.sender,
                    (1e6 - outcomeBids[outcome][bestBidOrderId].price) * 1e6 / finalAmountShares
                );
            } else {
                uint collateralAmount = finalAmountShares * outcomeBids[outcome][bestBidOrderId].price / 1e6;
                _transferConditionalTokensWithFee(
                    outcomeBids[outcome][bestBidOrderId].creator,
                    outcomePositionIds[outcome],
                    finalAmountShares
                );
                _transferTokensWithFee(msg.sender, collateralAmount);
            }
            if (bestBidAmount <= finalAmountShares) {
                bestBidOrderId = outcomeBids[outcome][bestBidOrderId].nextBestOrderId;
                outcomeBidCount[outcome]--;
            }
        }
        
        bestBid[outcome] = bestBidOrderId;
        return amountShares;
    }

    /**
     * @dev Fills orders up until `maxPrice` and `amount` is reached. Returns the remaining amount.
     */
    function _fillOrders(uint outcome, uint maxPrice, uint amountShares) internal returns (uint) {
        uint oppositeOutcome = 1 - outcome;
        bytes32 bestBidOrderId = bestBid[oppositeOutcome];
        if (bestBidOrderId == bytes32(0)) return amountShares;

        while (amountShares > 0) {
            uint bestBidAmount = outcomeBids[oppositeOutcome][bestBidOrderId].amountShares;
            uint bestBidPrice = outcomeBids[oppositeOutcome][bestBidOrderId].price;
            if (bestBidAmount == 0 || bestBidPrice < maxPrice) break;

            uint finalAmountShares = bestBidAmount > amountShares ? amountShares : bestBidAmount;
            uint collateralAmount = finalAmountShares * outcomeBids[oppositeOutcome][bestBidOrderId].price / 1e6;
            outcomeBids[oppositeOutcome][bestBidOrderId].amountShares -= finalAmountShares;
            amountShares -= amountShares * maxPrice / bestBidPrice;
            if (outcomeBids[oppositeOutcome][bestBidOrderId].isConditionalTokenShares) {
                // transfer shares to msg.sender
                _transferConditionalTokensWithFee(
                    msg.sender,
                    outcomePositionIds[outcome],
                    finalAmountShares
                );
                _transferTokensWithFee(
                    outcomeBids[oppositeOutcome][bestBidOrderId].creator,
                    collateralAmount
                );
            } else {
                _splitConditionalTokens(
                    outcomeBids[oppositeOutcome][bestBidOrderId].creator,
                    oppositeOutcome,
                    msg.sender,
                    outcome,
                    finalAmountShares
                );
            }
            if (bestBidAmount <= finalAmountShares) {
                bestBidOrderId = outcomeBids[oppositeOutcome][bestBidOrderId].nextBestOrderId;
                outcomeBidCount[oppositeOutcome]--;
            }
        }

        bestBid[oppositeOutcome] = bestBidOrderId;
        return amountShares;
    }

    /**
     * @dev Fills orders up until `maxPrice` and `amount` is reached. Returns the remaining amount.
     */
    function _fillOrdersCollateralToken(uint outcome, uint maxPrice, uint amountCollateral) internal returns (uint) {
        uint oppositeOutcome = 1 - outcome;
        bytes32 bestBidOrderId = bestBid[oppositeOutcome];
        if (bestBidOrderId == bytes32(0)) return amountCollateral;

        // Rounding
        while (amountCollateral > 1) {
            uint bestBidAmount = outcomeBids[oppositeOutcome][bestBidOrderId].amountShares;
            uint bestBidPrice = outcomeBids[oppositeOutcome][bestBidOrderId].price;
            if (bestBidAmount == 0 || bestBidPrice > maxPrice) break;

            uint amountSharesFromCollateral = amountCollateral * 1e6 / (1e6 - bestBidPrice);
            uint finalAmountShares = bestBidAmount > amountSharesFromCollateral ? amountSharesFromCollateral : bestBidAmount;
            amountCollateral -= finalAmountShares * (1e6 - bestBidPrice) / 1e6;
            outcomeBids[oppositeOutcome][bestBidOrderId].amountShares -= finalAmountShares;

            if (outcomeBids[oppositeOutcome][bestBidOrderId].isConditionalTokenShares) {
                // transfer shares to msg.sender
                _transferConditionalTokensWithFee(
                    msg.sender,
                    outcomePositionIds[outcome],
                    finalAmountShares
                );
                _transferTokensWithFee(
                    outcomeBids[oppositeOutcome][bestBidOrderId].creator,
                    finalAmountShares * (1e6 - bestBidPrice) / 1e6
                );
            } else {
                _splitConditionalTokens(
                    outcomeBids[oppositeOutcome][bestBidOrderId].creator,
                    oppositeOutcome,
                    msg.sender,
                    outcome,
                    finalAmountShares
                );
            }
            if (bestBidAmount <= finalAmountShares) {
                bestBidOrderId = outcomeBids[oppositeOutcome][bestBidOrderId].nextBestOrderId;
                outcomeBidCount[oppositeOutcome]--;
            }
        }

        bestBid[oppositeOutcome] = bestBidOrderId;
        return amountCollateral;
    }

    function _splitConditionalTokens(
        address recipient1,
        uint outcomeRecipient1,
        address recipient2,
        uint outcomeRecipient2,
        uint amount
    ) internal {
            IConditionalTokens(conditionalToken).splitPosition(
                collateralToken,
                EMPTY_BYTES,
                conditionId,
                BINARY_PARTITION,
                amount
            );
            uint positionIdRecipient1 = outcomePositionIds[outcomeRecipient1];
            uint positionIdRecipient2 = outcomePositionIds[outcomeRecipient2];
            _transferConditionalTokensWithFee(
                recipient1,
                positionIdRecipient1,
                amount
            );
            _transferConditionalTokensWithFee(
                recipient2,
                positionIdRecipient2,
                amount
            );
    }

    function _transferTokensWithFee(address _to, uint _amount) internal {
        uint feeAmount = _amount * fee / 1e6;
        if (feeAmount > 0) IERC20(collateralToken).transfer(
            feeRecipient,
            feeAmount
        );
        IERC20(collateralToken).transfer(
            _to,
            _amount - feeAmount
        );
    }

    function _transferConditionalTokensWithFee(address _to, uint positionId, uint _amount) internal {
        uint feeAmount = _amount * fee / 1e6;
        if (feeAmount > 0) IConditionalTokens(conditionalToken).safeTransferFrom(
            address(this),
            feeRecipient, 
            positionId, 
            feeAmount,
            new bytes(0)
        );
        IConditionalTokens(conditionalToken).safeTransferFrom(
            address(this),
            _to, 
            positionId, 
            _amount - feeAmount,
            new bytes(0)
        );
    }

    function toggleMarketStatus() external onlyOwner {
        isMarketActive = !isMarketActive;
    }

    function setFee(uint _fee) external onlyOwner {
        require(_fee <= 1e5, "Fee cannot be greater than 10%");
        fee = _fee;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function getAllOutcomeBids(uint outcome) external view returns (BidData[] memory) {
        uint bidCount = outcomeBidCount[outcome];
        BidData[] memory bids = new BidData[](bidCount);
        bytes32 currentBestOrderId = bestBid[outcome];
        uint i = 0;
        while (currentBestOrderId != bytes32(0)) {
            bids[i] = outcomeBids[outcome][currentBestOrderId];
            currentBestOrderId = outcomeBids[outcome][currentBestOrderId].nextBestOrderId;
            i++;
        }
        return bids;
    }
}

