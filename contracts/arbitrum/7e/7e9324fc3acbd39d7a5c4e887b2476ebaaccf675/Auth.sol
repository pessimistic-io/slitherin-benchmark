// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {AuthBase, Authority} from "./AuthBase.sol";

/// @notice Provides a flexible and updatable auth pattern which is completely separate from application logic.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/security/Auth.sol)
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/auth/Auth.sol)
abstract contract Auth is AuthBase {
    constructor(address _owner, Authority _authority) {
        setup(_owner, _authority);
    }
}

