pragma solidity ^0.8.0;

import { SafeTransferLib, ERC20 } from "./SafeTransferLib.sol";

import "./Kernel.sol";
import "./EnumerableSet.sol";
import "./SignatureChecker.sol";
import "./ECDSA.sol";

// module dependancies
import { HOUSE } from "./HOUSE.sol";
import { ROLES } from "./ROLES.sol";

contract HousePolicy is Policy {
    using EnumerableSet for EnumerableSet.AddressSet;
    using ECDSA for bytes32;

    event WithdrawalSignerAdded(address indexed prover);
    event WithdrawalSignerRemoved(address indexed prover);
    event WithdrawalApproved(address indexed who, address indexed token, uint256 nonce);

    error Paused();
    error WithdrawalTokenNotWhitelisted();
    error WithdrawalExpired();
    error WithdrawalProofInvalid();
    error WithdrawalSignerNotFound();
    error WithdrawalNonceInvalid();
    error WithdrawalSignerExists();
    error WithdrawalSignerDoesntExist();
    error MinSignersExceedsProofs();
    error WithdrawalBadReceiver();
    error WithdrawalProofSignerNotUnique();
    error WithdrawalSignersMustHaveOneSigner();
    error WithdrawalMinSignerBadAmount();

    /// @notice Roles admin module
    ROLES public roles;

    /// @notice house module
    HOUSE public house;

    /// @notice pause lock for house actions
    bool public paused;

    /// @notice whitelist of address token -> bool whitelisted for house actions
    mapping(address => bool) public tokenWhitelist;

    /// @notice minimum number of proofs needed to execute a withdrawal (uniqueness is asserted)
    uint256 public minSigners;

    /// @notice Set of addresses that can generate withdrawal proofs
    EnumerableSet.AddressSet private _withdrawalSigners;

    /// @notice Current withdrawal nonce to prevent the re-use of a proof (TODO this might already be baked into ecrevocer sig data)
    mapping(address => uint256) public withdrawalNonces;

    struct WithdrawalProof {
        address proposedSigner;
        bytes signature;
    }

    struct WithdrawalData {
        address token;
        address recipient;
        uint256 amount;
        uint256 nonce;
        uint256 expiryTimestamp;
    }

    constructor(Kernel kernel_) Policy(kernel_) { }

    modifier unpaused() {
        if (paused) revert Paused();
        _;
    }

    modifier tokenWhitelisted(address token) {
        if (!tokenWhitelist[token]) revert WithdrawalTokenNotWhitelisted();
        _;
    }

    modifier OnlyOwner {
        roles.requireRole("houseowner", msg.sender);
        _;
    }

    modifier OnlyManager {
        roles.requireRole("housemanager", msg.sender);
        _;
    }

    // ######################## ~ KERNEL SETUP ~ ########################

    function configureDependencies() external override onlyKernel returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("HOUSE");
        dependencies[1] = toKeycode("ROLES");

        house = HOUSE(getModuleAddress(dependencies[0]));
        roles = ROLES(getModuleAddress(dependencies[1]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](6);
        requests[0] = Permissions(toKeycode("HOUSE"), HOUSE.depositERC20.selector);
        requests[1] = Permissions(toKeycode("HOUSE"), HOUSE.depositNative.selector);
        requests[2] = Permissions(toKeycode("HOUSE"), HOUSE.withdrawERC20.selector);
        requests[3] = Permissions(toKeycode("HOUSE"), HOUSE.withdrawNative.selector);
        requests[4] = Permissions(toKeycode("HOUSE"), HOUSE.ownerEmergencyWithdrawERC20.selector);
        requests[5] = Permissions(toKeycode("HOUSE"), HOUSE.ownerEmergencyWithdrawalNative.selector);
    }

    function allWithdrawalSigners() external view returns(address[] memory) {
        return _withdrawalSigners.values();
    }

    function withdrawalSignerAt(uint256 index) external view returns(address) {
        return _withdrawalSigners.at(index);
    }

    function withdrawalSignersContain(address signer) external view returns(bool) {
        return _withdrawalSigners.contains(signer);
    }

    function withdrawalSignersLength() external view returns(uint256) {
        return _withdrawalSigners.length();
    }

    // ######################## ~ MODULE ENTRANCES ~ ########################

    function depositERC20(ERC20 token, uint256 amount) external unpaused tokenWhitelisted(address(token)) {
        house.depositERC20(token, msg.sender, amount);
    }

    function depositNative() external payable unpaused tokenWhitelisted(address(0)) {
        house.depositNative{value: msg.value}(msg.sender);
    }

    function withdrawERC20(
        WithdrawalData calldata proposedWithdrawal,
        WithdrawalProof[] calldata proofs
    ) external unpaused {
        _validateWithdrawal(proposedWithdrawal, proofs);

        house.withdrawERC20(ERC20(proposedWithdrawal.token), payable(msg.sender), proposedWithdrawal.amount);
        emit WithdrawalApproved(msg.sender, proposedWithdrawal.token, withdrawalNonces[msg.sender]++);
    }

    function withdrawNative(
        WithdrawalData calldata proposedWithdrawal,
        WithdrawalProof[] calldata proofs
    ) external unpaused {
        _validateWithdrawal(proposedWithdrawal, proofs);

        house.withdrawNative(payable(msg.sender), proposedWithdrawal.amount);
        emit WithdrawalApproved(msg.sender, proposedWithdrawal.token, withdrawalNonces[msg.sender]++);
    }

    function _validateWithdrawal(
        WithdrawalData memory proposedWithdrawal,
        WithdrawalProof[] calldata proofs
    ) internal view {

        if (!tokenWhitelist[proposedWithdrawal.token])
            revert WithdrawalTokenNotWhitelisted();

        if (proposedWithdrawal.recipient != msg.sender)
            revert WithdrawalBadReceiver();

        if (proposedWithdrawal.nonce != withdrawalNonces[msg.sender])
            revert WithdrawalNonceInvalid();

        if (block.timestamp > proposedWithdrawal.expiryTimestamp)
            revert WithdrawalExpired();

        if (proofs.length < minSigners)
            revert MinSignersExceedsProofs();

        _validateWithdrawalProofs(proposedWithdrawal, proofs);
    }

    function _validateWithdrawalProofs(WithdrawalData memory proposedWithdrawal, WithdrawalProof[] calldata proofs) internal view {
        bytes32 proposedWithdrawalData = keccak256(abi.encode(proposedWithdrawal));
        proposedWithdrawalData = proposedWithdrawalData.toEthSignedMessageHash();

        for(uint i = 0; i < proofs.length; ++i) {

            if (!SignatureChecker.isValidSignatureNow(
                proofs[i].proposedSigner,
                proposedWithdrawalData,
                proofs[i].signature)
            )  revert WithdrawalProofInvalid();

            if(!_withdrawalSigners.contains(proofs[i].proposedSigner))
                revert WithdrawalProofInvalid();

            for(uint j = 0; j < proofs.length; ++j) {
                if(i == j) continue;
                if(proofs[j].proposedSigner == proofs[i].proposedSigner)
                    revert WithdrawalProofSignerNotUnique();
            }
        }
    }

    // ######################## ~ AUTH GATED FNS  ~ ########################

    function ownerEmergencyWithdrawERC20(ERC20 token, address to, uint256 amount) external OnlyOwner {
        house.ownerEmergencyWithdrawERC20(token, to, amount);
    }

    function ownerEmergencyWithdrawNative(address payable to, uint256 amount) external OnlyOwner {
        house.ownerEmergencyWithdrawalNative(to, amount);
    }

    // ######################## ~ POLICY MANAGEMENT  ~ ########################

    function unpause() external OnlyOwner {
        paused = false;
    }

    function pause() external OnlyManager {
        paused = true;
    }

    function whitelistToken(address token) external OnlyOwner {
        tokenWhitelist[token] = true;
    }

    function insertSigner(address signer) external OnlyOwner {
        bool success = _withdrawalSigners.add(signer);
        if(!success) revert WithdrawalSignerExists();
        ++minSigners;
        emit WithdrawalSignerAdded(signer);
    }

    /// @notice Removes a withdrawal prover
    /// @dev Withdrawals must be globally paused, changing prover order affects calldata
    function removeSigner(address signer) external OnlyOwner {
        bool success = _withdrawalSigners.remove(signer);
        if(!success) revert WithdrawalSignerDoesntExist();
        if(_withdrawalSigners.length() == 0) revert WithdrawalSignersMustHaveOneSigner();
        if(minSigners > 1) --minSigners; // TODO get rid of this?

        emit WithdrawalSignerRemoved(signer);
    }

    function changeMinSigners(uint256 newMinSigners) external OnlyOwner {
        if (
            newMinSigners == 0 ||
            newMinSigners > _withdrawalSigners.length()
        ) revert WithdrawalMinSignerBadAmount();

        minSigners = newMinSigners;
        // todo emit event
    }
}

