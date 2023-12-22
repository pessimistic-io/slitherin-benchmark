// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./IRoleManager.sol";

/**huntnft
 * @dev IPoints is the interface of manage points of hunt game
 */
interface IPoints {
    //********************FUNCTION*******************************//
    /**
     * @dev add game point to to _recipient
     * @param _recipient who will receive the points
     * @param _amount the amount of points
     * @notice required:
     * - sender must have specific right
     * - _recipient can't be empty address
     */
    function addPoint(address _recipient, uint64 _amount) external;

    /**
     * @dev consumePoint from specific account
     * @param _owner the account that consume the point
     * @param _amount the amount of point that try to consume
     * @notice required:
     * - sender must have specific right
     * - _owner have enough amount to consume
     */
    function consumePoint(address _owner, uint64 _amount) external;

    /// @return the role controller address
    function getRoleCenter() external view returns (IRoleManager);
}

