// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Authority} from "./AuthBase.sol";
import {IERC721Restricted} from "./IERC721Restricted.sol";

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/IERC721RestrictedFactory.sol)
interface IERC721RestrictedFactory {
    function deploy(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address owner,
        Authority authority
    ) external returns (IERC721Restricted token);

    function getDeployedToken(bytes32 salt) external view returns (IERC721Restricted token);
}

