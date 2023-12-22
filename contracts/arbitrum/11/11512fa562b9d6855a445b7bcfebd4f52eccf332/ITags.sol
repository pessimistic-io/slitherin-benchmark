// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ITerm, IAgreementManager} from "./ITerm.sol";

/// @notice Agreement Term for 256 flexible read-only tags.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/ITags.sol)
interface ITags is ITerm {
    function getTags(IAgreementManager manager, uint256 tokenId) external view returns (uint256);

    function hasTag(
        IAgreementManager manager,
        uint256 tokenId,
        uint8 tag
    ) external view returns (bool);
}

