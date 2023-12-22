// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ArcBase} from "./ArcBase.sol";
import {IRainbowRoad} from "./IRainbowRoad.sol";

/**
 * Extends the ArcBase contract to provide
 * for interactions with the Rainbow Road
 */
contract ArcBaseWithRainbowRoad is ArcBase
{
    IRainbowRoad public rainbowRoad;
    
    constructor(address _rainbowRoad)
    {
        require(_rainbowRoad != address(0), 'Rainbow Road cannot be zero address');
        rainbowRoad = IRainbowRoad(_rainbowRoad);
    }
    
    function setRainbowRoad(address _rainbowRoad) external onlyOwner
    {
        require(_rainbowRoad != address(0), 'Rainbow Road cannot be zero address');
        rainbowRoad = IRainbowRoad(_rainbowRoad);
    }
    
    /// @dev Only calls from the Rainbow Road are accepted.
    modifier onlyRainbowRoad() 
    {
        require(msg.sender == address(rainbowRoad), 'Must be called by Rainbow Road');
        _;
    }
}

