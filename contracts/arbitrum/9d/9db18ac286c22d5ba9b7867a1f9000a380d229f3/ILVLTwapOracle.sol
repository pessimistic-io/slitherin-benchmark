// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ILVLTwapOracle {
    /**
     * @notice Update TWAP for the last period
     */
    function update() external;

    /**
     * @notice Returns TWAP for the last period
     */
    function lastTWAP() external view returns (uint256);

    /**
     * @notice Returns TWAP from the last update time to current time
     */
    function getCurrentTWAP() external view returns (uint256);
}

