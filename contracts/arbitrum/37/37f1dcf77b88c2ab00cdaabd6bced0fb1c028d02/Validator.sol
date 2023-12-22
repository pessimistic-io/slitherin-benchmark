// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC165.sol";
import "./IValidator.sol";
import "./BaseValidator.sol";

abstract contract Validator is IValidator, ERC165, BaseValidator {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return (interfaceId == type(IValidator).interfaceId) || super.supportsInterface(interfaceId);
    }
}

