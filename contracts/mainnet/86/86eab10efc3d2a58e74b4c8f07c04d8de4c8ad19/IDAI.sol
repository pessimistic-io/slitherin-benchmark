//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "./IERC20Metadata.sol";
import "./IERC20PermitAllowed.sol";

interface IDAI is IERC20Metadata, IERC20PermitAllowed {
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function version() external view returns (string memory);
}

