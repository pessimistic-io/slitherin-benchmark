// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IVolatilityOracle} from "./IVolatilityOracle.sol";

contract VolatilityOracle is Ownable, IVolatilityOracle {
    /*==== PUBLIC VARS ====*/

    mapping(address => mapping(uint256 => uint256)) public atlanticPutsPoolStrikeToVols;

    /*==== EVENTS  ====*/

    event VolatilityUpdated(
        address indexed pool,
        uint256[] strikes,
        uint256[] vols
    );

    /*==== SETTER FUNCTIONS (ONLY OWNER) ====*/

    /**
     * @notice Updates the volatility
     * @param pool target atlantic puts pool
     * @param strikes strikes
     * @param vols volatilities
     */
    function updateVolatility(
        address pool,
        uint256[] memory strikes,
        uint256[] memory vols
    ) external onlyOwner {
        require(strikes.length == vols.length, "Input lengths must match");

        for (uint256 i = 0; i < strikes.length; i++) {
            require(vols[i] > 0, "Volatility cannot be 0");
            atlanticPutsPoolStrikeToVols[pool][strikes[i]] = vols[i];
        }

        emit VolatilityUpdated(pool, strikes, vols);
    }

    /*==== VIEWS ====*/

    /**
     * @notice Gets the volatility
     * @return volatility
     */
    function getVolatility(uint256 strike) external view returns (uint256) {
        require(
            atlanticPutsPoolStrikeToVols[msg.sender][strike] != 0,
            "Volatility cannot be 0"
        );

        return atlanticPutsPoolStrikeToVols[msg.sender][strike];
    }
}
