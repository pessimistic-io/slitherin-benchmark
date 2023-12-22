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
 
pragma solidity ^0.8.7;
import "./AutomationCompatibleInterface.sol";
import "./Ownable.sol";

interface ITakeProfit {
    function checkTakeProfit(uint256 tokenId) external view returns (bool);
    function executeTakeProfit(uint256 tokenId) external;
    function indexTokenToTokenId(uint256 indexToken) external view returns (uint256);
}

contract UpkeepTakeProfit is 
    AutomationCompatibleInterface, 
    Ownable
{
    ITakeProfit public takeProfit;
    constructor(
        address _takeProfit
    ) { 
        takeProfit = ITakeProfit(_takeProfit);
    }
    function checkUpkeep(
        bytes calldata checkData
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (uint256 lowerBound, uint256 upperBound) = abi.decode(
            checkData,
            (uint256, uint256)
        );
        uint256 counter;
        for (uint256 i = 0; i < upperBound - lowerBound + 1; i++) {
            if (takeProfit.checkTakeProfit(takeProfit.indexTokenToTokenId(lowerBound + i))) {
                counter++;
            }
            if (counter == 1) {
                break;
            }
        }

        uint256[] memory indexes = new uint256[](counter);

        upkeepNeeded = false;
        uint256 indexCounter;

        for (uint256 i = 0; i < upperBound - lowerBound + 1; i++) {
            if (takeProfit.checkTakeProfit(takeProfit.indexTokenToTokenId(lowerBound + i))) {
                upkeepNeeded = true;
                indexes[indexCounter] = takeProfit.indexTokenToTokenId(lowerBound + i);
                indexCounter++;
                if (indexCounter == counter) {
                    break;
                }
            }
        }
        performData = abi.encode(indexes);
        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint256[] memory indexes) = abi.decode(
            performData,
            (uint256[])
        );
        for (uint256 i = 0; i < indexes.length; i++) {
            if (takeProfit.checkTakeProfit(indexes[i])) {
                takeProfit.executeTakeProfit(indexes[i]);
            }
        }
    }
}

