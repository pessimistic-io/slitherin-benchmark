// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./access_Ownable.sol";
import "./InterfaceSupportTokenManager.sol";

/**
 * @author ishan@highlight.xyz
 * @dev A basic token manager / sample implementation that locks swaps / removals
 */
contract LockedTokenManager is ITokenManager, InterfaceSupportTokenManager {
    /**
     * @dev See {ITokenManager-canUpdateMetadata}
     */
    function canUpdateMetadata(
        address sender,
        uint256, /* id */
        bytes calldata /* newTokenUri */
    ) external view override returns (bool) {
        return Ownable(msg.sender).owner() == sender;
    }

    /**
     * @dev See {ITokenManager-canSwap}
     */
    function canSwap(
        address, /* sender */
        uint256, /* id */
        address /* newTokenManager */
    ) external pure override returns (bool) {
        return false;
    }

    /**
     * @dev See {ITokenManager-canRemoveItself}
     */
    function canRemoveItself(
        address, /* sender */
        uint256 /* id */
    ) external pure override returns (bool) {
        return false;
    }
}

