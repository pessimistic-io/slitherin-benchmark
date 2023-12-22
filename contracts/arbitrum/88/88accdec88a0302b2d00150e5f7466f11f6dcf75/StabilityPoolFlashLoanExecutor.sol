// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./IFlashLoanExecutor.sol";
import "./IVestaDexTrader.sol";
import "./IStabilityPool.sol";
import "./ITroveManager.sol";
import "./IWETH9.sol";
import "./IGlpRewardRouter.sol";
import { ManualExchange } from "./TradingModel.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";

error NoAssetGain();
error UnprofitableTransaction(uint256 _finalVSTBalance);

contract StabilityPoolFlashLoanExecutor is
	IFlashLoanExecutor,
	TokenTransferrer,
	Ownable
{
	address public immutable ethStabilityPoolAddress;
	address public immutable wethAddress;
	address public immutable glpStabilityPoolAddress;
	address public immutable feeStakedGLP;
	address public immutable VST;
	IGlpRewardRouter public immutable glpRewardRouterAddress;
	IVestaDexTrader public immutable dexTrader;
	ITroveManager public immutable troveManager;

	event debug(uint256 amount);

	constructor(
		address _VST,
		address _flashloanContract,
		address _dexTrader,
		address _troveManager,
		address _ethStabilityPool,
		address _weth,
		address _glpStabilityPool,
		address _glpRewardRouter,
		address _feeStakedGlp
	) {
		VST = _VST;
		dexTrader = IVestaDexTrader(_dexTrader);
		troveManager = ITroveManager(_troveManager);
		glpRewardRouterAddress = IGlpRewardRouter(_glpRewardRouter);
		ethStabilityPoolAddress = _ethStabilityPool;
		wethAddress = _weth;
		glpStabilityPoolAddress = _glpStabilityPool;
		feeStakedGLP = _feeStakedGlp;
		_tryPerformMaxApprove(address(VST), _flashloanContract);
	}

	function executeOperation(
		uint256 _amount,
		uint256 _fee,
		address _initiator,
		bytes calldata _extraParams
	) external {
		(
			address tokenAddress,
			address stabilityPoolAddress,
			ManualExchange[] memory routes
		) = abi.decode(_extraParams, (address, address, ManualExchange[]));

		_performApprove(VST, address(stabilityPoolAddress), _amount);
		IStabilityPool(stabilityPoolAddress).provideToSP(_amount);
		troveManager.liquidateTroves(tokenAddress, type(uint256).max);
		IStabilityPool(stabilityPoolAddress).withdrawFromSP(type(uint256).max);

		uint256 assetGain;
		if (stabilityPoolAddress == ethStabilityPoolAddress) {
			assetGain = address(this).balance;
			IWETH9(wethAddress).deposit{ value: assetGain }();
			tokenAddress = wethAddress;
		} else if (stabilityPoolAddress == glpStabilityPoolAddress) {
			uint256 glpAmount = _balanceOf(feeStakedGLP, address(this));
			IGlpRewardRouter(glpRewardRouterAddress).unstakeAndRedeemGlp(
				wethAddress,
				glpAmount,
				0,
				address(this)
			);
			assetGain = _balanceOf(wethAddress, address(this));
			tokenAddress = wethAddress;
		} else {
			assetGain = _balanceOf(tokenAddress, address(this));
		}

		if (assetGain > 0) {
			_performApprove(tokenAddress, address(dexTrader), assetGain);
			dexTrader.exchange(address(this), tokenAddress, assetGain, routes);
		} else {
			revert NoAssetGain();
		}

		uint256 finalVSTBalance = _balanceOf(VST, address(this));

		if (finalVSTBalance < _amount + _fee) {
			revert UnprofitableTransaction(finalVSTBalance);
		}
	}

	function sendERC20(
		address _tokenAddress,
		uint256 _tokenAmount
	) external onlyOwner {
		_performTokenTransfer(_tokenAddress, msg.sender, _tokenAmount, false);
	}

	receive() external payable {}
}


