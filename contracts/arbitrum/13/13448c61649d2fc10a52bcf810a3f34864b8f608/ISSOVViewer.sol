//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ISSOV} from "./ISSOV.sol";

interface ISSOVViewer {
    function getEpochStrikeTokens(uint256 epoch, ISSOV ssov) external view returns (address[] memory strikeTokens);

    function walletOfOwner(address owner, ISSOV ssov) external view returns (uint256[] memory tokenIds);
}

