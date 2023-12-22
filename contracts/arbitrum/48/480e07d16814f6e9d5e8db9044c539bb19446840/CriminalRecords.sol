// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC721.sol";
import "./ICriminalRecords.sol";
import "./ICounterfeitMoney.sol";
import "./IStolenNFT.sol";

error BribeIsNotEnough();
error CaseNotFound();
error NotTheLaw();
error ProcessingReport();
error ReportAlreadyFiled();
error SurrenderInstead();
error SuspectNotWanted();
error TheftNotReported();
error ThiefGotAway();
error ThiefIsHiding();

/// @title Police HQ - tracking criminals - staying corrupt
contract CriminalRecords is ICriminalRecords, Ownable {
	/// @inheritdoc ICriminalRecords
	uint8 public override maximumWanted = 50;
	/// @inheritdoc ICriminalRecords
	uint8 public override sentence = 2;
	/// @inheritdoc ICriminalRecords
	uint8 public override thiefCaughtChance = 40;
	/// @inheritdoc ICriminalRecords
	uint32 public override reportDelay = 2 minutes;
	/// @inheritdoc ICriminalRecords
	uint32 public override reportValidity = 24 hours;
	/// @inheritdoc ICriminalRecords
	uint256 public override reward = 100 ether;
	/// @inheritdoc ICriminalRecords
	uint256 public override bribePerLevel = 100 ether;

	/// ERC20 token used to pay bribes and rewards
	ICounterfeitMoney public money;
	/// ERC721 token which is being monitored by the authorities
	IStolenNFT public stolenNFT;
	/// Contracts that cannot be sentenced
	mapping(address => bool) public aboveTheLaw;
	/// Officers / Contracts that can track and sentence others
	mapping(address => bool) public theLaw;

	/// Tracking the reports for identification
	uint256 private _caseNumber;
	/// Tracking the crime reporters and the time since their last report
	mapping(address => Report) private _reports;
	/// Tracking the criminals and their wanted level
	mapping(address => uint8) private _wantedLevel;

	constructor(
		address _owner,
		address _stolenNft,
		address _money,
		address _stakingHideout,
		address _blackMarket
	) Ownable(_owner) {
		stolenNFT = IStolenNFT(_stolenNft);
		money = ICounterfeitMoney(_money);

		theLaw[_stolenNft] = true;
		aboveTheLaw[address(0)] = true;
		aboveTheLaw[_stakingHideout] = true;
		aboveTheLaw[_blackMarket] = true;
	}

	/// @inheritdoc ICriminalRecords
	function bribe(address criminal, uint256 amount) public override returns (uint256) {
		uint256 wantedLevel = _wantedLevel[criminal];
		if (wantedLevel == 0) revert SuspectNotWanted();
		if (amount < bribePerLevel) revert BribeIsNotEnough();

		uint256 levels = amount / bribePerLevel;
		if (wantedLevel < levels) {
			levels = wantedLevel;
		}
		uint256 cost = levels * bribePerLevel;

		_decreaseWanted(criminal, uint8(levels));

		money.burn(msg.sender, cost);

		return levels;
	}

	/// @inheritdoc ICriminalRecords
	function bribeCheque(
		address criminal,
		uint256 amount,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override returns (uint256) {
		money.permit(criminal, address(this), amount, deadline, v, r, s);
		return bribe(criminal, amount);
	}

	/// @inheritdoc ICriminalRecords
	function reportTheft(uint256 stolenId) external override {
		address holder = stolenNFT.ownerOf(stolenId);

		if (msg.sender == holder) revert SurrenderInstead();
		if (aboveTheLaw[holder]) revert ThiefIsHiding();
		if (_wantedLevel[holder] == 0) revert SuspectNotWanted();
		if (
			_reports[msg.sender].stolenId == stolenId &&
			block.timestamp - _reports[msg.sender].timestamp <= reportValidity
		) revert ReportAlreadyFiled();

		_reports[msg.sender] = Report(stolenId, block.timestamp);

		emit Reported(msg.sender, holder, stolenId);
	}

	/// @inheritdoc ICriminalRecords
	function arrest() external override returns (bool) {
		Report memory report = _reports[msg.sender];
		if (report.stolenId == 0) revert TheftNotReported();
		if (block.timestamp - report.timestamp < reportDelay) revert ProcessingReport();
		if (block.timestamp - report.timestamp > reportValidity) revert ThiefGotAway();

		delete _reports[msg.sender];
		_caseNumber++;

		address holder = stolenNFT.ownerOf(report.stolenId);
		uint256 holderWanted = _wantedLevel[holder];

		uint256 kindaRandom = uint256(
			keccak256(
				abi.encodePacked(
					_caseNumber,
					holder,
					holderWanted,
					report.timestamp,
					block.timestamp,
					blockhash(block.number)
				)
			)
		) % 100; //0-100

		// Arrest is not possible if thief managed to hide or get rid of wanted level
		bool arrested = !aboveTheLaw[holder] &&
			holderWanted > 0 &&
			kindaRandom < thiefCaughtChance + holderWanted;

		if (arrested) {
			_increaseWanted(holder, sentence);

			emit Arrested(msg.sender, holder, report.stolenId);

			stolenNFT.swatted(report.stolenId);

			money.print(msg.sender, reward * holderWanted);
		}

		return arrested;
	}

	/// @inheritdoc ICriminalRecords
	function crimeWitnessed(address criminal) external override onlyTheLaw {
		_increaseWanted(criminal, sentence);
	}

	/// @inheritdoc ICriminalRecords
	function exchangeWitnessed(address from, address to) external override onlyTheLaw {
		if (_wantedLevel[from] > 0 && from != to) {
			_increaseWanted(to, sentence);
		}
	}

	/// @inheritdoc ICriminalRecords
	function surrender(address criminal) external override onlyTheLaw {
		_decreaseWanted(criminal, sentence);
	}

	/// @notice Executed when a theft of a NFT was witnessed, increases the criminals wanted level
	/// @dev Can only be called by the current owner
	/// @param _maxWanted Maximum wanted level a thief can have
	/// @param _sentence The wanted level sentence given for a crime
	/// @param _reportDelay The time that has to pass between a users reports
	/// @param _thiefCaughtChance The chance a report will be successful
	/// @param _reward The reward if a citizen successfully reports a criminal
	/// @param _bribePerLevel How much to bribe to remove a wanted level
	function setWantedParameters(
		uint8 _maxWanted,
		uint8 _sentence,
		uint8 _thiefCaughtChance,
		uint32 _reportDelay,
		uint32 _reportValidity,
		uint256 _reward,
		uint256 _bribePerLevel
	) external onlyOwner {
		maximumWanted = _maxWanted;
		sentence = _sentence;
		thiefCaughtChance = _thiefCaughtChance;
		reportDelay = _reportDelay;
		reportValidity = _reportValidity;
		reward = _reward;
		bribePerLevel = _bribePerLevel;

		emit WantedParamChange(
			maximumWanted,
			sentence,
			thiefCaughtChance,
			reportDelay,
			reportValidity,
			reward,
			bribePerLevel
		);
	}

	/// @notice Set which addresses / contracts are above the law and cannot be sentenced / tracked
	/// @dev Can only be called by the current owner, can also be used to reset addresses
	/// @param badgeNumber Address which should be set
	/// @param state If the given address should be above the law or not
	function setAboveTheLaw(address badgeNumber, bool state) public onlyOwner {
		aboveTheLaw[badgeNumber] = state;
		emit Promotion(badgeNumber, true, state);
	}

	/// @notice Set which addresses / contracts are authorized to sentence thief's
	/// @dev Can only be called by the current owner, can also be used to reset addresses
	/// @param badgeNumber Address which should be set
	/// @param state If the given address should authorized or not
	function setTheLaw(address badgeNumber, bool state) external onlyOwner {
		theLaw[badgeNumber] = state;
		emit Promotion(badgeNumber, false, state);
	}

	/// @inheritdoc ICriminalRecords
	function getReport(address reporter)
		external
		view
		returns (
			uint256,
			uint256,
			bool
		)
	{
		if (_reports[reporter].stolenId == 0) revert CaseNotFound();
		bool processed = block.timestamp - _reports[reporter].timestamp >= reportDelay &&
			block.timestamp - _reports[reporter].timestamp <= reportValidity;

		return (_reports[reporter].stolenId, _reports[reporter].timestamp, processed);
	}

	/// @inheritdoc ICriminalRecords
	function getWanted(address criminal) external view override returns (uint256) {
		return _wantedLevel[criminal];
	}

	/// @notice Increase a criminals wanted level, except if they are above the law
	/// @dev aboveTheLaw[criminal] avoids increasing e.g. the BlackMarkets wanted level on receiving a listing
	/// aboveTheLaw[msg.sender] avoids increasing e.g. the BlackMarket buyers wanted level
	/// @param criminal The caught criminal
	/// @param increase The amount the wanted level should be increased
	function _increaseWanted(address criminal, uint8 increase) internal {
		if (aboveTheLaw[criminal] || aboveTheLaw[msg.sender]) return;

		uint8 currentLevel = _wantedLevel[criminal];
		uint8 nextLevel;

		unchecked {
			nextLevel = currentLevel + increase;
		}
		if (nextLevel < currentLevel || nextLevel > maximumWanted) {
			nextLevel = maximumWanted;
		}

		_wantedLevel[criminal] = nextLevel;
		emit Wanted(criminal, nextLevel);
	}

	/// @notice Decrease a criminals wanted level, except if they are above the law
	/// @dev If current > max the maximumWanted will be used (in case the params changed)
	/// @param criminal The criminal
	/// @param decrease The amount the wanted level should be decreased
	function _decreaseWanted(address criminal, uint8 decrease) internal {
		if (aboveTheLaw[criminal] || aboveTheLaw[msg.sender]) return;

		uint8 currentLevel = _wantedLevel[criminal];
		uint8 nextLevel = 0;

		if (currentLevel > maximumWanted) {
			currentLevel = maximumWanted;
		}

		unchecked {
			if (decrease < currentLevel) {
				nextLevel = currentLevel - decrease;
			}
		}

		_wantedLevel[criminal] = nextLevel;
		emit Wanted(criminal, nextLevel);
	}

	/// @dev Modifier to only allow msg.senders that are the law to execute a function
	modifier onlyTheLaw() {
		if (!theLaw[msg.sender]) revert NotTheLaw();
		_;
	}

	/// @notice Emitted when theLaw/aboveTheLaw is set or unset
	/// @param user The user that got promoted / demoted
	/// @param aboveTheLaw Whether the user is set to be theLaw or aboveTheLaw
	/// @param state true if it was a promotion, false if it was a demotion
	event Promotion(address indexed user, bool aboveTheLaw, bool state);

	/// @notice Emitted when any wanted parameter is being changed
	/// @param maxWanted Maximum wanted level a thief can have
	/// @param sentence The wanted level sentence given for a crime
	/// @param thiefCaughtChance The chance a report will be successful
	/// @param reportDelay The time that has to pass between report and arrest
	/// @param reportValidity The time the report is valid for
	/// @param reward The reward if a citizen successfully reports a criminal
	/// @param bribePerLevel How much to bribe to remove a wanted level
	event WantedParamChange(
		uint8 maxWanted,
		uint8 sentence,
		uint256 thiefCaughtChance,
		uint256 reportDelay,
		uint256 reportValidity,
		uint256 reward,
		uint256 bribePerLevel
	);
}

