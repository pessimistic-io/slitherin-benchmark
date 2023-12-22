//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";

import {IMagicDomainRegistry} from "./IMagicDomainRegistry.sol";
import {IMagicDomainResolver} from "./IMagicDomainResolver.sol";
import {AddressResolverAbs} from "./AddressResolverAbs.sol";
import {NameResolverAbs} from "./NameResolverAbs.sol";
import {TextResolverAbs} from "./TextResolverAbs.sol";
import {ResolverAbs} from "./ResolverAbs.sol";

/**
 * A simple resolver anyone can use; only allows the owner of a node to set its
 * address.
 */
contract MagicDomainResolver is
    Initializable,
    ResolverAbs,
    AddressResolverAbs,
    NameResolverAbs,
    TextResolverAbs,
    IMagicDomainResolver
{
    IMagicDomainRegistry public magicDomains;
    address public trustedDomainController;
    address public trustedReverseRegistrar;

    /**
     * A mapping of operators. An address that is authorized for an address
     * may make any changes to the name that the owner could, but may not update
     * the set of authorisations.
     * (owner, operator) => approved
     */
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * A mapping of delegates. A delegate that is authorised by an owner
     * for a name may make changes to the name's resolver, but may not update
     * the set of token approvals.
     * (owner, name, delegate) => approved
     */
    mapping(address => mapping(bytes32 => mapping(address => bool))) private _tokenApprovals;

    // Logged when an operator is added or removed.
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );
    // Logged when a delegate is approved or  an approval is revoked.
    event Approved(
        address owner,
        bytes32 indexed node,
        address indexed delegate,
        bool indexed approved
    );

    function initialize(IMagicDomainRegistry _magicDomains,
        address _trustedDomainController,
        address _trustedReverseRegistrar
    ) external initializer {
        magicDomains = _magicDomains;
        trustedDomainController = _trustedDomainController;
        trustedReverseRegistrar = _trustedReverseRegistrar;
    }

    /**
     * @dev Forked from {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) external {
        require(
            msg.sender != operator,
            "MagicDomainResolver: setting approval status for self"
        );

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev Forked from {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator)
        public
        view
        returns (bool)
    {
        return _operatorApprovals[account][operator];
    }

    /**
     * @dev Approve a delegate to be able to updated records on a node.
     */
    function approve(bytes32 node, address delegate, bool approved) external {
        require(
            msg.sender != delegate,
            "MagicDomainResolver: Setting delegate status for self"
        );

        _tokenApprovals[msg.sender][node][delegate] = approved;
        emit Approved(msg.sender, node, delegate, approved);
    }

    /**
     * @dev Check to see if the delegate has been approved by the owner for the node.
     */
    function isApprovedFor(address owner, bytes32 node, address delegate)
        public
        view
        returns (bool)
    {
        return _tokenApprovals[owner][node][delegate];
    }

    function isAuthorized(bytes32 node) internal view override returns (bool) {
        if (
            msg.sender == trustedDomainController ||
            msg.sender == trustedReverseRegistrar
        ) {
            return true;
        }
        address owner = magicDomains.owner(node);
        return owner == msg.sender 
            || isApprovedForAll(owner, msg.sender)
            || isApprovedFor(owner, node, msg.sender);
    }

    function supportsInterface(bytes4 interfaceID)
        public
        view
        override(
            ResolverAbs,
            AddressResolverAbs,
            NameResolverAbs,
            TextResolverAbs,
            IMagicDomainResolver
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceID) || interfaceID == type(IMagicDomainResolver).interfaceId;
    }
}
