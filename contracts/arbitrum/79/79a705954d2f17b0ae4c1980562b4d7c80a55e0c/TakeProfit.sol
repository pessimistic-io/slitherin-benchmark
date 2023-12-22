/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DeDeLend
 * Copyright (C) 2023 DeDeLend
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./AggregatorV3Interface.sol";
import "./Ownable.sol";
import "./IERC721.sol";


interface ILiquidityPool {
    struct Liquidity {
        // Amount of liquidity available for option collateral and premiums
        uint freeLiquidity;
        // Amount of liquidity available for withdrawals - different to freeLiquidity
        uint burnableLiquidity;
        // Amount of liquidity reserved for long options sold to traders
        uint reservedCollatLiquidity;
        // Portion of liquidity reserved for delta hedging (quote outstanding)
        uint pendingDeltaLiquidity;
        // Current value of delta hedge
        uint usedDeltaLiquidity;
        // Net asset value, including everything and netOptionValue
        uint NAV;
        // longs scaled down by this factor in a contract adjustment event
        uint longScaleFactor;
    }
}

interface IOptionMarket {
    enum OptionType {
        LONG_CALL,
        LONG_PUT,
        SHORT_CALL_BASE,
        SHORT_CALL_QUOTE,
        SHORT_PUT_QUOTE
    }

    enum TradeDirection {
        OPEN,
        CLOSE,
        LIQUIDATE
    }

    struct Strike {
        // strike listing identifier
        uint id;
        // strike price
        uint strikePrice;
        // volatility component specific to the strike listing (boardIv * skew = vol of strike)
        uint skew;
        // total user long call exposure
        uint longCall;
        // total user short call (base collateral) exposure
        uint shortCallBase;
        // total user short call (quote collateral) exposure
        uint shortCallQuote;
        // total user long put exposure
        uint longPut;
        // total user short put (quote collateral) exposure
        uint shortPut;
        // id of board to which strike belongs
        uint boardId;
    }

    struct OptionBoard {
        // board identifier
        uint id;
        // expiry of all strikes belonging to board
        uint expiry;
        // volatility component specific to board (boardIv * skew = vol of strike)
        uint iv;
        // admin settable flag blocking all trading on this board
        bool frozen;
        // list of all strikes belonging to this board
        uint[] strikeIds;
    }

    struct TradeInputParameters {
        // id of strike
        uint strikeId;
        // OptionToken ERC721 id for position (set to 0 for new positions)
        uint positionId;
        // number of sub-orders to break order into (reduces slippage)
        uint iterations;
        // type of option to trade
        OptionType optionType;
        // number of contracts to trade
        uint amount;
        // final amount of collateral to leave in OptionToken position
        uint setCollateralTo;
        // revert trade if totalCost is below this value
        uint minTotalCost;
        // revert trade if totalCost is above this value
        uint maxTotalCost;
        // referrer emitted in Trade event, no on-chain interaction
        address referrer;
    }

    struct TradeParameters {
        bool isBuy;
        bool isForceClose;
        TradeDirection tradeDirection;
        OptionType optionType;
        uint amount;
        uint expiry;
        uint strikePrice;
        uint spotPrice;
        ILiquidityPool.Liquidity liquidity;
    }

    struct Result {
        uint positionId;
        uint totalCost;
        uint totalFee;
    }

    function getStrikeAndBoard(uint strikeId) external view returns (Strike memory, OptionBoard memory);
    function closePosition(TradeInputParameters memory params) external returns (Result memory result);
    function forceClosePosition(TradeInputParameters memory params) external returns (Result memory result);
    function quoteAsset() external view returns (address);
}

interface IOptionToken is IERC721 {
    enum PositionState {
        EMPTY,
        ACTIVE,
        CLOSED,
        LIQUIDATED,
        SETTLED,
        MERGED
    }

    struct OptionPosition {
        uint positionId;
        uint strikeId;
        IOptionMarket.OptionType optionType;
        uint amount;
        uint collateral;
        PositionState state;
    }
    function getOptionPosition(uint positionId) external view returns (OptionPosition memory);
}

/**
 * @title TakeProfit
 * @notice This contract allows users to set and execute take-profit orders on ERC721 tokens.
 * Users can set a price target, and when the target is met, the contract automatically
 * executes the order and sends the profit to the user.
 * @dev The contract utilizes Chainlink price feeds, Lyra options protocol, and an exchange adapter for executing orders.
 */
contract TakeProfit is Ownable {
    // Enum for specifying the type of the take-profit order
    enum TakeType { GreaterThanOrEqual, LessThanOrEqual }

    // TokenInfo struct to store information related to a token for which a take-profit order is set
    struct TokenInfo {
        uint256 tokenId;
        uint256 takeProfitPrice;
        uint256 expirationTime;
        address owner;
        TakeType takeType;
        uint256 commissionPaid;
    }

    // Mappings for storing tokenId related data, active takes, and their indices
    mapping(uint256 => TokenInfo) public tokenIdToTokenInfo;
    uint256 public commissionSize = 0.001 * 1e18;
    uint256 public slippage = 0.02 * 1e18;
    uint256 public withdrawableBalance;
    address public rewardAddress;
    uint256 private activeTakeCount;
    uint256 public maxActiveTakes = 400;
    mapping(uint256 => uint256) public indexTokenToTokenId;
    mapping(uint256 => uint256) public idTokenToIndexToken;

    // Contract instances for price feeds, exchange adapter, and Lyra options protocol
    AggregatorV3Interface public priceProvider;
    IOptionMarket public optionMarket;
    IOptionToken public optionToken;
    
    // Events to emit when a take-profit order is set, deleted, updated, or executed
    event TakeProfitSet(uint256 indexed tokenId, uint256 takeProfitPrice, TakeType takeType);
    event TakeProfitDeleted(uint256 indexed tokenId);
    event TakeProfitUpdated(uint256 indexed tokenId, uint256 newTakeProfitPrice, TakeType newTakeType);
    event TakeProfitExecuted(uint256 indexed tokenId);

    // Constructor to initialize the contract with the required ERC721 contract and operational treasury addresses
    constructor(
        address _priceProvider,
        address _optionMarket,
        address _optionToken
    ) {
        priceProvider = AggregatorV3Interface(_priceProvider);
        optionMarket = IOptionMarket(_optionMarket);
        optionToken = IOptionToken(_optionToken);
    }

    // Function to set the commission size
    function setCommissionSize(uint256 newCommissionSize) external onlyOwner {
        commissionSize = newCommissionSize;
    }

    function setSlippage(uint256 newSlippage) external onlyOwner {
        slippage = newSlippage;
    }

    function setRewardAddress(address newRewardAddress) external onlyOwner {
        rewardAddress = newRewardAddress;
    }

    // Function to set the maximum number of active takes
    function setMaxActiveTakes(uint256 newMaxActiveTakes) external onlyOwner {
        maxActiveTakes = newMaxActiveTakes;
    }

    // Function for the contract owner to withdraw the profit
    function withdrawProfit() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > withdrawableBalance, "No profit available to withdraw");

        uint256 profit = contractBalance - withdrawableBalance;
        withdrawableBalance = contractBalance - profit;
        payable(owner()).transfer(profit);
    }

    // Function to get the count of active take-profit orders
    function getActiveTakeCount() external view returns (uint256) {
        return activeTakeCount;
    }

    // Function to set a take-profit order
    function setTakeProfit(
        uint256 tokenId,
        uint256 takeProfitPrice,
        TakeType takeType
    ) external payable {
        require(optionToken.ownerOf(tokenId) == msg.sender, "Caller must be the owner of the token");
        require(msg.value >= commissionSize, "Not enough commission sent");

        uint256 refund = msg.value - commissionSize;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }
        withdrawableBalance += commissionSize;

        // Add token to the active list
        activeTakeCount++;
        indexTokenToTokenId[activeTakeCount] = tokenId;
        idTokenToIndexToken[tokenId] = activeTakeCount;

        optionToken.transferFrom(msg.sender, address(this), tokenId);
        uint256 expirationTime = getExpirationTime(tokenId);
        tokenIdToTokenInfo[tokenId] = TokenInfo(
            tokenId,
            takeProfitPrice,
            expirationTime,
            msg.sender,
            takeType,
            commissionSize
        );

        emit TakeProfitSet(tokenId, takeProfitPrice, takeType);
    }

    // Function to delete a take-profit order
    function deleteTakeProfit(uint256 tokenId) external {
        TokenInfo memory tokenInfo = tokenIdToTokenInfo[tokenId];
        require(tokenInfo.owner == msg.sender, "Caller must be the owner of the token");
        require(tokenInfo.expirationTime > 0, "No token set for take profit");

        uint256 commissionToReturn = tokenInfo.commissionPaid;
        withdrawableBalance -= commissionToReturn;
        payable(msg.sender).transfer(commissionToReturn);

        // Remove token from the active list
        _removeTokenFromActiveList(tokenId);

        delete tokenIdToTokenInfo[tokenId];
        optionToken.transferFrom(address(this), msg.sender, tokenId);

        emit TakeProfitDeleted(tokenId);
    }

    // Function to update a take-profit order
    function updateTakeProfit(
        uint256 tokenId,
        uint256 newTakeProfitPrice,
        TakeType newTakeType
    ) external {
        TokenInfo storage tokenInfo = tokenIdToTokenInfo[tokenId];
        require(tokenInfo.owner == msg.sender, "Caller must be the owner of the token");

        tokenInfo.takeProfitPrice = newTakeProfitPrice;
        tokenInfo.takeType = newTakeType;

        emit TakeProfitUpdated(tokenId, newTakeProfitPrice, newTakeType);
    }

    // Function to execute a take-profit order
    function executeTakeProfit(uint256 tokenId) external {
        TokenInfo memory tokenInfo = tokenIdToTokenInfo[tokenId];
        require(checkTakeProfit(tokenId), "Take profit conditions not met");

        uint256 commissionToReturn = tokenInfo.commissionPaid;
        withdrawableBalance -= commissionToReturn;

        // Remove token from the active list
        _removeTokenFromActiveList(tokenId);

        delete tokenIdToTokenInfo[tokenId];
        IERC20 quoteAsset = IERC20(optionMarket.quoteAsset());
        uint256 balanceBefore = quoteAsset.balanceOf(address(this));
        closeOrForceClosePosition(tokenInfo);
        quoteAsset.transfer(tokenInfo.owner, quoteAsset.balanceOf(address(this)) - balanceBefore);


        emit TakeProfitExecuted(tokenId);
    }

    // Function to check if the conditions for a take-profit order are met
    function checkTakeProfit(uint256 tokenId) public view returns (bool) {
        TokenInfo memory tokenInfo = tokenIdToTokenInfo[tokenId];
        if (tokenInfo.expirationTime == 0) {
            return false;
        }

        uint256 timeToExpiration = tokenInfo.expirationTime - block.timestamp;
        if (timeToExpiration < 30 minutes) {
            return true;
        }

        uint256 currentPrice = getCurrentPrice();
        bool takeProfitTriggered = false;
        if (tokenInfo.takeType == TakeType.GreaterThanOrEqual) {
            takeProfitTriggered = currentPrice >= tokenInfo.takeProfitPrice;
        } else if (tokenInfo.takeType == TakeType.LessThanOrEqual) {
            takeProfitTriggered = currentPrice <= tokenInfo.takeProfitPrice;
        }
        return takeProfitTriggered;
    }
    
    function _removeTokenFromActiveList(uint256 tokenId) private {
        uint256 indexToRemove = idTokenToIndexToken[tokenId];
        uint256 lastTokenId = indexTokenToTokenId[activeTakeCount];

        // Move the last token to the removed token's position
        indexTokenToTokenId[indexToRemove] = lastTokenId;
        idTokenToIndexToken[lastTokenId] = indexToRemove;

        // Remove the last token from the active list
        delete indexTokenToTokenId[activeTakeCount];
        delete idTokenToIndexToken[tokenId];
        activeTakeCount--;
    }

    // Function to get the current price of a specific token
    function getCurrentPrice() public view returns (uint256) {
        (, int256 latestPrice, , , ) = AggregatorV3Interface(priceProvider).latestRoundData();
        return uint256(latestPrice);
    }

    function getExpirationTime(uint256 tokenId) internal view returns (uint256) {
        IOptionToken.OptionPosition memory positionInfo = optionToken.getOptionPosition(tokenId);
        (, IOptionMarket.OptionBoard memory optBoard) = optionMarket.getStrikeAndBoard(positionInfo.strikeId);
        return optBoard.expiry;
    }

    function closeOrForceClosePosition(TokenInfo memory tokenInfo) internal {
        IOptionToken.OptionPosition memory positionInfo = optionToken.getOptionPosition(tokenInfo.tokenId);
        IOptionMarket.TradeInputParameters memory params = IOptionMarket.TradeInputParameters(
            positionInfo.strikeId,
            positionInfo.positionId,
            1,
            IOptionMarket.OptionType(uint256(positionInfo.optionType)),
            positionInfo.amount,
            0,
            positionInfo.amount*slippage/1e18,
            type(uint256).max,
            rewardAddress
        );

        try optionMarket.closePosition(params) {
        } catch (bytes memory err) {
            if (checkForceCloseErrors(err)) {
                optionMarket.forceClosePosition(params);
            } else {
                revert(abi.decode(err, (string)));
            }
        }
    }

    function checkForceCloseErrors(bytes memory err) private pure returns (bool isForce) {
        if (
            keccak256(abi.encodeWithSignature('TradingCutoffReached(address,uint256,uint256,uint256)')) == keccak256(getFirstFourBytes(err)) ||
            keccak256(abi.encodeWithSignature('TradeDeltaOutOfRange(address,int256,int256,int256)')) == keccak256(getFirstFourBytes(err)) 
        ) return true;
    }

    function getFirstFourBytes(bytes memory data) public pure returns (bytes memory) {
        require(data.length >= 4, "Data should be at least 4 bytes long.");
        
        bytes memory result = new bytes(4);
        for (uint i = 0; i < 4; i++) {
            result[i] = data[i];
        }
        
        return result;
    }
}

