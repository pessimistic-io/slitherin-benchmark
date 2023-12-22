// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IModuleInterest {
	error NotInterestManager();
	error CannotBeZero();
	error NoDebtFound();

	event InterestMinted(uint256 interest);
	event DebtChanged(address user, uint256 debt);
	event SystemDebtChanged(uint256 debt);
	event RiskChanged(uint8 risk);
	event EIRChanged(uint256 newEIR);

	function increaseDebt(address _vault, uint256 _debt)
		external
		returns (uint256 addedInterest_);

	function decreaseDebt(address _vault, uint256 _debt)
		external
		returns (uint256 addedInterest_);

	function exit(address _vault) external returns (uint256 addedInterest_);

	function updateEIR(uint256 _vstPrice)
		external
		returns (uint256 mintedInterest_);

	function getNotEmittedInterestRate(address user)
		external
		view
		returns (uint256);

	function getDebtOf(address _vault) external view returns (uint256);

	function syncWithProtocol(uint256 _amount) external;
}


