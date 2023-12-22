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
import "./AutomationCompatibleInterface.sol";
import "./Ownable.sol";

interface IStopOrder {
    function checkStopOrder(uint256 tokenId) external view returns (bool);
    function executeStopOrder(uint256 tokenId) external;
    function indexTokenToTokenId(uint256 indexToken) external view returns (uint256);
}

contract UpkeepStopOrder is 
    AutomationCompatibleInterface, 
    Ownable
{
    IStopOrder public stopOrder;
    constructor(
        address _stopOrder
    ) { 
        stopOrder = IStopOrder(_stopOrder);
    }

    ////////////////
    // ONLY OWNER //
    ////////////////

    function setStopOrder(address newStopOrder) external onlyOwner {
        stopOrder = IStopOrder(newStopOrder);
    }    

    //////////
    // VIEW //
    //////////

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
            if (stopOrder.checkStopOrder(stopOrder.indexTokenToTokenId(lowerBound + i))) {
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
            if (stopOrder.checkStopOrder(stopOrder.indexTokenToTokenId(lowerBound + i))) {
                upkeepNeeded = true;
                indexes[indexCounter] = stopOrder.indexTokenToTokenId(lowerBound + i);
                indexCounter++;
                if (indexCounter == counter) {
                    break;
                }
            }
        }
        performData = abi.encode(indexes);
        return (upkeepNeeded, performData);
    }

    //////////////
    // EXTERNAL //
    //////////////    

    function performUpkeep(bytes calldata performData) external override {
        (uint256[] memory indexes) = abi.decode(
            performData,
            (uint256[])
        );
        for (uint256 i = 0; i < indexes.length; i++) {
            if (stopOrder.checkStopOrder(indexes[i])) {
                stopOrder.executeStopOrder(indexes[i]);
            }
        }
    }
}

