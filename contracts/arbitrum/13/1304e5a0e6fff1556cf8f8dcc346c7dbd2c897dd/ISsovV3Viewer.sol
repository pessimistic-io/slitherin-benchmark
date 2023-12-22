//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ISsovV3} from "./ISsovV3.sol";

interface ISsovV3Viewer {
    function getEpochStrikeTokens(uint256 epoch, ISsovV3 ssov)
        external
        view
        returns (address[] memory strikeTokens);

    function walletOfOwner(address owner, ISsovV3 ssov)
        external
        view
        returns (uint256[] memory tokenIds);
}

