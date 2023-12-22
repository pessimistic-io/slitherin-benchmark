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

import "./IERC721.sol";
import "./Ownable.sol";
import "./AggregatorV3Interface.sol";

interface IHegicStrategy {
    function priceProvider() external view returns (address);
    function payOffAmount(uint256 optionID)
        external
        view
        returns (uint256 profit);
}

interface IOperationalTreasury {
    enum LockedLiquidityState { Unlocked, Locked }

    function payOff(uint256 positionID, address account) external;

    function lockedLiquidity(uint256 id)
        external
        view
        returns (
            LockedLiquidityState state,
            IHegicStrategy strategy,
            uint128 negativepnl,
            uint128 positivepnl,
            uint32 expiration
        );
}

contract TakeProfit is Ownable {
    enum TakeType { GreaterThanOrEqual, LessThanOrEqual }

    struct TokenInfo {
        uint256 tokenId;
        uint256 takeProfitPrice;
        uint256 expirationTime;
        address owner;
        TakeType takeType;
        uint256 commissionPaid;
    }

    IERC721 public erc721Contract;
    IOperationalTreasury public operationalTreasury;
    mapping(uint256 => TokenInfo) public tokenIdToTokenInfo;
    uint256 public commissionSize = 0.001 * 1e18;
    uint256 public withdrawableBalance;

    uint256 private activeTakeCount;
    uint256 public maxActiveTakes = 400;
    mapping(uint256 => uint256) public indexTokenToTokenId;
    mapping(uint256 => uint256) public idTokenToIndexToken;

    // Events
    event TakeProfitSet(uint256 indexed tokenId, uint256 takeProfitPrice, TakeType takeType);
    event TakeProfitDeleted(uint256 indexed tokenId);
    event TakeProfitUpdated(uint256 indexed tokenId, uint256 newTakeProfitPrice, TakeType newTakeType);
    event TakeProfitExecuted(uint256 indexed tokenId);

    // Constructor
    constructor(
        address _erc721Address,
        address _operationalTreasury
    ) {
        erc721Contract = IERC721(_erc721Address);
        operationalTreasury = IOperationalTreasury(_operationalTreasury);
    }

    // Set commission size
    function setCommissionSize(uint256 newCommissionSize) external onlyOwner {
        commissionSize = newCommissionSize;
    }

    function setMaxActiveTakes(uint256 newMaxActiveTakes) external onlyOwner {
        maxActiveTakes = newMaxActiveTakes;
    }

    // Withdraw profit
    function withdrawProfit() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > withdrawableBalance, "No profit available to withdraw");

        uint256 profit = contractBalance - withdrawableBalance;
        withdrawableBalance = contractBalance - profit;
        payable(owner()).transfer(profit);
    }

    function getActiveTakeCount() external view returns (uint256) {
        return activeTakeCount;
    }

    // Set take profit
    function setTakeProfit(
        uint256 tokenId,
        uint256 takeProfitPrice,
        TakeType takeType
    ) external payable {
        require(erc721Contract.ownerOf(tokenId) == msg.sender, "Caller must be the owner of the token");
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

        erc721Contract.transferFrom(msg.sender, address(this), tokenId);
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

        // Delete take profit
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
        erc721Contract.transferFrom(address(this), msg.sender, tokenId);

        emit TakeProfitDeleted(tokenId);
    }

    // Update take profit
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

    // Execute take profit
    function executeTakeProfit(uint256 tokenId) external {
        TokenInfo memory tokenInfo = tokenIdToTokenInfo[tokenId];
        require(checkTakeProfit(tokenId), "Take profit conditions not met");

        uint256 commissionToReturn = tokenInfo.commissionPaid;
        withdrawableBalance -= commissionToReturn;

        // Remove token from the active list
        _removeTokenFromActiveList(tokenId);

        delete tokenIdToTokenInfo[tokenId];
        payOff(tokenInfo);

        emit TakeProfitExecuted(tokenId);
    }

    // Check take profit
    function checkTakeProfit(uint256 tokenId) public view returns (bool) {
        TokenInfo memory tokenInfo = tokenIdToTokenInfo[tokenId];
        if (tokenInfo.expirationTime == 0) {
            return false;
        }

        uint256 timeToExpiration = tokenInfo.expirationTime - block.timestamp;
        if (timeToExpiration < 30 minutes && getPayOffAmount(tokenId) > 0) {
            return true;
        }

        uint256 currentPrice = getCurrentPrice(tokenInfo.tokenId);
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

    // Private function to pay off
    function payOff(TokenInfo memory tokenInfo) private {
        operationalTreasury.payOff(tokenInfo.tokenId, tokenInfo.owner);
        erc721Contract.transferFrom(address(this), tokenInfo.owner, tokenInfo.tokenId);
    }

    // Get pay off amount
    function getPayOffAmount(uint256 tokenId) public view returns (uint256) {
        (, IHegicStrategy strategy, , , ) = operationalTreasury.lockedLiquidity(tokenId);
        return strategy.payOffAmount(tokenId);
    } 

    // Get current price
    function getCurrentPrice(uint256 tokenId) public view returns (uint256) {
        (, IHegicStrategy strategy, , , ) = operationalTreasury.lockedLiquidity(tokenId);
        (, int256 latestPrice, , , ) = AggregatorV3Interface(strategy.priceProvider()).latestRoundData();
        return uint256(latestPrice);
    }

    // Get expiration time
    function getExpirationTime(uint256 tokenId) public view returns (uint256) {
        (, , , , uint32 expiration) = operationalTreasury.lockedLiquidity(tokenId);
        return uint256(expiration);
    }
}

