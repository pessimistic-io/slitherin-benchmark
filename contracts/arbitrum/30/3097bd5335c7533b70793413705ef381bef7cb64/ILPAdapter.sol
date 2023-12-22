// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "./ISuOracle.sol";

struct WithdrawResult {
    address token;
    uint256 amount;
}

interface ILPAdapter is ISuOracle {
    /* ======================== ERRORS ======================== */
    error IsNotLP(address asset);
    error AlreadyRegistered(address asset);
    error LPOracleNotReady();

    /* ==================== MUTABLE METHODS ==================== */
    /**
      * @notice Unwrap LP token with depth = 2 (if underlying token is LP => it's also unwrapping)
      * @param asset - address of LP token to withdraw/unwrap
      * @param amount - amount of asset to withdraw/unwrap
     **/
    function withdraw(address asset, uint256 amount) external returns (WithdrawResult[] memory);

    /* ====================== VIEW METHODS ==================== */
    /**
      * @notice Returns if asset ig Balancer LP token, registered in our adapter
      * @param asset - address of LP token to check
     **/
    function isAdapterLP(address asset) external returns (bool);
}
