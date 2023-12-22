// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;
import "./SafeMath.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

import "./IDefaultPool.sol";
import "./CheckContract.sol";
import "./SafetyTransfer.sol";
import "./Initializable.sol";

/*
 * The Default Pool holds the ETH and SLSD debt (but not SLSD tokens) from liquidations that have been redistributed
 * to active troves but not yet "applied", i.e. not yet recorded on a recipient active trove's struct.
 *
 * When a trove makes an operation that applies its pending ETH and SLSD debt, its pending ETH and SLSD debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable, CheckContract, Initializable, IDefaultPool {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	string public constant NAME = "DefaultPool";

	address constant ETH_REF_ADDRESS = address(0);

	address public troveManagerAddress;
	address public troveManagerHelpersAddress;
	address public activePoolAddress;

	bool public isInitialized;

	mapping(address => uint256) internal assetsBalance;
	mapping(address => uint256) internal SLSDDebts; // debt

	// --- Dependency setters ---

	function setAddresses(
		address _troveManagerAddress, 
		address _troveManagerHelpersAddress, 
		address _activePoolAddress
	  ) external
		initializer
		onlyOwner
	{
		require(!isInitialized, "Already initialized");
		checkContract(_troveManagerAddress);
		checkContract(_activePoolAddress);
		checkContract(_troveManagerHelpersAddress);
		isInitialized = true;

		troveManagerAddress = _troveManagerAddress;
		troveManagerHelpersAddress = _troveManagerHelpersAddress;
		activePoolAddress = _activePoolAddress;

		emit TroveManagerAddressChanged(_troveManagerAddress);
		emit ActivePoolAddressChanged(_activePoolAddress);

		renounceOwnership();
	}

	// --- Getters for public variables. Required by IPool interface ---

	/*
	 * Returns the ETH state variable.
	 *
	 * Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
	 */
	function getAssetBalance(address _asset) external view override returns (uint256) {
		return assetsBalance[_asset];
	}

	function getSLSDDebt(address _asset) external view override returns (uint256) {
		return SLSDDebts[_asset];
	}

	// --- Pool functionality ---

	function sendAssetToActivePool(address _asset, uint256 _amount)
		external
		override
		callerIsTroveManager
	{
		address activePool = activePoolAddress; // cache to save an SLOAD

		uint256 safetyTransferAmount = SafetyTransfer.decimalsCorrection(_asset, _amount);
		if (safetyTransferAmount == 0) return;

		assetsBalance[_asset] = assetsBalance[_asset].sub(_amount);

		if (_asset != ETH_REF_ADDRESS) {
			IERC20(_asset).safeTransfer(activePool, safetyTransferAmount);
			IDeposit(activePool).receivedERC20(_asset, _amount);
		} else {
			(bool success, ) = activePool.call{ value: _amount }("");
			require(success, "DefaultPool: sending ETH failed");
		}

		emit DefaultPoolAssetBalanceUpdated(_asset, assetsBalance[_asset]);
		emit AssetSent(activePool, _asset, safetyTransferAmount);
	}

	function increaseSLSDDebt(address _asset, uint256 _amount)
		external
		override
		callerIsTroveManager
	{
		SLSDDebts[_asset] = SLSDDebts[_asset].add(_amount);
		emit DefaultPoolSLSDDebtUpdated(_asset, SLSDDebts[_asset]);
	}

	function decreaseSLSDDebt(address _asset, uint256 _amount)
		external
		override
		callerIsTroveManager
	{
		SLSDDebts[_asset] = SLSDDebts[_asset].sub(_amount);
		emit DefaultPoolSLSDDebtUpdated(_asset, SLSDDebts[_asset]);
	}

	// --- 'require' functions ---

	modifier callerIsActivePool() {
		require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
		_;
	}

	modifier callerIsTroveManager() {
		require(
			msg.sender == troveManagerAddress ||
			msg.sender == troveManagerHelpersAddress, 
			"DefaultPool: Caller is not the TroveManager");
		_;
	}

	function receivedERC20(address _asset, uint256 _amount)
		external
		override
		callerIsActivePool
	{
		require(_asset != ETH_REF_ADDRESS, "ETH Cannot use this functions");

		assetsBalance[_asset] = assetsBalance[_asset].add(_amount);
		emit DefaultPoolAssetBalanceUpdated(_asset, assetsBalance[_asset]);
	}

	// --- Fallback function ---

	receive() external payable callerIsActivePool {
		assetsBalance[ETH_REF_ADDRESS] = assetsBalance[ETH_REF_ADDRESS].add(msg.value);
		emit DefaultPoolAssetBalanceUpdated(ETH_REF_ADDRESS, assetsBalance[ETH_REF_ADDRESS]);
	}
}

