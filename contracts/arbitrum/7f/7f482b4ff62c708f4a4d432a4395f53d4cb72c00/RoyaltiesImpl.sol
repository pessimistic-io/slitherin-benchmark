// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AbstractRoyalties.sol";
import "./Royalties.sol";

contract RoyaltiesImpl is AbstractRoyalties, Royalties {

    function getRaribleRoyalties(uint256 id) override external view returns (LibPart.Part[] memory) {
        return royalties[id];
    }

    function _onRoyaltiesSet(uint256 id, LibPart.Part[] memory _royalties) override internal {
        emit RoyaltiesSet(id, _royalties);
    }
}

