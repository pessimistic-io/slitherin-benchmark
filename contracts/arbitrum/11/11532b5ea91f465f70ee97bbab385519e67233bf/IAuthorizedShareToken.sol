// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ShareToken} from "./ShareToken.sol";

import {IERC165} from "./interfaces_IERC165.sol";

/// @notice Token representing non-voting "authorized" shares that can be redeemed for underlying.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/IAuthorizedShareToken.sol)
interface IAuthorizedShareToken is IERC165 {
    function mint(address to, uint256 amount) external;

    function underlying() external view returns (ShareToken);

    function issueTo(address account, uint256 amount) external;
}

