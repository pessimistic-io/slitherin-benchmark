// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { Initializable } from "./Initializable.sol";
import { ECDSA } from "./ECDSA.sol";
import { GovernancePowerDelegationERC20 } from "./GovernancePowerDelegationERC20.sol";

/**
 * @notice implementation of the URDGovernance token contract
 * @author URD
 * Inspired from AAVE v2
 */
contract UrdGovernance is Initializable, GovernancePowerDelegationERC20 {
    uint256 public constant MAX_SUPPLY = 1_000 ether;

    /// @dev owner => next valid nonce to submit with permit()
    mapping(address => uint256) public _nonces;

    mapping(address => mapping(uint256 => Snapshot)) public _votingSnapshots;

    mapping(address => uint256) public _votingSnapshotsCounts;

    bytes32 public DOMAIN_SEPARATOR;
    bytes public constant EIP712_REVISION = bytes("1");
    bytes32 internal constant EIP712_DOMAIN = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    mapping(address => address) internal _votingDelegates;

    mapping(address => mapping(uint256 => Snapshot)) internal _propositionPowerSnapshots;
    mapping(address => uint256) internal _propositionPowerSnapshotsCounts;

    mapping(address => address) internal _propositionPowerDelegates;

    function initialize() external initializer {
        __ERC20_init("UrDex Governance Token", "URO");
        _mint(_msgSender(), MAX_SUPPLY);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(abi.encode(EIP712_DOMAIN, keccak256(bytes(name())), keccak256(EIP712_REVISION), chainId, address(this)));
    }

    /**
     * @dev implements the permit function as for https://github.com/ethereum/EIPs/blob/8a34d644aacf0f9f8f00815307fd7dd5da07655f/EIPS/eip-2612.md
     * @param owner the owner of the funds
     * @param spender the spender
     * @param value the amount
     * @param deadline the deadline timestamp, type(uint256).max for no deadline
     * @param v signature param
     * @param s signature param
     * @param r signature param
     */

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(owner != address(0), "INVALID_OWNER");
        //solium-disable-next-line
        require(block.timestamp <= deadline, "INVALID_EXPIRATION");
        uint256 currentValidNonce = _nonces[owner];
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, currentValidNonce, deadline)))
        );

        require(owner == ECDSA.recover(digest, v, r, s), "INVALID_SIGNATURE");
        _nonces[owner] = currentValidNonce + 1;
        _approve(owner, spender, value);
    }

    /**
     * @dev Writes a snapshot before any operation involving transfer of value: _transfer, _mint and _burn
     * - On _transfer, it writes snapshots for both "from" and "to"
     * - On _mint, only for _to
     * - On _burn, only for _from
     * @param from the from address
     * @param to the to address
     * @param amount the amount to transfer
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        address votingFromDelegatee = _getDelegatee(from, _votingDelegates);
        address votingToDelegatee = _getDelegatee(to, _votingDelegates);

        _moveDelegatesByType(votingFromDelegatee, votingToDelegatee, amount, DelegationType.VOTING_POWER);

        address propPowerFromDelegatee = _getDelegatee(from, _propositionPowerDelegates);
        address propPowerToDelegatee = _getDelegatee(to, _propositionPowerDelegates);

        _moveDelegatesByType(propPowerFromDelegatee, propPowerToDelegatee, amount, DelegationType.PROPOSITION_POWER);
    }

    function _getDelegationDataByType(
        DelegationType delegationType
    )
        internal
        view
        override
        returns (
            mapping(address => mapping(uint256 => Snapshot)) storage, //snapshots
            mapping(address => uint256) storage, //snapshots count
            mapping(address => address) storage //delegatees list
        )
    {
        if (delegationType == DelegationType.VOTING_POWER) {
            return (_votingSnapshots, _votingSnapshotsCounts, _votingDelegates);
        } else {
            return (_propositionPowerSnapshots, _propositionPowerSnapshotsCounts, _propositionPowerDelegates);
        }
    }

    /**
     * @dev Delegates power from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param delegationType the type of delegation (VOTING_POWER, PROPOSITION_POWER)
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateByTypeBySig(address delegatee, DelegationType delegationType, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 structHash = keccak256(abi.encode(DELEGATE_BY_TYPE_TYPEHASH, delegatee, uint256(delegationType), nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "INVALID_SIGNATURE");
        require(nonce == _nonces[signatory]++, "INVALID_NONCE");
        require(block.timestamp <= expiry, "INVALID_EXPIRATION");
        _delegateByType(signatory, delegatee, delegationType);
    }

    /**
     * @dev Delegates power from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 structHash = keccak256(abi.encode(DELEGATE_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "INVALID_SIGNATURE");
        require(nonce == _nonces[signatory]++, "INVALID_NONCE");
        require(block.timestamp <= expiry, "INVALID_EXPIRATION");
        _delegateByType(signatory, delegatee, DelegationType.VOTING_POWER);
        _delegateByType(signatory, delegatee, DelegationType.PROPOSITION_POWER);
    }
}

