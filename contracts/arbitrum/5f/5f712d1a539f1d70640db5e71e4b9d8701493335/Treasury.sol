// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Address.sol";

import "./IRouter.sol";
import "./IRewards.sol";

// This contract should be relatively upgradeable = no important state

contract Treasury {

	using SafeERC20 for IERC20; 
    using Address for address payable;

	// Contract dependencies
	address public owner;
	address public router;
	address public trading;
	address public oracle;
	address public bridge;

	uint256 public constant UNIT = 10**18;

	constructor() {
		owner = msg.sender;
	}

	// Governance methods

	function setOwner(address newOwner) external onlyOwner {
		owner = newOwner;
	}

	function setRouter(address _router) external onlyOwner {
		router = _router;
		oracle = IRouter(router).oracle();
		trading = IRouter(router).trading();
	}

	function setBridge(address _bridge) external onlyOwner {
		bridge = _bridge;
	}

	// Methods

	function notifyFeeReceived(
		address currency, 
		uint256 amount
	) external onlyTrading {

		// Contracts from Router
		address poolRewards = IRouter(router).getPoolRewards(currency);
		address safxRewards = IRouter(router).getSafxRewards(currency);

		// Send poolShare to pool-currency rewards contract
		uint256 poolReward = IRouter(router).getPoolShare(currency) * amount / 10**4;
		_transferOut(currency, poolRewards, poolReward);
		IRewards(poolRewards).notifyRewardReceived(poolReward);

		// Send safxPoolShare to safx-currency rewards contract
		uint256 safxReward = IRouter(router).getSafxShare(currency) * amount / 10**4;
		_transferOut(currency, safxRewards, safxReward);
		IRewards(safxRewards).notifyRewardReceived(safxReward);

	}


	//tx.origin for this is the dark oracle
	function fundOracle(
		address destination, //destination is the dark oracle
		uint256 amount
	) external onlyOracle {
		uint256 ethBalance = address(this).balance;
		if (amount > ethBalance) return;
		//if enough eth, send to the darkoracle
		payable(destination).sendValue(amount);
	}


	//assuming this is just a withdraw for the owner
	function sendFunds(
		address token, 
		address destination, 
		uint256 amount
	) external onlyOwner {
		_transferOut(token, destination, amount);
	}

	// To receive ETH
	fallback() external payable {}
	receive() external payable {}

	// Utils

	function _transferOut(address currency, address to, uint256 amount) internal {
		if (amount == 0 || to == address(0)) return;
		// adjust decimals
		uint256 decimals = IRouter(router).getDecimals(currency);
		amount = amount * (10**decimals) / UNIT;
		if (currency == address(0)) {
			payable(to).sendValue(amount);
		} else {
			IERC20(currency).safeTransfer(to, amount);
		}
	}

	// Modifiers

	modifier onlyOwner() {
		require(msg.sender == owner, "!owner");
		_;
	}

	modifier onlyTrading() {
		require(msg.sender == trading, "!trading");
		_;
	}

	modifier onlyOracle() {
		require(msg.sender == oracle, "!oracle");
		_;
	}

}
