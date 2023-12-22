// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ShareTokenBase, Authority} from "./ShareTokenBase.sol";
import {AnnotatingConstructor} from "./AnnotatingConstructor.sol";

/// @notice Token representing common voting shares.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/ShareToken.sol)
contract ShareToken is ShareTokenBase, AnnotatingConstructor {
    constructor(
        string memory name,
        string memory symbol,
        address _owner,
        Authority _authority,
        string[] memory notes
    ) ShareTokenBase(name, symbol, 0, _owner, _authority) AnnotatingConstructor(notes) {}

    /**
     * @notice Mint new Share Tokens
     * @dev Intended role: Minter
     */
    function mint(address to, uint256 amount) external requiresAuth {
        _mint(to, amount);
    }

    /**
     * @notice Burn Share Tokens
     * @dev Intended role: Minter
     */
    function burn(address account, uint256 amount) external requiresAuth {
        _burn(account, amount);
    }
}

