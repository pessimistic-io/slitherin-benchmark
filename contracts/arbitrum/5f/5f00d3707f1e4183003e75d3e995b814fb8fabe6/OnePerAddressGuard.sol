// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGuard} from "./IGuard.sol";
import {IERC721} from "./IERC721.sol";

/// @title GroupOS OnePerAddressGuard Contract
/// @author symmetry (@symmtry69)
/// @notice This contract serves as a guard pattern implementation, similar to that of Gnosis Safe contracts,
/// designed to ensure that an address can only own one ERC-721 token at a time.
contract OnePerAddressGuard is IGuard {
    error OnePerAddress(address owner, uint256 balance);

    /*===========
        VIEWS
    ===========*/

    /// @dev Hook to perform pre-call checks and return guard information.
    /// @param data The data associated with the action, including relevant parameters.
    /// @return checkBeforeData Additional data to be passed to the `checkAfter` function.
    function checkBefore(address, bytes calldata data) external view returns (bytes memory checkBeforeData) {
        // (address operator, address from, address to, uint256 startTokenId, uint256 quantity)
        (,, address owner,, uint256 quantity) = abi.decode(data, (address, address, address, uint256, uint256));

        uint256 balanceBefore = IERC721(msg.sender).balanceOf(owner);
        if (balanceBefore + quantity > 1) {
            revert OnePerAddress(owner, balanceBefore + quantity);
        }

        return abi.encode(owner); // only need to pass the owner forward to checkAfter
    }

    /// @dev Hook to perform post-call checks.
    /// @param checkBeforeData Data passed from the `checkBefore` function.
    function checkAfter(bytes calldata checkBeforeData, bytes calldata) external view {
        address owner = abi.decode(checkBeforeData, (address));
        uint256 balanceAfter = IERC721(msg.sender).balanceOf(owner);
        if (balanceAfter > 1) revert OnePerAddress(owner, balanceAfter);
    }
}

