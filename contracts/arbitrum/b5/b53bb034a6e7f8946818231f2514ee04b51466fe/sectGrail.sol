// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { IXGrailToken } from "./IXGrailToken.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";

import { INFTPool } from "./INFTPool.sol";
import { INFTHandler } from "./INFTHandler.sol";
import { ISectGrail } from "./ISectGrail.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { ERC20PermitUpgradeable } from "./draft-ERC20PermitUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";

// import "hardhat/console.sol";

/// @title sectGrail
/// @notice sectGrail is a liquid wrapper for xGrail, an escrowed Grail token
/// @dev contract Camelot contract links:
/// xGrail: https://arbiscan.io/address/0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b//
/// USDC-ETH NFTPool: https://arbiscan.io/address/0x6bc938aba940fb828d39daa23a94dfc522120c11
/// YieldBooster: https://arbiscan.io/address/0xD27c373950E7466C53e5Cd6eE3F70b240dC0B1B1#code
contract sectGrail is
	ISectGrail,
	ERC20Upgradeable,
	INFTHandler,
	ERC20PermitUpgradeable,
	ReentrancyGuardUpgradeable,
	OwnableUpgradeable,
	PausableUpgradeable
{
	using SafeERC20 for IERC20;

	uint256[200] __pre_gap; // gap for upgrade safety allows to add inhertiance items

	mapping(address => uint256) public allocations;
	mapping(address => mapping(uint256 => address)) public positionOwners;
	mapping(address => bool) public whitelist;

	modifier onlyPositionOwner(address farm, uint256 positionId) {
		if (positionOwners[farm][positionId] != msg.sender) revert NotPositionOwner();
		_;
	}

	modifier onlyWhitelisted(address _address) {
		if (!whitelist[_address]) revert NotWhitelisted();
		_;
	}

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	IXGrailToken public xGrailToken;
	IERC20 public grailToken;

	// TODO is it better to hardcode xGrail address?
	function initialize(address _xGrail) public initializer {
		__Ownable_init();
		__ReentrancyGuard_init();
		__Pausable_init();
		__ERC20_init("liquid wrapper for xGrail", "sectGRAIL");
		xGrailToken = IXGrailToken(_xGrail);
		grailToken = IERC20(xGrailToken.grailToken());
	}

	/////////////////////////
	/// Oner methods
	/////////////////////////

	/// @notice whitelist an address to be used as farm or usage address
	function updateWhitelist(address _address, bool _whitelist) external onlyOwner {
		whitelist[_address] = _whitelist;
		emit UpdateWhitelist(_address, _whitelist);
	}

	/// PAUSABLE
	function pause() public onlyOwner {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}

	/////////////////////////
	/// State methods
	/////////////////////////

	/// @notice convert xGrail in the contract to sectGrail
	/// @dev we include allocated xGrail and check against totalSupply of sectGrail
	/// any extra amount can be minted to the user
	function _mintFromBalance(address to) internal returns (uint256) {
		(uint256 allocated, ) = xGrailToken.getXGrailBalance(address(this));

		// dont include redeems - redeems should be burned
		uint256 amount = xGrailToken.balanceOf(address(this)) + allocated - totalSupply();
		_mint(to, amount);
		return amount;
	}

	/// @notice deposit lp tokens into a Camelot farm
	function depositIntoFarm(
		INFTPool _farm,
		uint256 positionId,
		uint256 amount
	) external nonReentrant whenNotPaused onlyWhitelisted(address(_farm)) returns (uint256) {
		(address lp, , , , , , , ) = _farm.getPoolInfo();
		IERC20(lp).safeTransferFrom(msg.sender, address(this), amount);

		if (IERC20(lp).allowance(address(this), address(_farm)) < amount)
			IERC20(lp).safeIncreaseAllowance(address(_farm), type(uint256).max);

		// positionId = 0 means that position does not exist yet
		if (positionId == 0) {
			positionId = _farm.lastTokenId() + 1;
			_farm.createPosition(amount, 0);
			positionOwners[address(_farm)][positionId] = msg.sender;
		} else {
			if (positionOwners[address(_farm)][positionId] != msg.sender) revert NotPositionOwner();
			_farm.addToPosition(positionId, amount);
		}

		emit DepositIntoFarm(msg.sender, address(_farm), positionId, amount);
		return positionId;
	}

	/// @notice withdraw lp tokens from a Camelot farm
	function withdrawFromFarm(
		INFTPool _farm,
		uint256 positionId,
		uint256 amount
	)
		external
		nonReentrant
		whenNotPaused
		onlyPositionOwner(address(_farm), positionId)
		onlyWhitelisted(address(_farm))
		returns (uint256)
	{
		address usageAddress = _farm.yieldBooster();
		uint256 xGrailAllocation = xGrailToken.usageAllocations(address(this), usageAddress);
		_farm.withdrawFromPosition(positionId, amount);

		// when full balance is removed from position, the position gets deleted
		// xGrail get deallocated from a deleted position
		// if the position has been delted, reset the positionId to 0
		if (!_farm.exists(positionId)) {
			// when position gets removed we need to reset the allocation amount
			uint256 allocationChange = xGrailAllocation -
				xGrailToken.usageAllocations(address(this), usageAddress);

			allocations[msg.sender] -= allocationChange;
			// subtract deallocation fee amount
			// this is a fee that is charged when xGrail gets deallocated,
			// the deallocation fee gets subtracted from the user’s xGrail balance
			// (in this case for secGrail) since we want to maintain a 1-1 mapping
			// we also have to burn the equivalent amount of sectGrail from the
			// user responsible for the deallocation
			uint256 deallocationFeeAmount = (allocationChange *
				xGrailToken.usagesDeallocationFee(usageAddress)) / 10000;
			// burn the deallocation fee worth of sectGrail from user
			_burn(msg.sender, deallocationFeeAmount);
			positionOwners[address(_farm)][positionId] = address(0);
			positionId = 0;
		}

		(address lp, , , , , , , ) = _farm.getPoolInfo();
		IERC20(lp).safeTransfer(msg.sender, amount);
		uint256 grailBalance = grailToken.balanceOf(address(this));
		if (grailBalance > 0) grailToken.safeTransfer(msg.sender, grailBalance);
		_mintFromBalance(msg.sender);

		emit WithdrawFromFarm(msg.sender, address(_farm), positionId, amount);
		return positionId;
	}

	/// @notice harvest camelot farm and allocate xGrail to the position
	function harvestFarm(INFTPool _farm, uint256 positionId)
		external
		nonReentrant
		whenNotPaused
		onlyPositionOwner(address(_farm), positionId)
		onlyWhitelisted(address(_farm))
		returns (uint256[] memory harvested)
	{
		_farm.harvestPosition(positionId);
		harvested = new uint256[](1);
		harvested[0] = grailToken.balanceOf(address(this));
		if (harvested[0] > 0) grailToken.safeTransfer(msg.sender, harvested[0]);

		// allocate all xGrail to the farm
		bytes memory usageData = abi.encode(_farm, positionId);
		_mintFromBalance(msg.sender);
		// if farm is whitelisted, we don't need to check if yield booster is whitelisted
		_allocate(_farm.yieldBooster(), type(uint256).max, usageData);
		emit HarvestFarm(msg.sender, address(_farm), positionId, harvested);
	}

	/// @notice get lp tokens staked in a Camelot farm
	/// @param _farm address of the Camelot farm
	/// @param positionId id of the position
	/// @return amount of lp tokens staked in the farm
	function getFarmLp(INFTPool _farm, uint256 positionId) public view returns (uint256) {
		if (positionId == 0) return 0;
		(uint256 lp, , , , , , , ) = _farm.getStakingPosition(positionId);
		return lp;
	}

	/// @notice allocate xGrail to a farm position
	/// @param _farm address of the farm contract
	/// @param amount amount of xGrail to allocate
	/// @param positionId id of the position
	function allocateToPosition(
		INFTPool _farm,
		uint256 positionId,
		uint256 amount
	)
		public
		nonReentrant
		whenNotPaused
		onlyWhitelisted(address(_farm))
		onlyPositionOwner(address(_farm), positionId)
	{
		bytes memory usageData = abi.encode(_farm, positionId);
		address usageAddress = _farm.yieldBooster();
		_allocate(usageAddress, amount, usageData);
	}

	/// @notice internal allocate method
	/// @dev usageAddress address needs to be validated
	/// @param usageAddress address of the usage contract
	/// @param amount amount of xGrail to allocate
	/// @param usageData data to pass to the usage contract
	function _allocate(
		address usageAddress,
		uint256 amount,
		bytes memory usageData
	) internal {
		uint256 allocated = allocations[msg.sender];
		uint256 available = balanceOf(msg.sender) - allocated;
		amount = amount > available ? available : amount;
		if (amount == 0) revert InsufficientBalance();

		if (xGrailToken.getUsageApproval(address(this), usageAddress) < amount)
			xGrailToken.approveUsage(usageAddress, type(uint256).max);

		allocations[msg.sender] = allocated + amount;
		xGrailToken.allocate(usageAddress, amount, usageData);
		emit Allocate(msg.sender, usageAddress, amount, usageData);
	}

	/// @notice deallocate xGrail from a usage contract
	function deallocateFromPosition(
		INFTPool _farm,
		uint256 positionId,
		uint256 amount
	)
		public
		nonReentrant
		whenNotPaused
		onlyWhitelisted(address(_farm))
		onlyPositionOwner(address(_farm), positionId)
	{
		bytes memory usageData = abi.encode(_farm, positionId);
		address usageAddress = _farm.yieldBooster();
		allocations[msg.sender] = allocations[msg.sender] - amount;
		xGrailToken.deallocate(usageAddress, amount, usageData);

		// burn deallocation fee sectGrail
		// this is a fee that is charged when xGrail gets deallocated,
		// the deallocation fee gets subtracted from the user’s xGrail balance
		// (in this case for secGrail) since we want to maintain a 1-1 mapping
		// we also have to burn the equivalent amount of sectGrail from the
		// user responsible for the deallocation
		uint256 deallocationFeeAmount = (amount * xGrailToken.usagesDeallocationFee(usageAddress)) /
			10000;
		_burn(msg.sender, deallocationFeeAmount);
		emit Deallocate(msg.sender, usageAddress, amount, usageData);
	}

	/// @dev ensure that only non-allocated sectGrail can be transferred
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 amount
	) internal override {
		super._beforeTokenTransfer(from, to, amount);
		if (from == address(0)) return;
		uint256 currentAllocation = allocations[msg.sender];
		uint256 unAllocated = balanceOf(msg.sender) - currentAllocation;
		if (amount > unAllocated) revert CannotTransferAllocatedTokens();
	}

	/// VEIW FUNCTIONS

	/// @notice get the total amount of xGrail allocated by a user
	function getAllocations(address user) external view returns (uint256) {
		return allocations[user];
	}

	/// @notice get the total amount of xGrail that can be allocated by a user
	function getNonAllocatedBalance(address user) external view returns (uint256) {
		return balanceOf(user) - allocations[user];
	}

	/// NFT HANDLER OVERRIDES

	function onNFTHarvest(
		address send,
		address to,
		uint256 tokenId,
		uint256 grailAmount,
		uint256 xGrailAmount
	) external returns (bool) {
		return true;
	}

	function onNFTAddToPosition(
		address operator,
		uint256 tokenId,
		uint256 lpAmount
	) external returns (bool) {
		return true;
	}

	function onNFTWithdraw(
		address operator,
		uint256 tokenId,
		uint256 lpAmount
	) external returns (bool) {
		return true;
	}

	/**
	 * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
	 * by `operator` from `from`, this function is called.
	 *
	 * It must return its Solidity selector to confirm the token transfer.
	 * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
	 *
	 * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
	 */
	function onERC721Received(
		address operator,
		address from,
		uint256 tokenId,
		bytes calldata data
	) external returns (bytes4) {
		return this.onERC721Received.selector;
	}

	error CannotTransferAllocatedTokens();
	error InsufficientBalance();
	error NotPositionOwner();
	error NotWhitelisted();
}

