// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ITokensManagementFacet.sol";

contract ERC20TokensManagementFacet is ITokensManagementFacet {
    using SafeERC20 for IERC20;

    bytes32 internal constant STORAGE_POSITION = keccak256("mellow.contracts.erc20-management.storage");

    function contractStorage() internal pure returns (ITokensManagementFacet.Storage storage ds) {
        bytes32 position = STORAGE_POSITION;

        assembly {
            ds.slot := position
        }
    }

    function vault() external pure returns (address) {
        ITokensManagementFacet.Storage memory ds = contractStorage();
        return ds.vault;
    }

    function initERC20TokensManagementFacet() external {
        ITokensManagementFacet.Storage storage ds = contractStorage();
        require(ds.vault == address(0));
        ds.vault = address(this);
    }

    function approve(address token, address to, uint256 amount) external {
        require(msg.sender == address(this));
        IERC20(token).safeApprove(to, amount);
    }
}

