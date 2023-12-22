pragma solidity ^0.8.11;

import "./SafeMathUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IVestingVsta.sol";

contract VestingVesta is OwnableUpgradeable, IVestingVsta {
	using SafeERC20Upgradeable for IERC20Upgradeable;
	using SafeMathUpgradeable for uint256;

	error NoPermission();
	error EntityNotFound();
	error InvalidAddress();
	error DuplicatedVestingRule();
	error ClaimingLockHigherThanVestingLock();
	error VestingTimestampLowerThanBlockTimestamp();
	error SupplyCannotBeZero();
	error NewSupplyGoesToZero();
	error NewSupplyHigherOnReduceMethod();

	struct Rule {
		uint256 createdDate;
		uint256 totalSupply;
		uint256 startVestingDate;
		uint256 endVestingDate;
		uint256 claimed;
	}

	string public constant NAME = "VestingVesta";
	uint256 public constant SIX_MONTHS = 26 weeks; //4.3 * 6 == 25.8 -> 26
	uint256 public constant TWO_YEARS = 730 days;

	IERC20Upgradeable public vstaToken;
	uint256 public assignedVSTATokens;

	mapping(address => bool) public admins;
	mapping(address => mapping(uint256 => Rule)) public entitiesVesting;

	modifier entityRuleExists(address _entity, uint256 _vestingType) {
		if (!isEntityExits(_entity, _vestingType)) {
			revert EntityNotFound();
		}

		_;
	}

	modifier isAdmin() {
		if (!admins[msg.sender] && msg.sender != owner()) revert NoPermission();
		_;
	}

	function setUp(address _vstaAddress, address _whitelistAddr)
		external
		initializer
	{
		if (_whitelistAddr == address(0) || _vstaAddress == address(0))
			revert InvalidAddress();

		__Ownable_init();

		admins[_whitelistAddr] = true;
		vstaToken = IERC20Upgradeable(_vstaAddress);
	}

	function setAdmin(address _wallet, bool _status) public onlyOwner {
		admins[_wallet] = _status;
	}

	function addEntityVestingWithInitialDateOnly(
		address _entity,
		uint256 _vestingType,
		uint256 _totalSupply,
		uint256 _initialDateTimestamp
	) external override isAdmin {
		_addEntityVesting(
			_entity,
			_vestingType,
			_totalSupply,
			_initialDateTimestamp,
			SIX_MONTHS,
			TWO_YEARS
		);
	}

	function addEntityVestingWithConfig(
		address _entity,
		uint256 _vestingType,
		uint256 _totalSupply,
		uint256 _initialDateTimestamp,
		uint256 _lockClaimingInSeconds,
		uint256 _vestingDurationInSeconds
	) external override isAdmin {
		if (_lockClaimingInSeconds > _vestingDurationInSeconds)
			revert ClaimingLockHigherThanVestingLock();

		_addEntityVesting(
			_entity,
			_vestingType,
			_totalSupply,
			_initialDateTimestamp,
			_lockClaimingInSeconds,
			_vestingDurationInSeconds
		);
	}

	function addEntityVesting(
		address _entity,
		uint256 _vestingType,
		uint256 _totalSupply
	) external override isAdmin {
		_addEntityVesting(
			_entity,
			_vestingType,
			_totalSupply,
			block.timestamp,
			SIX_MONTHS,
			TWO_YEARS
		);
	}

	function _addEntityVesting(
		address _entity,
		uint256 _vestingType,
		uint256 _totalSupply,
		uint256 _initialDateTimestamp,
		uint256 _lockClaimingInSeconds,
		uint256 _vestingDurationInSeconds
	) internal {
		if (address(0) == _entity) revert InvalidAddress();
		if (isEntityExits(_entity, _vestingType)) revert DuplicatedVestingRule();
		if (_totalSupply == 0) revert SupplyCannotBeZero();

		assignedVSTATokens += _totalSupply;

		entitiesVesting[_entity][_vestingType] = Rule(
			_initialDateTimestamp,
			_totalSupply,
			_initialDateTimestamp + _lockClaimingInSeconds,
			_initialDateTimestamp + _vestingDurationInSeconds,
			0
		);

		vstaToken.safeTransferFrom(msg.sender, address(this), _totalSupply);
	}

	function lowerEntityVesting(
		address _entity,
		uint256 _vestingType,
		uint256 _newTotalSupply,
		bool _isAnError
	) external override onlyOwner entityRuleExists(_entity, _vestingType) {
		if (_newTotalSupply == 0) revert SupplyCannotBeZero();

		if (!_isAnError) {
			sendVSTATokenToEntity(_entity, _vestingType);
		}

		Rule storage vestingRule = entitiesVesting[_entity][_vestingType];

		if (_newTotalSupply <= vestingRule.claimed) revert NewSupplyGoesToZero();
		if (_newTotalSupply >= vestingRule.totalSupply) {
			revert NewSupplyHigherOnReduceMethod();
		}

		uint256 removedSupply = vestingRule.totalSupply.sub(_newTotalSupply);
		assignedVSTATokens = assignedVSTATokens.sub(removedSupply);

		vestingRule.totalSupply = _newTotalSupply;
	}

	function addSupplyToEntityVesting(
		address _entity,
		uint256 _vestingType,
		uint256 _extraSupply
	) external override onlyOwner entityRuleExists(_entity, _vestingType) {
		Rule storage vestingRule = entitiesVesting[_entity][_vestingType];

		vestingRule.totalSupply = vestingRule.totalSupply.add(_extraSupply);
		assignedVSTATokens = assignedVSTATokens.add(_extraSupply);

		vstaToken.safeTransferFrom(msg.sender, address(this), _extraSupply);
	}

	function removeEntityVesting(
		address _entity,
		uint256 _vestingType,
		bool _isAnError
	) external override onlyOwner entityRuleExists(_entity, _vestingType) {
		if (!_isAnError) {
			sendVSTATokenToEntity(_entity, _vestingType);
		}

		Rule memory vestingRule = entitiesVesting[_entity][_vestingType];

		assignedVSTATokens = assignedVSTATokens.sub(
			vestingRule.totalSupply.sub(vestingRule.claimed)
		);

		delete entitiesVesting[_entity][_vestingType];
	}

	function claimVSTAToken(uint256 _vestingType)
		external
		override
		entityRuleExists(msg.sender, _vestingType)
	{
		sendVSTATokenToEntity(msg.sender, _vestingType);
	}

	function sendVSTATokenToEntity(address _entity, uint256 _vestingType)
		private
	{
		uint256 unclaimedAmount = getClaimableVSTA(_entity, _vestingType);
		if (unclaimedAmount == 0) return;

		Rule storage entityRule = entitiesVesting[_entity][_vestingType];
		entityRule.claimed += unclaimedAmount;

		assignedVSTATokens = assignedVSTATokens.sub(unclaimedAmount);
		vstaToken.safeTransfer(_entity, unclaimedAmount);
	}

	function transferUnassignedVSTA() external override onlyOwner {
		uint256 unassignedTokens = getUnassignVSTATokensAmount();

		if (unassignedTokens == 0) return;

		vstaToken.safeTransfer(msg.sender, unassignedTokens);
	}

	function getClaimableVSTA(address _entity, uint256 _vestingType)
		public
		view
		override
		returns (uint256 claimable)
	{
		Rule memory entityRule = entitiesVesting[_entity][_vestingType];
		claimable = 0;

		if (entityRule.startVestingDate > block.timestamp) return claimable;

		if (block.timestamp >= entityRule.endVestingDate) {
			claimable = entityRule.totalSupply.sub(entityRule.claimed);
		} else {
			claimable =
				(entityRule.totalSupply / TWO_YEARS) *
				(block.timestamp.sub(entityRule.createdDate));

			if (claimable <= entityRule.claimed) {
				claimable = 0;
			} else {
				claimable -= entityRule.claimed;
			}
		}

		return claimable;
	}

	function getUnassignVSTATokensAmount()
		public
		view
		override
		returns (uint256)
	{
		return vstaToken.balanceOf(address(this)).sub(assignedVSTATokens);
	}

	function getEntityVestingTotalSupply(address _entity, uint256 _vestingType)
		external
		view
		override
		returns (uint256)
	{
		return entitiesVesting[_entity][_vestingType].totalSupply;
	}

	function getEntityVestingLeft(address _entity, uint256 _vestingType)
		external
		view
		override
		returns (uint256)
	{
		Rule memory entityRule = entitiesVesting[_entity][_vestingType];
		return entityRule.totalSupply.sub(entityRule.claimed);
	}

	function isEntityExits(address _entity, uint256 _vestingType)
		public
		view
		override
		returns (bool)
	{
		return entitiesVesting[_entity][_vestingType].createdDate != 0;
	}
}

