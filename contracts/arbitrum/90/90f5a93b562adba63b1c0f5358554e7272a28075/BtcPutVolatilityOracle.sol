// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

contract BtcPutVolatilityOracle is Ownable {
    /*==== PUBLIC VARS ====*/

    mapping(uint256 => uint256) public strikeToVols;

    /*==== EVENTS ====*/

    event VolatilityUpdate(uint256[] strikes, uint256[] vols);

    /*==== SETTER FUNCTIONS (ONLY OWNER) ====*/

    /**
     * @notice Updates the volatility
     * @param strikes strikes
     * @param vols volatilities
     */
    function updateVolatility(uint256[] memory strikes, uint256[] memory vols)
        external
        onlyOwner
    {
        require(
            strikes.length == vols.length,
            'VolatilityOracle: Input lengths must match'
        );

        for (uint256 i = 0; i < strikes.length; i++) {
            require(vols[i] > 0, 'VolatilityOracle: Volatility cannot be 0');
            strikeToVols[strikes[i]] = vols[i];
        }

        emit VolatilityUpdate(strikes, vols);
    }

    /*==== VIEWS ====*/

    /**
     * @notice Gets the volatility
     * @return volatility
     */
    function getVolatility(uint256 strike) external view returns (uint256) {
        require(strikeToVols[strike] != 0, 'VolatilityOracle: volatility == 0');

        return strikeToVols[strike];
    }
}

