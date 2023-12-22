// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {IAgreementManager} from "./IAgreementManager.sol";

import {IERC165} from "./interfaces_IERC165.sol";

/// @notice Interface for grants holding AuthorizedShareToken.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/IAuthorizedShareGrant.sol)
interface IAuthorizedShareGrant is IERC165 {
    error AuthorizedShareGrant__NotAuthorizedShareToken(address token);

    function authTokenBalance(IAgreementManager manager, uint256 tokenId) external view returns (uint256);
}

