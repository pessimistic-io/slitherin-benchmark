// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {IAuthorizedShareToken} from "./IAuthorizedShareToken.sol";
import {IAuthorizedShareGrant, IAgreementManager} from "./IAuthorizedShareGrant.sol";

import {ERC165Checker} from "./ERC165Checker.sol";
import {ERC165, IERC165} from "./ERC165.sol";

/// @notice Stores AuthorizedShareToken balance per agreement.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/AuthorizedShareGrant.sol)
abstract contract AuthorizedShareGrant is ERC165, IAuthorizedShareGrant {
    /// @notice Subset of agreement balance representing authorized shares
    mapping(IAgreementManager => mapping(uint256 => uint256)) public override authTokenBalance;

    function checkTokenInterface(address token) internal view virtual {
        if (!ERC165Checker.supportsInterface(token, type(IAuthorizedShareToken).interfaceId))
            revert AuthorizedShareGrant__NotAuthorizedShareToken(token);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return interfaceId == type(IAuthorizedShareGrant).interfaceId || super.supportsInterface(interfaceId);
    }
}

