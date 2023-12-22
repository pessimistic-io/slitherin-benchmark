// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IExchangeHelper.sol";

/**
 * @title Knox Queue Diamond Storage Library
 */

library QueueStorage {
    struct Layout {
        // epoch id
        uint64 epoch;
        // maximum total value locked
        uint256 maxTVL;
        // mapping of claim token id to price per share (claimTokenIds -> pricePerShare)
        mapping(uint256 => uint256) pricePerShare;
        // ExchangeHelper contract interface
        IExchangeHelper Exchange;
    }

    bytes32 internal constant LAYOUT_SLOT =
        keccak256("knox.contracts.storage.Queue");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = LAYOUT_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @notice returns the current claim token id
     * @return claim token id
     */
    function _getCurrentTokenId() internal view returns (uint256) {
        return _formatClaimTokenId(_getEpoch());
    }

    /**
     * @notice returns the current epoch of the queue
     * @return epoch id
     */
    function _getEpoch() internal view returns (uint64) {
        return layout().epoch;
    }

    /**
     * @notice returns the max total value locked of the vault
     * @return max total value
     */
    function _getMaxTVL() internal view returns (uint256) {
        return layout().maxTVL;
    }

    /**
     * @notice returns the price per share for a given claim token id
     * @param tokenId claim token id
     * @return price per share
     */
    function _getPricePerShare(uint256 tokenId)
        internal
        view
        returns (uint256)
    {
        return layout().pricePerShare[tokenId];
    }

    /************************************************
     * HELPERS
     ***********************************************/

    /**
     * @notice calculates claim token id for a given epoch
     * @param epoch weekly interval id
     * @return claim token id
     */
    function _formatClaimTokenId(uint64 epoch) internal view returns (uint256) {
        return (uint256(uint160(address(this))) << 64) + uint256(epoch);
    }

    /**
     * @notice derives queue address and epoch from claim token id
     * @param tokenId claim token id
     * @return address of queue
     * @return epoch id
     */
    function _parseClaimTokenId(uint256 tokenId)
        internal
        pure
        returns (address, uint64)
    {
        address queue;
        uint64 epoch;

        assembly {
            queue := shr(64, tokenId)
            epoch := tokenId
        }

        return (queue, epoch);
    }
}

