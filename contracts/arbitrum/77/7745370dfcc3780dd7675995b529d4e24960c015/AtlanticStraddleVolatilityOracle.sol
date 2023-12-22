// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {AccessControl} from "./AccessControl.sol";

// Interfaces
import {IVolatilityOracle} from "./IVolatilityOracle.sol";

contract AtlanticStraddleVolatilityOracle is AccessControl, IVolatilityOracle {
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /*==== PUBLIC VARS ====*/

    uint256 public volatility;
    uint256 public lastUpdatedAt;

    /*==== EVENTS ====*/

    event VolatilityUpdated(uint256 volatility, uint256 updatedAt);

    /*==== ERRORS ====*/

    error VolatilityZero();

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(KEEPER_ROLE, _msgSender());
    }

    /*==== SETTER FUNCTIONS (ONLY OWNER) ====*/

    /**
     * @notice Updates the volatility
     * @param _volatility volatility
     */
    function updateVolatility(uint256 _volatility)
        external
        onlyRole(KEEPER_ROLE)
    {
        volatility = _volatility;

        lastUpdatedAt = block.timestamp;

        emit VolatilityUpdated(_volatility, block.timestamp);
    }

    /*==== VIEWS ====*/

    /**
     * @notice Gets the volatility
     * @return volatility
     */
    function getVolatility(uint256) external view override returns (uint256) {
        if (volatility == 0) revert VolatilityZero();

        return volatility;
    }
}

