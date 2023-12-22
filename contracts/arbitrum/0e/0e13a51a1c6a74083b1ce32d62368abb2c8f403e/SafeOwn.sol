pragma solidity 0.8.19;

/**
* @dev Contract defines way for 2-setp access control for the owner of contract.
* To avoid accidental transfer owner will have to first propose a new owner
* then new owner have to accept the ownership.
*/
abstract contract SafeOwn {

	address private _Owner;

	address private _pendingOwner;

	/**
	* @dev Emitted when the Ownership is transferred.
     */
	event OwnershipTransferred(
		address indexed currentOwner,
		address indexed newOwner,
		uint256 transferredTimestamp
	);

	/**
	* @notice Initializes the Deployer as the Owner of the contract.
     */

	constructor()
    {
		_Owner = msg.sender;
		emit OwnershipTransferred(address(0), _Owner, block.timestamp);
	}

	/**
	* @notice Throws if the caller is not the Owner.
     */
	modifier onlyOwner()
    {
		require(Owner() == msg.sender, "SafeOwn: Caller is the not the Owner");
		_;
	}

	/**
	* @notice Throws if the caller is not the Pending Owner.
     */
	modifier onlyPendingOwner()
    {
		require(_pendingOwner == msg.sender, "SafeOwn: Caller is the not the Pending Owner");
		_;
	}

	/**
	 * @notice Returns the current Owner.
     * @dev Returns owner of contract
     */

	function Owner()
	public
	view
	virtual
	returns (address)
    {
		return _Owner;
	}

	/**
	 * @notice Returns the Pending Owner.
     */
	function pendingOwner()
	public
	view
	virtual
	returns (address)
    {
		return _pendingOwner;
	}

	/**
	 * @notice Owner can propose ownership to a new Owner(newOwner).
     * @param _newOwner address of the new owner to propose ownership to.
     */
	function proposeOwnership(
		address _newOwner
	)
    public
	virtual
	onlyOwner
    {
		require(_newOwner != address(0), "SafeOwn: New Owner can not be a Zero Address");
		_pendingOwner = _newOwner;
	}

	/**
	 * @notice Pending Owner can accept the ownership proposal and become the new Owner.
     */
	function acceptOwnership()
	public
	virtual
	onlyPendingOwner
    {
		address currentOwner = _Owner;
		address newOwner = _pendingOwner;
		_Owner = _pendingOwner;
		_pendingOwner = address(0);
		emit OwnershipTransferred(currentOwner, newOwner, block.timestamp);
	}
}

