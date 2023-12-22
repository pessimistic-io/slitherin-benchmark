// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Police HQ - tracking criminals - staying corrupt
interface ICriminalRecords {
	/// @notice Emitted when the wanted level of a criminal changes
	/// @param criminal The user that committed a crime
	/// @param level The criminals new wanted level
	event Wanted(address indexed criminal, uint256 level);

	/// @notice Emitted when a report against a criminal was filed
	/// @param snitch The user that reported the theft
	/// @param thief The user that got reported
	/// @param stolenId The tokenID of the stolen NFT
	event Reported(address indexed snitch, address indexed thief, uint256 indexed stolenId);

	/// @notice Emitted when a the criminal is arrested
	/// @param snitch The user that reported the theft
	/// @param thief The user that got reported
	/// @param stolenId The tokenID of the stolen NFT
	event Arrested(address indexed snitch, address indexed thief, uint256 indexed stolenId);

	/// @notice Struct to store the the details of a report
	struct Report {
		uint256 stolenId;
		uint256 timestamp;
	}

	/// @notice Maximum wanted level a thief can have
	/// @return The maximum wanted level
	function maximumWanted() external view returns (uint8);

	/// @notice The wanted level sentence given for a crime
	/// @return The sentence
	function sentence() external view returns (uint8);

	/// @notice The percentage between 0-100 a report is successful and the thief is caught
	/// @return The chance
	function thiefCaughtChance() external view returns (uint8);

	/// @notice Time that has to pass between the report and the arrest of a criminal
	/// @return The time
	function reportDelay() external view returns (uint32);

	/// @notice Time how long a report will be valid
	/// @return The time
	function reportValidity() external view returns (uint32);

	/// @notice How much to bribe to remove a wanted level
	/// @return The cost of a bribe
	function bribePerLevel() external view returns (uint256);

	/// @notice The reward if a citizen successfully reports a criminal
	/// @return The reward
	function reward() external view returns (uint256);

	/// @notice Decrease the criminals wanted level by providing a bribe denominated in CounterfeitMoney
	/// @dev The decrease depends on {bribePerLevel}. If more CounterfeitMoney is given
	/// then needed it will not be transferred / burned.
	/// Emits a {Wanted} Event
	/// @param criminal The criminal whose wanted level should be reduced
	/// @param amount Amount of CounterfeitMoney available to pay the bribe
	/// @return Number of wanted levels that have been removed
	function bribe(address criminal, uint256 amount) external returns (uint256);

	/// @notice Decrease the criminals wanted level by providing a bribe denominated in CounterfeitMoney and a valid EIP-2612 Permit
	/// @dev Same as {xref-ICriminalRecords-bribe-address-uint256-}[`bribe`], with additional signature parameters which
	/// allow the approval and transfer of CounterfeitMoney in a single Transaction using EIP-2612 Permits
	/// Emits a {Wanted} Event
	/// @param criminal The criminal whose wanted level should be reduced
	/// @param amount Amount of CounterfeitMoney available to pay the bribe
	/// @param deadline timestamp until when the given signature will be valid
	/// @param v The parity of the y co-ordinate of r of the signature
	/// @param r The x co-ordinate of the r value of the signature
	/// @param s The x co-ordinate of the s value of the signature
	/// @return Number of wanted levels that have been removed
	function bribeCheque(
		address criminal,
		uint256 amount,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external returns (uint256);

	/// @notice Report the theft of a stolen NFT, required to trigger an arrest
	/// @dev Emits a {Reported} Event
	/// @param stolenId The stolen NFTs tokenID that should be reported
	function reportTheft(uint256 stolenId) external;

	/// @notice After previous report was filed the arrest can be triggered
	/// If the arrest is successful the stolen NFT will be returned / burned
	/// If the thief gets away another report has to be filed
	/// @dev Emits a {Arrested} and {Wanted} Event
	/// @return Returns true if the report was successful
	function arrest() external returns (bool);

	/// @notice Returns the wanted level of a given criminal
	/// @param criminal The criminal whose wanted level should be returned
	/// @return The criminals wanted level
	function getWanted(address criminal) external view returns (uint256);

	// @notice Returns whether report data and processing state
	/// @param reporter The reporter who reported the theft
	/// @return stolenId The reported stolen NFT
	/// @return timestamp The timestamp when the theft was reported
	/// @return processed true if the report has been processed, false if not reported / processed or expired
	function getReport(address reporter)
		external
		view
		returns (
			uint256,
			uint256,
			bool
		);

	/// @notice Executed when a theft of a NFT was witnessed, increases the criminals wanted level
	/// @dev Emits a {Wanted} Event
	/// @param criminal The criminal who committed the crime
	function crimeWitnessed(address criminal) external;

	/// @notice Executed when a transfer of a NFT was witnessed, increases the receivers wanted level
	/// @dev Emits a {Wanted} Event
	/// @param from The sender of the stolen NFT
	/// @param to The receiver of the stolen NFT
	function exchangeWitnessed(address from, address to) external;

	/// @notice Allows the criminal to surrender and to decrease his wanted level
	/// @dev Emits a {Wanted} Event
	/// @param criminal The criminal who turned himself in
	function surrender(address criminal) external;
}

