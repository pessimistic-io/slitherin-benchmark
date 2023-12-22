// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {IERC721Enumerable} from "./IERC721Enumerable.sol";

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/IERC721RestrictedFactory.sol)
interface IERC721Restricted is IERC721Enumerable {
    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId) external;
}

