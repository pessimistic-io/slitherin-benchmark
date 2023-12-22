// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./AccountRoles.sol";
import "./Account.sol";

abstract contract AccountRoleVerifier {
    /// @dev Reference to the account NFT contract.
    Account public account;

    modifier onlyAccountRole(
        AccountRole authorisedRole,
        uint256 accountId,
        address accountUser,
        bytes calldata signature
    ) {
        account.consumeAccountRoleSignature(
            accountId,
            accountUser,
            authorisedRole,
            signature
        );
        _;
    }
}

