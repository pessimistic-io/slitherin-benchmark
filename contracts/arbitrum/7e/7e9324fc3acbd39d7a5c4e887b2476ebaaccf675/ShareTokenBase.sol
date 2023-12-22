// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ERC20Base} from "./ERC20Base.sol";
import {TokenVotes} from "./TokenVotes.sol";
import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";
import {PausableAuth, Auth} from "./PausableAuth.sol";
import {AuthBase, Authority} from "./AuthBase.sol";

/// @notice Base implementation for all voting share tokens.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/ShareTokenBase.sol)
abstract contract ShareTokenBase is ERC20Base, PausableAuth, TokenVotes, AnnotatingMulticall {
    /// @dev Starts paused
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _owner,
        Authority _authority
    ) ERC20Base(_name, _symbol, _decimals) Auth(_owner, _authority) {
        _pause();
    }

    function setName(string calldata newName) external requiresAuth {
        name = newName;
    }

    function setSymbol(string calldata newSymbol) external requiresAuth {
        symbol = newSymbol;
    }

    /**
     * @dev Only allows contract owner to mint new tokens
     */
    function _mint(address to, uint256 amount) internal override {
        super._mint(to, amount);
        _mintVotes(to, amount);
    }

    /**
     * @dev Only allows contract owner to burn tokens
     */
    function _burn(address account, uint256 amount) internal override {
        super._burn(account, amount);
        _burnVotes(account, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override onlyAuthorizedWhenPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);
        _afterTransfer(from, to, amount);
    }

    // functions required for TokenVotes implementation
    function _getVotingPower(address account) internal view virtual override returns (uint256) {
        return balanceOf[account];
    }

    function _getTotalSupply() internal view virtual override returns (uint256) {
        return totalSupply;
    }
}

