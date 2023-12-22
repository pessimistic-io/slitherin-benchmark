// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ERC20Base} from "./ERC20Base.sol";
import {ShareToken} from "./ShareToken.sol";
import {AnnotatingConstructor} from "./AnnotatingConstructor.sol";
import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";
import {Auth, Authority} from "./Auth.sol";

import {ERC165} from "./ERC165.sol";

/// @notice Token representing non-voting "authorized" shares that can be redeemed for underlying.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/AuthorizedShareToken.sol)
contract AuthorizedShareToken is ERC20Base, Auth, ERC165, AnnotatingConstructor, AnnotatingMulticall {
    ShareToken public immutable underlying;

    constructor(
        string memory _name,
        string memory _symbol,
        ShareToken _underlying,
        Authority _authority,
        string[] memory notes
    ) ERC20Base(_name, _symbol, _underlying.decimals()) Auth(msg.sender, _authority) AnnotatingConstructor(notes) {
        underlying = _underlying;
    }

    function setName(string calldata newName) external requiresAuth {
        name = newName;
    }

    function setSymbol(string calldata newSymbol) external requiresAuth {
        symbol = newSymbol;
    }

    /**
     * @notice Mint new Share Tokens
     * @dev Intended role: ShareHolders
     */
    function mint(address to, uint256 amount) external requiresAuth {
        _mint(to, amount);
    }

    /// @dev Intended role: ShareHolders
    function burn(uint256 amount) external requiresAuth {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Allow a user to burn a number of authorized tokens and issue the corresponding number of underlying tokens.
     */
    function issueTo(address account, uint256 amount) external {
        _burn(msg.sender, amount);
        underlying.mint(account, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == 0x3df6821b || // ERC165 Interface ID for AuthorizedShareToken
            super.supportsInterface(interfaceId);
    }
}

