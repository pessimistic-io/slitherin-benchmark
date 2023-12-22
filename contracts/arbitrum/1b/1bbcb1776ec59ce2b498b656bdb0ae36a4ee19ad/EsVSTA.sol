// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";
import "./VestaMath.sol";
import "./EsVSTAModel.sol";
import "./IEsVSTA.sol";

contract EsVSTA is ERC20Upgradeable, OwnableUpgradeable, TokenTransferrer, IEsVSTA {
	address public vstaToken;
	uint128 public vestingDuration;

	mapping(address => bool) private isHandler;
	mapping(address => VestingDetails) private vestingDetails;

	function setUp(address _vsta, uint128 _vestingDuration) external initializer {
		__Ownable_init();
		__ERC20_init("Escrowed VSTA", "EsVSTA");
		vstaToken = _vsta;
		vestingDuration = _vestingDuration;
	}

	modifier validateHandler() {
		if (!isHandler[msg.sender]) revert Unauthorized();
		_;
	}

	function transfer(address to, uint256 amount)
		public
		override
		validateHandler
		returns (bool)
	{
		address owner = _msgSender();
		_transfer(owner, to, amount);
		return true;
	}

	function transferFrom(
		address from,
		address to,
		uint256 amount
	) public override validateHandler returns (bool) {
		address spender = _msgSender();
		_spendAllowance(from, spender, amount);
		_transfer(from, to, amount);
		return true;
	}

	function convertVSTAToEsVSTA(uint128 _amount) external override validateHandler {
		_performTokenTransferFrom(vstaToken, msg.sender, address(this), _amount, false);
		_mint(msg.sender, _amount);
		emit EsVSTAMinted(_amount);
	}

	function vestEsVSTA(uint128 _amount) external override {
		VestingDetails storage userVestingDetails = vestingDetails[msg.sender];

		if (userVestingDetails.amount > 0) {
			claimVSTA();
		}

		userVestingDetails.amount += _amount;
		userVestingDetails.startDate = uint128(block.timestamp);
		userVestingDetails.duration = vestingDuration;

		_burn(msg.sender, _amount);

		emit UpdateVestingDetails(msg.sender, _amount, block.timestamp, vestingDuration);
	}

	function claimVSTA() public override {
		VestingDetails memory userVestingDetails = vestingDetails[msg.sender];

		uint128 timeVested = uint128(block.timestamp) - userVestingDetails.startDate;
		uint128 amountClaimable;

		if (timeVested < userVestingDetails.duration) {
			uint128 currentEntitledAmount = uint128(
				VestaMath.mulDiv(
					userVestingDetails.amount,
					timeVested,
					userVestingDetails.duration
				)
			);

			amountClaimable = currentEntitledAmount - userVestingDetails.amountClaimed;

			vestingDetails[msg.sender].amountClaimed = currentEntitledAmount;
		} else {
			amountClaimable = userVestingDetails.amount - userVestingDetails.amountClaimed;

			vestingDetails[msg.sender].amountClaimed = 0;
			vestingDetails[msg.sender].amount = 0;

			emit FinishVesting(msg.sender);
		}

		if (amountClaimable > 0) {
			_performTokenTransfer(vstaToken, msg.sender, amountClaimable, false);

			emit ClaimVSTA(msg.sender, amountClaimable);
		}
	}

	function setHandler(address _handler, bool _isActive) external override onlyOwner {
		isHandler[_handler] = _isActive;
	}

	function setVestingDuration(uint128 _vestingDuration) external override onlyOwner {
		vestingDuration = _vestingDuration;
	}

	function claimableVSTA()
		external
		view
		override
		returns (uint256 amountClaimable_)
	{
		VestingDetails memory userVestingDetails = vestingDetails[msg.sender];

		uint256 timeVested = block.timestamp - userVestingDetails.startDate;

		if (timeVested < userVestingDetails.duration) {
			uint256 currentEntitledAmount = (userVestingDetails.amount * timeVested) /
				userVestingDetails.duration;

			amountClaimable_ = currentEntitledAmount - userVestingDetails.amountClaimed;
		} else {
			amountClaimable_ =
				userVestingDetails.amount -
				userVestingDetails.amountClaimed;
		}
	}

	function getIsHandler(address _user) external view returns (bool) {
		return isHandler[_user];
	}

	function getVestingDetails(address _user)
		external
		view
		override
		returns (VestingDetails memory)
	{
		return vestingDetails[_user];
	}

	function getUserVestedAmount(address _user)
		external
		view
		override
		returns (uint256)
	{
		return vestingDetails[_user].amount;
	}

	function getUserVestedAmountClaimed(address _user)
		external
		view
		override
		returns (uint256)
	{
		return vestingDetails[_user].amountClaimed;
	}

	function getUserVestingStartDate(address _user)
		external
		view
		override
		returns (uint128)
	{
		return vestingDetails[_user].startDate;
	}

	function getUserVestingDuration(address _user)
		external
		view
		override
		returns (uint128)
	{
		return vestingDetails[_user].duration;
	}
}


