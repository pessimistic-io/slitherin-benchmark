// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IVestaGMXStaking {
	error CallerIsNotAnOperator(address _caller);
	error ZeroAmountPassed();
	error InvalidAddress();
	error InsufficientStakeBalance();
	error ETHTransferFailed(address to, uint256 amount);
	error ReentrancyDetected();
	error BPSHigherThanOneHundred();

	event StakingUpdated(uint256 totalStaking);
	event RewardReceived(uint256 reward);

	/**
		Stake: Allow a vault wallet to stake into GMX earning program
		@dev only called by an operator
		@dev `_amount` cannot be zero
		@param _behalfOf Vault Owner address
		@param _amount GMX that should be staked
	 */
	function stake(address _behalfOf, uint256 _amount) external;

	/**
		Unstake: unstake from GMX earning program
		@dev Can only be called by an operator
		@dev _amount can be zero
		@param _behalfOf address of the vault owner
		@param _amount amount you want to unstake
	 */
	function unstake(address _behalfOf, uint256 _amount) external;

	/**
		claim: Allow a vault owner to claim their reward without modifying their vault
	 */
	function claim() external;

	/**
		setOperator: Add or Remove an operator. An operator can stake and unstake.
		@dev Operator needs to be a contract address
		@dev Can only be called by an owner
		@param _address the address of the operator
		@param _enabled the access of the operator
	 */
	function setOperator(address _address, bool _enabled) external;

	/**
		setTreasuryFee: The share of the rewards that goes to the vault owners
		@dev BPS format (10_000 <-> 0);
		@param _sharesBPS the new shares of the vault owners
	 */
	function setTreasuryFee(uint256 _sharesBPS) external;

	/**
		setTreasury: set new Treasury address
		@param _newTreasury treasury address
	 */
	function setTreasury(address _newTreasury) external;

	/**
		getVaultStake: returns how much is staked from a vault owner
		@param _vaultOwner the address of the vault owner
		@return stake total token staked
	 */
	function getVaultStake(address _vaultOwner) external view returns (uint256);

	/**
		getVaultOwnerShare: Get the share of 
			the vault owner at the moment s/he interacted with the Staking contract.
		@param _vaultOwner address of the vault owner
		@return _originalShare the vault's share at the moment of the interaction with the contract.
	 */
	function getVaultOwnerShare(address _vaultOwner) external view returns (uint256);

	/**
		getVaultOwnerClaimable: returns how much the vault owner has earns and is pending for claiming
		@dev The returned number isn't an absolute number, it's an estimation.
		@param _vaultOwner the address of the vault owner
		@return claimable An close estimation of rewards reserved to the vault owner
	 */
	function getVaultOwnerClaimable(address _vaultOwner)
		external
		view
		returns (uint256);

	/**
		isOperator: find if a contract is an operator
		@notice An operator can only be a contract. For vesta, the contract will be ActivePool
		@param _operator the address of the contract
		@return status true if it's an operator
	 */
	function isOperator(address _operator) external view returns (bool);
}

