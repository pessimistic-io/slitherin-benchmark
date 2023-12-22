// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface ILendingWallet {
	event Deposit(address indexed _token, uint256 _value);
	event Withdraw(address indexed _token, address _to, uint256 _value);
	event CollateralChanged(address indexed _token, uint256 _newValue);
	event DebtChanged(address indexed _token, uint256 _newValue);
	event RedistributionCollateralChanged(address indexed _token, uint256 _newValue);
	event RedistributionDebtChanged(address indexed _token, uint256 _newValue);
	event GasCompensationChanged(uint256 _newValue);
	event VstMinted(address indexed _to, uint256 _value);
	event SurplusCollateralChanged(uint256 _newValue);
	event UserSurplusCollateralChanged(address indexed _user, uint256 _newValue);

	/** 
	@notice Transfer any tokens from the contract to an address
	@dev requires WITHDRAW permission to execute this function
	@param _token address of the token you want to withdraw
	@param _to address you want to send to
	@param _amount the amount you want to send
	 */
	function transfer(
		address _token,
		address _to,
		uint256 _amount
	) external;

	/** 
	@notice Decrease the debt of a vault and burn the stable token of `_from` (normally, it's the vault's owner)
		*Normally: since we have a feature that allows a friend of the vault's owner to pay off the debts for the owner.
	@dev requires DEBT_ACCESS permission to execute this function
	@param _token address of the token used by the vault
	@param _from the address you want to burn the stable token from
	@param _amount the amount of debt you want to remove
	 */
	function decreaseDebt(
		address _token,
		address _from,
		uint256 _amount
	) external;

	/** 
	@notice Increase debt of a vault and mint the stable token to the vault's owner
	@dev requires DEBT_ACCESS permission to execute this function
	@param _token address of the token used by the vault
	@param _to the address you want to mint to
	@param _amountToMint the exact number you want to mint
	@param _amountToDebt the amount of debt you want to add to the vault. 
		e.g: 100 to mint + X for the fee. You don't want to send the fee to the user but want to include it
	 */
	function increaseDebt(
		address _token,
		address _to,
		uint256 _amountToMint,
		uint256 _amountToDebt
	) external;

	/** 
	@notice Move the collateral from the lending service to the Redistribution data.
	@dev requires REDISTRIBUTION_ACCESS permission to execute this function
	@param _token address of the token used by the vault
	@param _amount the amount we want to redistribute
	 */
	function moveCollateralToRedistribution(address _token, uint256 _amount) external;

	/** 
	@notice Move the debts from the lending service to the Redistribution data.
	@dev requires REDISTRIBUTION_ACCESS permission to execute this function
	@param _token address of the token used by the vault
	@param _amount the amount we want to redistribute
	 */
	function moveDebtToRedistribution(address _token, uint256 _amount) external;

	/** 
	@notice Move back the collateral from Redistribution to the lending service data.
	@dev requires REDISTRIBUTION_ACCESS permission to execute this function
	@param _token address of the token used by the vault
	@param _amount the amount we want to return
	 */
	function returnRedistributionCollateral(address _token, uint256 _amount) external;

	/** 
	@notice Move back the debt from Redistribution to the lending service data.
	@dev requires REDISTRIBUTION_ACCESS permission to execute this function
	@param _token address of the token used by the vault
	@param _amount the amount we want to return
	 */
	function returnRedistributionDebt(address _token, uint256 _amount) external;

	/** 
	@notice Mint an extra of stable token for gas compensation.
	@dev requires DEPOSIT permission to execute this function
	@param _amount the amount we want to mint
	 */
	function mintGasCompensation(uint256 _amount) external;

	/** 
	@notice Burn the gas compensation.
	@dev requires DEPOSIT permission to execute this function
	@param _amount the amount we want to burn
	 */
	function burnGasCompensation(uint256 _amount) external;

	/** 
	@notice Send gas compensation to a user
	@dev requires WITHDRAW permission to execute this function
	@param _user the address you want to send the gas compensation
	@param _amount the amount you want to send
	 */
	function refundGasCompensation(address _user, uint256 _amount) external;

	/** 
	@notice Mint directly into an account via a lending service. e.g for the fee when opening a vault.
	@dev requires WITHDRAW permission to execute this function
	@param _to the address you want to mint to.
	@param _amount the amount you want to mint
	@param _depositCallback trigger the callback function receiveERC20(address _token, uint256 _amount) if it's a contract
		IERC20Callback has been created for Vesta protocol's contracts to track the ERC20 flow.
	 */
	function mintVstTo(
		address _token,
		address _to,
		uint256 _amount,
		bool _depositCallback
	) external;

	/** 
	@notice Add surplus collateral to a user.
	@dev requires DEPOSIT permission to execute this function
		Most of the time, a surplus collateral happens on an execution of a third party user / service.
		It is not their job to pay the transfer fee of the collateral. 
		That's why we store it and the user will need to manually claim it.
	@param _token the address used by the lending service / vault
	@param _user the user that will be able to claim this surplus collateral
	@param _amount the amount of the surplus collateral
	 */
	function addSurplusCollateral(
		address _token,
		address _user,
		uint256 _amount
	) external;

	/** 
	@notice Claim the pending surplus collateral.
	@param _token the address used by the lending service / vault
	 */
	function claimSurplusCollateral(address _token) external;

	/** 
	@notice Total amount of gas compensation stored in the contract.
	@return _value total amount for the gas compensation
	 */
	function getGasCompensation() external view returns (uint256);

	/** 
	@notice Total amount of collateral by a lending service stored in the contract.
	@param _token address of the token used by the lending service
	@return _value total collateral from the lending service
	 */
	function getLendingCollateral(address _token) external view returns (uint256);

	/** 
	@notice Total amount of debts by a lending service stored in the contract.
	@param _token address of the token used by the lending service
	@return _value total debts of from the lending service
	 */
	function getLendingDebts(address _token) external view returns (uint256);

	/** 
	@notice Get both collateral and debts of a Lending Service
	@param _token address of the token used by the lending service
	@return collateral_ total collateral from the lending service
	@return debts_ total debts of from the lending service
	 */
	function getLendingBalance(address _token)
		external
		view
		returns (uint256 collateral_, uint256 debts_);

	/** 
	@notice Total stored collateral for redistribution from the lending service
	@param _token address of the token used by the lending service
	@return _value total collateral of the lending service
	 */
	function getRedistributionCollateral(address _token)
		external
		view
		returns (uint256);

	/** 
	@notice Total stored debts for redistribution from the lending service
	@param _token address of the token used by the lending service
	@return _value total debts of the lending service
	 */
	function getRedistributionDebt(address _token) external view returns (uint256);

	/** 
	@notice Total surplus collateral waiting to be claimed by the Lending Service
	@param _token address of the token used by the lending service
	@return _value total collateral of the lending service
	 */
	function getTotalSurplusCollateral(address _token) external view returns (uint256);

	/** 
	@notice Total surplus collateral of an user waiting to be claimed by the Lending Service
	@param _token address of the token used by the lending service
	@param _user address to look for surplus collateral
	@return _value total collateral waiting to be claimed by the user
	 */
	function getUserSurplusCollateral(address _token, address _user)
		external
		view
		returns (uint256);
}

