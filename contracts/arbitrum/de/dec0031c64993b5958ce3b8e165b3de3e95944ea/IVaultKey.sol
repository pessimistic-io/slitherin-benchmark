// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import { IERC721Enumerable } from "./IERC721Enumerable.sol";

interface IVaultKey is IERC721Enumerable {
    function mintKey(address to) external;

    function lastMintedKeyId(address to) external view returns (uint256);
}

