// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./BaseStorage.sol";
import {IGmxHelper} from "./IGmxHelper.sol";

/**
 * @title AlgoTradingStorage Base Contract for containing all storage variables
 */
abstract contract AlgoTradingStorage is BaseStorage {
    struct PositionInfo {
        uint256 size;
        uint256 collateral;
    }

    struct TransactionMetaData {
        bytes4 selector;
        bytes32 txHash;
        bool isLong;
        address account;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 sizeDelta;
        uint256 executionFee;
        uint256 nonce;
        uint256 deadline;
    }

    struct TransactionMetaDataV2 {
        uint8 orderType;
        bytes32 txHash;
        bool isLong;
        address account;
        address[] addresses; // array of collateralToken, marketAddress
        uint256 amountIn;
        uint256 sizeDelta;
        uint256 executionFee;
        bytes numbers; //abi.encode(sizeInUsd, Collateral,executionPrice, priceMin, priceMax)
        uint256 nonce;
        uint256 deadline;
    }

    struct TradeExecutionInfo {
        bool status;
        uint256 retryCount;
    }

    address public strategyCreator;

    IGmxHelper internal gmxHelper;

    address internal policyManager;

    /**
     * @notice a list of traders whose trades will be copied for the user
     */
    address public followedTrader;

    /**
     * @notice pendingTxHash indicates a transaction of the master trader that is to be copied 
    */
    bytes32 public pendingTxHash;

    mapping(address => mapping(bytes32 => PositionInfo)) public traderPositions;

    /**
     * @dev stores the hashes of relayed txns to avoid replay transaction.
     */
    mapping(bytes32 => TradeExecutionInfo) public relayedTxns;

    mapping(address => uint256) internal _nonces;
    /**
     * @dev This variable becomes true when the master trader takes a position after squaring off
     * for first-time copy trade
     */
    mapping(address => mapping(address => mapping(address => bool)))
        public shouldFollow;

    mapping(address => mapping(bytes => bool)) public shouldStartCopy; //This for v2 trades

    /**
     * @notice Emits after add external addition
     *  @dev emits after successful requesting GMX positions
     *  @param externalPosition external position proxy addres
     *  @param followedTrader  trader address
     *  @param isLong position type
     *  @param indexToken position token
     *  @param selector position direction type (increase or decrease position)
     */
    event LeveragePositionUpdated(
        address externalPosition,
        address followedTrader,
        bool isLong,
        address indexToken,
        bytes4 selector
    );
}

