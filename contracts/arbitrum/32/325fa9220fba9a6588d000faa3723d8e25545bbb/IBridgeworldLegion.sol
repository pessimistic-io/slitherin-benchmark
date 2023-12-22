// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IBridgeworldLegion {
    function getStakedLegions(address user)
        external
        view
        returns (uint256[] memory);
}

