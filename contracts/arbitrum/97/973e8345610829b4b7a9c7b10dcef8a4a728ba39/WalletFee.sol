// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./WalletExec.sol";

import "./IFunWallet.sol";
import "./IWalletFee.sol";
import "./IFeePercentOracle.sol";

abstract contract WalletFee is WalletExec, IWalletFee {
	uint256[50] private __gap;

	function _transferEth(address payable recipient, uint256 amount) internal {
		if (address(this).balance < amount) {
			_transferEthFromEntrypoint(recipient, amount);
		} else {
			(bool success, ) = payable(recipient).call{value: amount}("");
			require(success, "FW508");
		}
	}

	function _handleFee(UserOperationFee memory feedata) internal {
		address payable funOracle = _getOracle();
		(uint256 funCut, uint256 developerCut) = IFeePercentOracle(funOracle).getFee(feedata.amount);
		if (feedata.token == address(0)) {
			_transferEth(feedata.recipient, developerCut);
			_transferEth(funOracle, funCut);
		} else {
			if (developerCut != 0) {
				try IFunWallet(address(this)).transferErc20(feedata.token, feedata.recipient, developerCut) {} catch {
					revert("FW510");
				}
			}
			if (funCut != 0) {
				try IFunWallet(address(this)).transferErc20(feedata.token, funOracle, funCut) {} catch {
					revert("FW509");
				}
			}
		}
	}

	/**
	 * @notice this method is used to execute the downstream module
	 * @dev only entrypoint or owner is allowed to invoke this method.
	 * @param dest the address of the module to be called
	 * @param value the amount of ether to forward
	 * @param data the call data to the downstream module
	 * @param feedata UserOperationFee struct containing fee data
	 */

	function execFromEntryPointWithFee(address dest, uint256 value, bytes calldata data, UserOperationFee memory feedata) public override {
		execFromEntryPoint(dest, value, data);
		_handleFee(feedata);
	}

	function execFromEntryPoint(address dest, uint256 value, bytes calldata data) public override(IWalletFee, WalletExec) {
		super.execFromEntryPoint(dest, value, data);
	}

	function _getOracle() internal view virtual returns (address payable);

	function _transferEthFromEntrypoint(address payable recipient, uint256 amount) internal virtual;
}

