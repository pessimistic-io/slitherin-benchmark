// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {Limiter, LimiterLibrary, Transfer} from "./Limiter.sol";
import {Beneficiary, Beneficiaries, BeneficiariesLibrary} from "./Beneficiaries.sol";
import {ExtendedAccessControlUpgradeable} from "./ExtendedAccessControlUpgradeable.sol";

using LimiterLibrary for Limiter;
using BeneficiariesLibrary for Beneficiaries;

interface IToken is IERC20 {
    function mint(uint256 _amount) external;

    function burn(uint256 _amount) external;
}

contract Wallet is ExtendedAccessControlUpgradeable {
    error LimitExceeded();

    // Define constants for various roles using the keccak256 hash of the role names.
    bytes32 public constant BENEFICIARY_ROLE = keccak256("BENEFICIARY_ROLE");
    bytes32 public constant BENEFICIARY_LIMIT_ROLE = keccak256("BENEFICIARY_LIMIT_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant LIMIT_ROLE = keccak256("LIMIT_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");

    IToken public token; // Reference to the token contract.
    Limiter private limiter; // Limits the amount of transfers possible within a given timeframe.
    Beneficiaries private beneficiaries; // Keeps track of beneficiaries allowed by this contract.

    /**
     * @dev Emitted when a beneficiary with address `address`, 24-hour transfer limit `limit`
     * and cooldown period `period` (in seconds) is added to the list of beneficiaries.
     */
    event BeneficiaryAdded(address beneficiary, uint limit, uint cooldown);

    /**
     * @dev Emitted when the 24-hour transfer limit of beneficiary with address `address`
     * is changed to `limit`.
     */
    event BeneficiaryLimitChanged(address beneficiary, uint limit);

    /**
     * @dev Emitted when the 24-hour transfer limit of beneficiary with address `address`
     * is temporarily decreased by `limitDecrease`.
     */
    event BeneficiaryLimitTemporarilyDecreased(address beneficiary, uint limitDecrease);

    /**
     * @dev Emitted when the 24-hour transfer limit of beneficiary with address `address`
     * is temporarily increased by `limitIncrease`.
     */
    event BeneficiaryLimitTemporarilyIncreased(address beneficiary, uint limitIncrease);

    /**
     * @dev Emitted when the beneficiary with address `address` is removed from the list of beneficiaries.
     */
    event BeneficiaryRemoved(address beneficiary);

    /**
     * @dev Emitted when the 24-hour transfer limit is changed to `limit`.
     */
    event LimitChanged(uint limit);

    /**
     * @dev Emitted when the 24-hour transfer limit is temporarily decreased by `limitDecrease`.
     */
    event LimitTemporarilyDecreased(uint limitDecrease);

    /**
     * @dev Emitted when the 24-hour transfer limit is temporarily increased by `limitIncrease`.
     */
    event LimitTemporarilyIncreased(uint limitIncrease);

    /**
     * @dev Emitted when `amount` of tokens are transferred to `beneficiary`.
     */
    event Transferred(address beneficiary, uint amount);

    /**
     * @dev Emitted when `amount` of `token` are transferred to `to`.
     */
    event Transferred(IERC20 token, address to, uint amount);

    /**
     * @dev Emitted when an `amount` of tokens is minted.
     */
    event Minted(uint amount);

    /**
     * @dev Emitted when an `amount` of tokens is burned.
     */
    event Burned(uint amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with an admin and the address of the token.
     * @param _admin Address of the admin to be granted roles.
     * @param _token Address of the token contract.
     */
    function initialize(address _admin, IToken _token) public initializer {
        __ExtendedAccessControl_init();
        _addRole(BENEFICIARY_ROLE);
        _addRole(BENEFICIARY_LIMIT_ROLE);
        _addRole(BURN_ROLE);
        _addRole(LIMIT_ROLE);
        _addRole(MINT_ROLE);
        _addRole(TRANSFER_ROLE);
        _grantRoles(_admin);
        token = _token;
        limiter.interval = 24 hours;
    }

    /**
     * @dev Adds a beneficiary with a default 24-hour transfer limit of 0 and a default cooldown period of 24 hours.
     * Can only be called by an account with the BENEFICIARY_ROLE.
     * @param _beneficiary Address of the beneficiary to be added.
     */
    function addBeneficiary(address _beneficiary) public onlyRole(BENEFICIARY_ROLE) {
        addBeneficiary(_beneficiary, 0);
    }

    /**
     * @dev Adds a beneficiary with a specified 24-hour transfer limit and a default cooldown period of 24 hours.
     * Can only be called by an account with the BENEFICIARY_ROLE.
     * @param _beneficiary Address of the beneficiary to be added.
     * @param _limit Limit value for the beneficiary.
     */
    function addBeneficiary(address _beneficiary, uint _limit) public onlyRole(BENEFICIARY_ROLE) {
        addBeneficiary(_beneficiary, _limit, 24 hours);
    }

    /**
     * @dev Adds a beneficiary with a specified 24-hour transfer limit and specified cooldown period.
     * Can only be called by an account with the BENEFICIARY_ROLE.
     * @param _beneficiary Address of the beneficiary to be added.
     * @param _limit Limit value for the beneficiary.
     * @param _cooldown Cooldown period for the beneficiary.
     */
    function addBeneficiary(address _beneficiary, uint _limit, uint _cooldown) public onlyRole(BENEFICIARY_ROLE) {
        beneficiaries.addBeneficiary(_beneficiary, 24 hours, _limit, _cooldown);
        emit BeneficiaryAdded(_beneficiary, _limit, _cooldown);
    }

    /**
     * @dev Returns the list of all beneficiaries.
     */
    function getBeneficiaries() public view returns (Beneficiary[] memory) {
        return beneficiaries.getBeneficiaries();
    }

    /**
     * @dev Returns the details of a specific beneficiary.
     * @param _beneficiary Address of the beneficiary.
     */
    function getBeneficiary(address _beneficiary) public view returns (Beneficiary memory) {
        return beneficiaries.getBeneficiary(_beneficiary);
    }

    /**
     * @dev Returns the timestamp when a beneficiary gets enabled.
     * @param _beneficiary Address of the beneficiary.
     */
    function getBeneficiaryEnabledAt(address _beneficiary) public view returns (uint) {
        return beneficiaries.getBeneficiary(_beneficiary).enabledAt;
    }

    /**
     * @dev Returns the current 24-hour transfer limit for a specific beneficiary.
     * @param _beneficiary Address of the beneficiary.
     */
    function getBeneficiaryLimit(address _beneficiary) public view returns (uint) {
        return beneficiaries.getBeneficiary(_beneficiary).limit;
    }

    /**
     * @dev Returns the remaining 24-hour transfer limit for a specific beneficiary.
     * @param _beneficiary Address of the beneficiary.
     */
    function getBeneficiaryRemainingLimit(address _beneficiary) public view returns (int) {
        return beneficiaries.getBeneficiary(_beneficiary).remainingLimit;
    }

    /**
     * @dev Returns the list of transfers to a specific beneficiary within the last 24 hours.
     * @param _beneficiary Address of the beneficiary.
     */
    function getBeneficiaryTransfers(address _beneficiary) public view returns (Transfer[] memory) {
        return beneficiaries.getBeneficiary(_beneficiary).transfers;
    }

    /**
     * @dev Returns the current 24-hour transfer limit.
     */
    function getLimit() public view returns (uint) {
        return limiter.limit;
    }

    /**
     * @dev Returns the remaining 24-hour transfer limit.
     */
    function getRemainingLimit() public view returns (int) {
        return limiter.remainingLimit();
    }

    /**
     * @dev Returns the list of all transfers within the last 24 hours.
     */
    function getTransfers() public view returns (Transfer[] memory) {
        return limiter.transfers();
    }

    /**
     * @dev Removes a beneficiary from the list of whitelisted beneficiaries.
     * Can only be called by an account with the BENEFICIARY_ROLE.
     * @param _beneficiary Address of the beneficiary to be removed.
     */
    function removeBeneficiary(address _beneficiary) public onlyRole(BENEFICIARY_ROLE) {
        beneficiaries.removeBeneficiary(_beneficiary);
        emit BeneficiaryRemoved(_beneficiary);
    }

    /**
     * @dev Sets the 24-hour transfer limit for a specific beneficiary.
     * Can only be called by an account with the BENEFICIARY_LIMIT_ROLE.
     * @param _beneficiary Address of the beneficiary.
     * @param _limit The limit value to be set for the beneficiary.
     */
    function setBeneficiaryLimit(address _beneficiary, uint _limit) public onlyRole(BENEFICIARY_LIMIT_ROLE) {
        beneficiaries.setBeneficiaryLimit(_beneficiary, _limit);
        emit BeneficiaryLimitChanged(_beneficiary, _limit);
    }

    /**
     * @dev Sets the 24-hour transfer limit.
     * Can only be called by an account with the LIMIT_ROLE.
     * @param _limit The limit value to be set.
     */
    function setLimit(uint _limit) public onlyRole(LIMIT_ROLE) {
        limiter.limit = _limit;
        emit LimitChanged(_limit);
    }

    /**
     * @dev Temporarily increases the 24-hour transfer limiter for a specific beneficiary.
     * Can only be called by an account with the BENEFICIARY_LIMIT_ROLE.
     * @param _beneficiary Address of the beneficiary.
     * @param _limitIncrease Amount by which the limit should be increased.
     */
    function temporarilyIncreaseBeneficiaryLimit(
        address _beneficiary,
        uint _limitIncrease
    ) public onlyRole(BENEFICIARY_LIMIT_ROLE) {
        beneficiaries.temporarilyIncreaseBeneficiaryLimit(_beneficiary, _limitIncrease);
        emit BeneficiaryLimitTemporarilyIncreased(_beneficiary, _limitIncrease);
    }

    /**
     * @dev Temporarily decreases the 24-hour transfer limiter for a specific beneficiary.
     * Can only be called by an account with the BENEFICIARY_LIMIT_ROLE.
     * @param _beneficiary Address of the beneficiary.
     * @param _limitDecrease Amount by which the limit should be decreased.
     */
    function temporarilyDecreaseBeneficiaryLimit(
        address _beneficiary,
        uint _limitDecrease
    ) public onlyRole(BENEFICIARY_LIMIT_ROLE) {
        beneficiaries.temporarilyDecreaseBeneficiaryLimit(_beneficiary, _limitDecrease);
        emit BeneficiaryLimitTemporarilyDecreased(_beneficiary, _limitDecrease);
    }

    /**
     * @dev Temporarily increases the 24-hour transfer limiter.
     * Can only be called by an account with the LIMIT_ROLE.
     * @param _limitIncrease Amount by which the limit should be increased.
     */
    function temporarilyIncreaseLimit(uint _limitIncrease) public onlyRole(LIMIT_ROLE) {
        limiter.temporarilyIncreaseLimit(_limitIncrease);
        emit LimitTemporarilyIncreased(_limitIncrease);
    }

    /**
     * @dev Temporarily decreases the 24-hour transfer limiter.
     * Can only be called by an account with the LIMIT_ROLE.
     * @param _limitDecrease Amount by which the limit should be decreased.
     */
    function temporarilyDecreaseLimit(uint _limitDecrease) public onlyRole(LIMIT_ROLE) {
        limiter.temporarilyDecreaseLimit(_limitDecrease);
        emit LimitTemporarilyDecreased(_limitDecrease);
    }

    /**
     * @dev Transfers the token to a specified beneficiary, subject to 24 hours limits.
     * Can only be called by an account with the TRANSFER_ROLE.
     * @param _beneficiary Address of the beneficiary to receive the tokens.
     * @param _amount Amount of tokens to be transferred.
     */
    function transfer(address _beneficiary, uint _amount) public onlyRole(TRANSFER_ROLE) {
        if (!limiter.addTransfer(_amount)) {
            revert LimitExceeded();
        }
        beneficiaries.addBeneficiaryTransfer(_beneficiary, _amount);
        token.transfer(_beneficiary, _amount);
        emit Transferred(_beneficiary, _amount);
    }

    /**
     * @dev Transfers a specified token to a specified address.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * @param _token Token to be transferred.
     * @param _to Address to receive the tokens.
     * @param _amount Amount of tokens to be transferred.
     */
    function transfer(IERC20 _token, address _to, uint _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _token.transfer(_to, _amount);
        emit Transferred(_token, _to, _amount);
    }

    /**
     * @dev Mints tokens to the wallet.
     * Can only be called by an account with the MINT_ROLE.
     * @param _amount Amount of tokens to be minted.
     */
    function mint(uint _amount) public onlyRole(MINT_ROLE) {
        token.mint(_amount);
        emit Minted(_amount);
    }

    /**
     * @dev Burns tokens from the wallet.
     * Can only be called by an account with the BURN_ROLE.
     * @param _amount Amount of tokens to be minted.
     */
    function burn(uint _amount) public onlyRole(BURN_ROLE) {
        token.burn(_amount);
        emit Burned(_amount);
    }
}

