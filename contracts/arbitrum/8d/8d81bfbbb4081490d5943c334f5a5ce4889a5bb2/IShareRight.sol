// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

/// @notice Preferred share rights template.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/rights/IShareRight.sol)
interface IShareRight {
    /**
     * @notice Create new right
     * @param token PreferredShareToken address
     * @param data Initialization data struct
     */
    function createRight(address token, bytes calldata data) external;

    /**
     * @notice Check if right is satisfied
     */
    function checkRight(address token) external view returns (bool);

    /**
     * @notice Remove existing right
     */
    function removeRight(address token) external;
}

