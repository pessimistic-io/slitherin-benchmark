// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ERC165, IERC165} from "./ERC165.sol";

import {ITerm, IAgreementManager} from "./ITerm.sol";
import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";

/// @notice Base implementation for composable agreements.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/Term.sol)
abstract contract Term is ERC165, ITerm, AnnotatingMulticall {
    /// @dev Throws if called by an account other than the manager contract
    function onlyManager(IAgreementManager manager) internal view virtual {
        if (msg.sender != address(manager)) revert Term__NotManager(msg.sender);
    }

    function percentOfTotal(uint256 amount, uint256 total) internal pure virtual returns (uint256) {
        return (100 ether * amount) / total;
    }

    /// @inheritdoc ITerm
    function createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) public virtual override {
        onlyManager(manager);

        _createTerm(manager, tokenId, data);
    }

    /// @inheritdoc ITerm
    function settleTerm(IAgreementManager manager, uint256 tokenId) public virtual override {
        onlyManager(manager);
        if (constraintStatus(manager, tokenId) != 100 ether) revert Term__TermNotSatisfied();

        _settleTerm(manager, tokenId);
        _afterTermResolved(manager, tokenId);
    }

    /// @inheritdoc ITerm
    function cancelTerm(IAgreementManager manager, uint256 tokenId) public virtual override {
        onlyManager(manager);

        _cancelTerm(manager, tokenId);
        _afterTermResolved(manager, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(ITerm).interfaceId || super.supportsInterface(interfaceId);
    }

    /* ------ Abstract ------ */

    function constraintStatus(IAgreementManager manager, uint256 tokenId)
        public
        view
        virtual
        override
        returns (uint256);

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual;

    function _settleTerm(IAgreementManager manager, uint256 tokenId) internal virtual;

    function _cancelTerm(IAgreementManager manager, uint256 tokenId) internal virtual;

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual {}
}

