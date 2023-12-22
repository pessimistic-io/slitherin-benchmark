// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {AuthBase, Authority} from "./AuthBase.sol";

import {Initializable} from "./Initializable.sol";

/// @notice Provides a flexible and updatable auth pattern which is completely separate from application logic.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/security/AuthUpgradeable.sol)
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/auth/Auth.sol)
abstract contract AuthUpgradeable is AuthBase, Initializable {
    // slither-disable-next-line naming-convention
    function __Auth_init(address _owner, Authority _authority) internal onlyInitializing {
        __Auth_init_unchained(_owner, _authority);
    }

    // slither-disable-next-line naming-convention
    function __Auth_init_unchained(address _owner, Authority _authority) internal onlyInitializing {
        setup(_owner, _authority);
    }
}

