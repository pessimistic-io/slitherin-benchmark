// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IETHVolatilityOracle} from "./IETHVolatilityOracle.sol";

contract ETHVolatilityOracle is Ownable, IETHVolatilityOracle {
    /*==== PUBLIC VARS ====*/

    mapping(uint256 => uint256) public strikeToVols;

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
            'ETHVolatilityOracle: Input lengths must match'
        );

        for (uint256 i = 0; i < strikes.length; i++) {
            require(vols[i] > 0, 'ETHVolatilityOracle: Volatility cannot be 0');
            strikeToVols[strikes[i]] = vols[i];
        }
    }

    /*==== VIEWS ====*/

    /**
     * @notice Gets the volatility of dpx
     * @return volatility
     */
    function getVolatility(uint256 strike)
        external
        view
        override
        returns (uint256)
    {
        require(
            strikeToVols[strike] != 0,
            'ETHVolatilityOracle: volatility == 0'
        );

        return strikeToVols[strike];
    }
}

