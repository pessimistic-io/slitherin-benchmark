//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Market.sol";
import "./MarketCreator.sol";
import { CTHelpers } from "./CTHelpers.sol";

/**
 * @dev This contract is the factory for creating on chain orderbooks.
 * This market uses gnosis' ConditionalToken framework as the settlement layer.
 */
contract MarketFactory is Ownable {

    MarketCreator public marketCreator;
    IConditionalTokens public conditionalTokens;

    mapping (address => string) public marketQuestions;
    mapping (address => bytes32) public marketQuestionIds;
    mapping (address => bool) public marketIsResolved;

    address[] public activeMarkets;
    address[] public inactiveMarkets;

    event NewMarket(address market);

    constructor(address _marketCreator, address _conditionalTokens) {
        marketCreator = MarketCreator(_marketCreator);
        conditionalTokens = IConditionalTokens(_conditionalTokens);
    }

    /**
     * @dev Creates a new market, as well as the necessary condition and oracle in the ConditionalToken 
     * 
     * @param _collateralToken Address of the collateral token for the market
     * @param _question The two outcome question to create a market on top of
     * @param _minAmount The minimum amount of collateral that can be used to create a new order
     * @param _fee The volume based trading fee
     * @param _feeRecipient Address which will receive the fees
     */
    function createMarket(
        address _collateralToken,
        string memory _question,
        uint _minAmount,
        uint _fee,
        address _feeRecipient
    ) public onlyOwner {
        bytes32 _questionId = keccak256(abi.encodePacked(_question));
        bytes32 conditionId = CTHelpers.getConditionId(address(this), _questionId, 2);
        uint positionIdOutcome0 = CTHelpers.getPositionId(IERC20(_collateralToken), CTHelpers.getCollectionId(bytes32(0), conditionId, 1));
        uint positionIdOutcome1 = CTHelpers.getPositionId(IERC20(_collateralToken), CTHelpers.getCollectionId(bytes32(0), conditionId, 2));
        // Hardcoded binary outcome for MVP
        conditionalTokens.prepareCondition(address(this), _questionId, 2);
        address market = marketCreator.createMarket(
            _collateralToken,
            address(conditionalTokens),
            conditionId,
            positionIdOutcome0,
            positionIdOutcome1,
            _minAmount,
            _fee,
            _feeRecipient
        );
        activeMarkets.push(address(market));
        marketQuestions[market] = _question;
        marketQuestionIds[market] = _questionId;
    }

    function resolveAndCloseMarket(address market, uint[] calldata indexSets, uint limit) external onlyOwner {
        _resolveMarket(market, indexSets);
        uint index = type(uint).max;
        for (uint i = 0; i < activeMarkets.length; i++) {
            if (activeMarkets[i] == market) {
                index = i;
                break;
            }
        }
        require(index != type(uint).max, "Market not found");
        activeMarkets[index] = activeMarkets[activeMarkets.length - 1];
        activeMarkets.pop();
        inactiveMarkets.push(market);
        Market(market).toggleMarketStatus();
        Market(market).bulkCancelOrders(limit);
    }

    function resolveMarket(address market, uint[] calldata indexSets) external onlyOwner {
        _resolveMarket(market, indexSets);
    }

    function setMarketFee(address market, uint fee) external onlyOwner {
        Market(market).setFee(fee);
    }

    function setMarketFeeRecipient(address market, address recipient) external onlyOwner {
        Market(market).setFeeRecipient(recipient);
    }

    function bulkCancelOrders(address market, uint limit) external onlyOwner {
        Market(market).bulkCancelOrders(limit);
    }

    function toggleMarketStatus(address market) external onlyOwner {
        uint index = type(uint).max;
        if (Market(market).isMarketActive()) {
            for (uint i = 0; i < activeMarkets.length; i++) {
                if (activeMarkets[i] == market) {
                    index = i;
                    break;
                }
            }
            require(index != type(uint).max, "Market not found");
            activeMarkets[index] = activeMarkets[activeMarkets.length - 1];
            activeMarkets.pop();
            inactiveMarkets.push(market);
        } else {
            for (uint i = 0; i < inactiveMarkets.length; i++) {
                if (inactiveMarkets[i] == market) {
                    index = i;
                    break;
                }
            }
            require(index != type(uint).max, "Market not found");
            inactiveMarkets[index] = inactiveMarkets[inactiveMarkets.length - 1];
            inactiveMarkets.pop();
            activeMarkets.push(market);
        }
        Market(market).toggleMarketStatus();
    }

    function getAllActiveMarkets() external view returns (address[] memory, string[] memory, bool[] memory) {
        uint256 length = activeMarkets.length; 
        uint i = 0; 
        bool[] memory isResolved = new bool[](length); 
        string[] memory questions = new string[](length); 
        for ( i; i < length; i++) {
            address market = activeMarkets[i]; 
            questions[i] = marketQuestions[market]; 
            isResolved[i] = marketIsResolved[market];
        }
        return (activeMarkets, questions, isResolved);
    }

    function getAllInactiveMarkets() external view returns (address[] memory, string[] memory, bool[] memory) {
        uint256 length = inactiveMarkets.length; 
        uint i = 0; 
        bool[] memory isResolved = new bool[](length); 
        string[] memory questions = new string[](length); 
        for ( i; i < length; i++) {
            address market = inactiveMarkets[i]; 
            questions[i] = marketQuestions[market]; 
            isResolved[i] = marketIsResolved[market];
        }
        return (inactiveMarkets, questions, isResolved);
    }

    function _resolveMarket(address market, uint[] calldata indexSets) internal {
        bytes32 questionId = marketQuestionIds[market];
        conditionalTokens.reportPayouts(questionId, indexSets);
        marketIsResolved[market] = true;
    }
}
