// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**huntnft
 * @title The interface for role manager
 * @notice a role manager manage the role in huntnft system
 */
interface IRoleManager {
    //********************EVENT*******************************//
    /// @notice emmit when set point operator
    event PointOperatorSet(address _operator, bool _enabled);
    event StoreOperatorSet(address _operator, bool _enabled);

    //********************FUNCTION*******************************//
    /**
     * @dev grant or revoke PointOperator role of an operator
     * @param _operator the account that need to change role
     * @param _enabled true equals to grant, false equals to revoke
     * @notice require:
     * - called must be admin of point operator role
     */
    function setPointOperator(address _operator, bool _enabled) external;

    /// @dev grant or revoke role of hunt nft store, which is used to sell nft in hunt nft store
    function setStoreOperator(address _operator, bool _enabled) external;

    /// @return check an _operator whether have the point operator role
    function isPointOperator(address _operator) external view returns (bool);

    /// @return check an _operator whether have the hunt nft  operator role
    function isStoreOperator(address _operator) external view returns (bool);
}

