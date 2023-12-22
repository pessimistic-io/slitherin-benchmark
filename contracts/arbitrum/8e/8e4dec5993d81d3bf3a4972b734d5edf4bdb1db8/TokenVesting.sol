// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./Context.sol";
import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./AccessProtected.sol";

/**
@title Access Limiter to multiple owner-specified accounts.
@dev An address with role admin can:
- Can allocate tokens owned by the contract to a given recipient through a vesting agreement via the functions createGrant() (one by one) and createGrantsBatch() (batch).
- Can withdraw unallocated tokens owned by the contract via the function withdrawAdmin().
- Can revoke an active grant for a given address via the function revokeGrant().
- Can withdraw any ERC20 token owner by the contract and different than the vested token via the function withdrawOtherToken().
*/
contract TokenVesting is Context, AccessProtected, ReentrancyGuard {
	using SafeERC20 for IERC20;

	// Address of the token that we're vesting
	IERC20 public immutable tokenAddress;

	// Current total vesting allocation
	uint256 public numTokensReservedForVesting = 0;

	/**
    @notice A structure representing a Grant - supporting linear and cliff vesting.
     */
	struct Grant {
		uint40 startTimestamp;
		uint40 endTimestamp;
		uint40 cliffReleaseTimestamp;
		uint40 releaseIntervalSecs; // used for calculating the vested amount
		uint256 linearVestAmount; // vesting allocation, excluding cliff
		uint256 claimedAmount; // claimed so far, excluding cliff
		uint112 cliffAmount;
		bool isActive; // revoked if false
		uint40 deactivationTimestamp;
	}

	mapping(address => Grant) internal grants;
	address[] internal vestingRecipients;

	/**
    @notice Emitted on creation of new Grant
     */
	event GrantCreated(address indexed _recipient, Grant _grant);

	/**
    @notice Emitted on withdrawal from Grant
     */
	event Claimed(address indexed _recipient, uint256 _withdrawalAmount);

	/**
    @notice Emitted on Grant revoke
     */
	event GrantRevoked(
		address indexed _recipient,
		uint256 _numTokensWithheld,
		Grant _grant
	);

	/**
    @notice Emitted on admin withdrawal
     */
	event AdminWithdrawn(address indexed _recipient, uint256 _amountRequested);

	/**
    @notice Construct the contract, taking the ERC20 token to be vested as the parameter.
    @dev The owner can set the token in question when creating the contract.
    */
	constructor(IERC20 _tokenAddress) {
		require(address(_tokenAddress) != address(0), "INVALID_ADDRESS");
		tokenAddress = _tokenAddress;
	}

	/**
    @notice Basic getter for a Grant.
    @param _recipient - Grant recipient wallet address
     */
	function getGrant(address _recipient) external view returns (Grant memory) {
		return grants[_recipient];
	}

	/**
    @notice Check if Recipient has an active grant attached.
    @dev
    * Grant is considered active if:
    * - is active
    * - start timestamp is greater than 0
    *
    * We can use startTimestamp as a criterion because it is only assigned a value in
    * createGrant, and it is never modified afterwards. Thus, startTimestamp will have a value
    * only if a grant has been created. Moreover, we need to verify
    * that the grant is active (since this is has_Active_Grant).
    */
	modifier hasActiveGrant(address _recipient) {
		Grant memory _grant = grants[_recipient];
		require(_grant.startTimestamp > 0, "NO_ACTIVE_GRANT");

		// We however still need the active check, since (due to the name of the function)
		// we want to only allow active grants
		require(_grant.isActive, "NO_ACTIVE_GRANT");

		_;
	}

	/**
    @notice Check if the recipient has no active grant attached.
    @dev Requires that all fields are unset
    */
	modifier hasNoGrant(address _recipient) {
		Grant memory _grant = grants[_recipient];
		// A grant is only created when its start timestamp is nonzero
		// So, a zero value for the start timestamp means the grant does not exist
		require(_grant.startTimestamp == 0, "GRANT_ALREADY_EXISTS");
		_;
	}

	/**
    @notice Calculate the vested amount for a given Grant, at a given timestamp.
    @param _grant The grant in question
    @param _referenceTs Timestamp for which we're calculating
     */
	function _baseVestedAmount(
		Grant memory _grant,
		uint40 _referenceTs
	) internal pure returns (uint256) {
		// Does the Grant exist?
		if (!_grant.isActive && _grant.deactivationTimestamp == 0) {
			return 0;
		}

        uint256 vestAmt;

		// Has the Grant ended?
		if (_referenceTs > _grant.endTimestamp) {
			_referenceTs = _grant.endTimestamp;
		}

		// Has the cliff passed?
		if (_referenceTs >= _grant.cliffReleaseTimestamp) {
			vestAmt += _grant.cliffAmount;
		}

		// Has the vesting started? If so, calculate the vested amount linearly
		if (_referenceTs > _grant.startTimestamp) {
			uint40 currentVestingDurationSecs = _referenceTs -
				_grant.startTimestamp;

			// Round to releaseIntervalSecs
			uint40 truncatedCurrentVestingDurationSecs = (currentVestingDurationSecs /
					_grant.releaseIntervalSecs) * _grant.releaseIntervalSecs;

			uint40 finalVestingDurationSecs = _grant.endTimestamp -
				_grant.startTimestamp;

			// Calculate vested amount
			uint256 linearVestAmount = (_grant.linearVestAmount *
				truncatedCurrentVestingDurationSecs) / finalVestingDurationSecs;

			vestAmt += linearVestAmount;
		}

		return vestAmt;
	}

	/**
    @notice Calculate the vested amount for a given Recipient, at a given Timestamp.
    @param _recipient - Grant recipient wallet address
    @param _referenceTs - Reference date timestamp
    */
	function vestedAmount(
		address _recipient,
		uint40 _referenceTs
	) public view returns (uint256) {
		Grant memory _grant = grants[_recipient];
		uint40 vestEndTimestamp = _grant.isActive
			? _referenceTs
			: _grant.deactivationTimestamp;
		return _baseVestedAmount(_grant, vestEndTimestamp);
	}

	/**
    @notice Return total allocation for a given Recipient.
    @param _recipient - Grant recipient wallet address
     */
	function grantAllocation(address _recipient) public view returns (uint256) {
		Grant memory _grant = grants[_recipient];
		return _baseVestedAmount(_grant, _grant.endTimestamp);
	}

	/**
    @notice Currently claimable amount for a given Recipient.
    @param _recipient - Grant recipient wallet address
    */
	function claimableAmount(address _recipient) public view returns (uint256) {
		Grant memory _grant = grants[_recipient];
		return
			vestedAmount(_recipient, uint40(block.timestamp)) -
			_grant.claimedAmount;
	}

	/**
    @notice Remaining allocation for Recipient. Total allocation minus already withdrawn amount.
    @param _recipient - Grant recipient wallet address
    */
	function finalClaimableAmount(
		address _recipient
	) external view returns (uint256) {
		Grant storage _grant = grants[_recipient];
		uint40 vestEndTimestamp = _grant.isActive
			? _grant.endTimestamp
			: _grant.deactivationTimestamp;
		return
			_baseVestedAmount(_grant, vestEndTimestamp) - _grant.claimedAmount;
	}

	/**
    @notice Get all active recipients
    */
	function allVestingRecipients() external view returns (address[] memory) {
		return vestingRecipients;
	}

	/**
    @notice Get active recipients count
    */
	function numVestingRecipients() external view returns (uint256) {
		return vestingRecipients.length;
	}

	/**
    @notice Create Grant logic, called by createGrant and createGrantsBatch.
    @dev Only input validation. Does not check if the startTimestamp is in the past to allow to back-allocate.
    @param _recipient - Grant recipient wallet address
    @param _startTimestamp - Vesting start date timestamp
    @param _endTimestamp - Vesting end date timestamp
    @param _cliffReleaseTimestamp - Lump sum cliff release date timestamp. Usually equal to _startTimestamp, must be <= _startTimestamp, or 0 if no cliff
    @param _releaseIntervalSecs - Time between releases, expressed in seconds
    @param _linearVestAmount - Allocation to be linearly vested between _startTimestamp and _endTimestamp (excluding cliff)
    @param _cliffAmount - The amount released at _cliffReleaseTimestamp. Can be 0 if _cliffReleaseTimestamp is also 0.
     */
	function _createGrantUnchecked(
		address _recipient,
		uint40 _startTimestamp,
		uint40 _endTimestamp,
		uint40 _cliffReleaseTimestamp,
		uint40 _releaseIntervalSecs,
		uint112 _linearVestAmount,
		uint112 _cliffAmount
	) private hasNoGrant(_recipient) {
		require(_recipient != address(0), "INVALID_ADDRESS");
		require(_linearVestAmount + _cliffAmount > 0, "INVALID_VESTED_AMOUNT");
		require(_startTimestamp > 0, "INVALID_START_TIMESTAMP");
		require(_startTimestamp < _endTimestamp, "INVALID_END_TIMESTAMP");
		require(_releaseIntervalSecs > 0, "INVALID_RELEASE_INTERVAL");
		require(
			(_endTimestamp - _startTimestamp) % _releaseIntervalSecs == 0,
			"INVALID_INTERVAL_LENGTH"
		);

		// Both or neither of cliff parameters must be set.
		// If cliff is set, the cliff timestamp must be before or at the vesting timestamp
		require(
			(_cliffReleaseTimestamp > 0 &&
				_cliffAmount > 0 &&
				_cliffReleaseTimestamp <= _startTimestamp) ||
				(_cliffReleaseTimestamp == 0 && _cliffAmount == 0),
			"INVALID_CLIFF"
		);

		Grant storage _grant = grants[_recipient];
		_grant.startTimestamp = _startTimestamp;
		_grant.endTimestamp = _endTimestamp;
		_grant.cliffReleaseTimestamp = _cliffReleaseTimestamp;
		_grant.releaseIntervalSecs = _releaseIntervalSecs;
		_grant.linearVestAmount = _linearVestAmount;
		_grant.cliffAmount = _cliffAmount;
		_grant.isActive = true;

		uint256 allocatedAmount = _cliffAmount + _linearVestAmount;

		// Can we afford to create a new Grant?
		require(
			tokenAddress.balanceOf(address(this)) >=
				numTokensReservedForVesting + allocatedAmount,
			"INSUFFICIENT_BALANCE"
		);

		numTokensReservedForVesting += allocatedAmount;
		vestingRecipients.push(_recipient);
		emit GrantCreated(_recipient, _grant);
	}

	/**
    @notice Create a grant based on the input parameters.
    @param _recipient - Grant recipient wallet address
    @param _startTimestamp - Vesting start date timestamp
    @param _endTimestamp - Vesting end date timestamp
    @param _cliffReleaseTimestamp - Lump sum cliff release date timestamp. Usually equal to _startTimestamp, must be <= _startTimestamp, or 0 if no cliff
    @param _releaseIntervalSecs - Time between releases, expressed in seconds
    @param _linearVestAmount - Allocation to be linearly vested between _startTimestamp and _endTimestamp (excluding cliff)
    @param _cliffAmount - The amount released at _cliffReleaseTimestamp. Can be 0 if _cliffReleaseTimestamp is also 0.
     */
	function createGrant(
		address _recipient,
		uint40 _startTimestamp,
		uint40 _endTimestamp,
		uint40 _cliffReleaseTimestamp,
		uint40 _releaseIntervalSecs,
		uint112 _linearVestAmount,
		uint112 _cliffAmount
	) external onlyAdmin {
		_createGrantUnchecked(
			_recipient,
			_startTimestamp,
			_endTimestamp,
			_cliffReleaseTimestamp,
			_releaseIntervalSecs,
			_linearVestAmount,
			_cliffAmount
		);
	}

	/**
    @notice Simple for loop sequential batch create. Takes n-th element of each array to create the Grant.
        @param _recipients - Array of Grant recipient wallet address
        @param _startTimestamps - Array of vesting start date timestamps
        @param _endTimestamps - Array of vesting end date timestamps
        @param _cliffReleaseTimestamps - Array of cliff release date timestamps
        @param _releaseIntervalsSecs - Array of time intervals between releases, expressed in seconds
        @param _linearVestAmounts - Array of allocations
        @param _cliffAmounts - Array of cliff release amounts
     */
	function createGrantsBatch(
		address[] memory _recipients,
		uint40[] memory _startTimestamps,
		uint40[] memory _endTimestamps,
		uint40[] memory _cliffReleaseTimestamps,
		uint40[] memory _releaseIntervalsSecs,
		uint112[] memory _linearVestAmounts,
		uint112[] memory _cliffAmounts
	) external onlyAdmin {
		uint256 length = _recipients.length;
		require(
			_startTimestamps.length == length &&
				_endTimestamps.length == length &&
				_cliffReleaseTimestamps.length == length &&
				_releaseIntervalsSecs.length == length &&
				_linearVestAmounts.length == length &&
				_cliffAmounts.length == length,
			"ARRAY_LENGTH_MISMATCH"
		);

		for (uint256 i = 0; i < length; i++) {
			_createGrantUnchecked(
				_recipients[i],
				_startTimestamps[i],
				_endTimestamps[i],
				_cliffReleaseTimestamps[i],
				_releaseIntervalsSecs[i],
				_linearVestAmounts[i],
				_cliffAmounts[i]
			);
		}
	}

	/**
    @notice Withdraw the claimable balance. Only callable by active Grant recipients.
     */
	function claim() external nonReentrant {
		Grant storage usrGrant = grants[_msgSender()];

		uint256 vested = vestedAmount(_msgSender(), uint40(block.timestamp));

		require(
			vested > usrGrant.claimedAmount,
			"NOTHING_TO_WITHDRAW"
		);

		uint256 amountRemaining = vested - usrGrant.claimedAmount;
		require(amountRemaining > 0, "NOTHING_TO_WITHDRAW");

		usrGrant.claimedAmount += amountRemaining;
		numTokensReservedForVesting -= amountRemaining;

		// Reentrancy: internal vars have been changed by now
		tokenAddress.safeTransfer(_msgSender(), amountRemaining);

		emit Claimed(_msgSender(), amountRemaining);
	}

	/**
    @notice Allow the owner to withdraw any balance not currently tied up in Grants
    @param _amountRequested - Amount to withdraw
     */
	function withdrawAdmin(
		uint256 _amountRequested
	) public onlyAdmin nonReentrant {
		uint256 amountRemaining = amountAvailableToWithdrawByAdmin();
		require(amountRemaining >= _amountRequested, "INSUFFICIENT_BALANCE");

		// Reentrancy: No changes to internal vars, only transfer
		tokenAddress.safeTransfer(_msgSender(), _amountRequested);

		emit AdminWithdrawn(_msgSender(), _amountRequested);
	}

	/**
    @notice Revoke active Grant. Grant must exist and be active.
    @param _recipient - Grant recipient wallet address
    */
	function revokeGrant(
		address _recipient
	) external onlyAdmin hasActiveGrant(_recipient) {
		Grant storage _grant = grants[_recipient];
		uint256 finalVestAmt = grantAllocation(_recipient);

		require(_grant.claimedAmount < finalVestAmt, "NO_UNVESTED_AMOUNT");

		_grant.isActive = false;
		_grant.deactivationTimestamp = uint40(block.timestamp);

		uint256 vestedSoFarAmt = vestedAmount(
			_recipient,
			uint40(block.timestamp)
		);
		uint256 amountRemaining = finalVestAmt - vestedSoFarAmt;
		numTokensReservedForVesting -= amountRemaining;

		emit GrantRevoked(
			_recipient,
			amountRemaining,
			_grant
		);
	}

	/**
    @notice Withdraw a token which isn't controlled by the vesting contract. Useful when someone accidentally sends tokens to the contract
    that arent the token that the contract is configured vest (tokenAddress).
    @param _otherTokenAddress - the token which we want to withdraw
     */
	function withdrawOtherToken(
		IERC20 _otherTokenAddress
	) external onlyAdmin nonReentrant {
		require(_otherTokenAddress != tokenAddress, "INVALID_TOKEN"); // tokenAddress address is already sure to be nonzero due to constructor
		uint256 balance = _otherTokenAddress.balanceOf(address(this));
		require(balance > 0, "INSUFFICIENT_BALANCE");
		_otherTokenAddress.safeTransfer(_msgSender(), balance);
	}

	/**
	 * @notice How many tokens are available to withdraw by the admin.
	 */
	function amountAvailableToWithdrawByAdmin() public view returns (uint256) {
		return
			tokenAddress.balanceOf(address(this)) - numTokensReservedForVesting;
	}
}

