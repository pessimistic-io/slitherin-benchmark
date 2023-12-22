// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./INftStorage.sol";
import "./IdType.sol";

abstract contract IBalance {
    function _insertNft(address owner, IdType id, INftStorage.NFTDef storage) internal virtual;

    function _removeNft(address owner, INftStorage.NFTDef storage) internal virtual;

    /**
     * @dev Gets id of the first NFT with the specified state.
     * @notice Reverts if there is no such NFT.
     */
    function _getHeadId(address owner, StateType nftState) internal virtual view returns (IdType);

    function _getTotalNftCount(address owner) internal virtual view returns (uint);
}

