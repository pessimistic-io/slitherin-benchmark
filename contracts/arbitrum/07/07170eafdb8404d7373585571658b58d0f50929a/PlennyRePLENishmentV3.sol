// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyFeeStorage.sol";
import "./IPlennyERC20.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";

/// @title  Plenny rePLENishment version 3
/// @notice This contract collects all the fees from the Dapp, mints new tokens for inflation, manages the rePLENishment
///			of the treasury, and performs automatic buybacks over the DEX.
contract PlennyRePLENishmentV3 is PlennyBasePausableV2, PlennyFeeStorage {

	using SafeMathUpgradeable for uint256;
	using AddressUpgradeable for address payable;
	using SafeERC20Upgradeable for IPlennyERC20;

	/// An event emitted when logging function calls.
	event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;
	/// An event emitted when liquidity is provided over the DEX.
	event LiquidityProvided(uint256 indexed jobId, uint256 plennyAdded, uint256 ethAdded, uint256 liquidity, uint256 blockNumber);
	/// An event emitted when PL2 are sold for ETH over the DEX.
	event SoldPlennyForEth(uint256 indexed jobId, uint256 plennySold, uint256 ethBought, uint256 blockNumber);
	/// An event emitted when liquidity is removed from the DEX.
	event LiquidityRemoved(uint256 indexed jobId, uint256 plennyReceived, uint256 ethReceived, uint256 liquidityAmount, uint256 blockNumber);
	/// An event that is emitted when ETH is sold for Pl2 over the DEX.
	event SoldEthForPlenny(uint256 indexed jobId, uint256 ethSold, uint256 plennyBought, uint256 blockNumber);
	/// An event that is emitted when the buyback and lp providing mechanism is completed.
	event BuybackAndLpProvided(uint256 indexed jobId, uint256 plennySpent, uint256 ethSpent, uint256 liquidityProvided, uint256 blockNumber);
	/// An event emitted when the remove lp and buyback mechanism is completed.
	event RemoveLpAndBuyBackPlenny(uint256 indexed jobId, uint256 lpBurned, uint256 plennyReceived, uint256 blockNumber);

	/// @notice Receives payment
	receive() external payable {
		emit LogCall(msg.sig, msg.sender, msg.data);
	}

	/// @notice Runs the re-distribution of the fees by sending all the fees directly to the Treasury HODL.
	function plennyReplenishment() external nonReentrant {
		require(_blockNumber().sub(lastMaintenanceBlock) > maintenanceBlockLimit, "ERR_DAILY_LIMIT");

		IUniswapV2Pair lpContract = contractRegistry.lpContract();
		IPlennyERC20 plennyToken = contractRegistry.plennyTokenContract();

		uint256 lpBalance = lpContract.balanceOf(address(this));
		uint256 plennyBalance = plennyToken.balanceOf(address(this));

		jobIdCount++;
		jobs[jobIdCount] = _blockNumber();
		lastMaintenanceBlock = jobs[jobIdCount];

		uint256 userReward;
		address treasuryAddress = contractRegistry.requireAndGetAddress("PlennyTreasury");

		if (lpBalance > lpThresholdForBurning) {
			(, uint256 plennyBought) = removeLpAndBuyBack(jobIdCount);
			userReward = plennyBought.mul(replenishRewardPercentage).div(100).div(100);
			lpBalance = lpContract.balanceOf(address(this));

			plennyToken.safeTransfer(msg.sender, userReward);
			plennyToken.safeTransfer(treasuryAddress, plennyBought.sub(userReward));
			require(lpContract.transfer(treasuryAddress, lpBalance), "failed");
		}

		if (plennyBalance > plennyThresholdForBuyback) {
			buyBackAndLP(jobIdCount);
			uint256 newPlennyBalance = plennyToken.balanceOf(address(this));
			lpBalance = lpContract.balanceOf(address(this));
			userReward = newPlennyBalance.mul(replenishRewardPercentage).div(100).div(100);

			plennyToken.safeTransfer(msg.sender, userReward);
			plennyToken.safeTransfer(treasuryAddress, newPlennyBalance.sub(userReward));
			require(lpContract.transfer(treasuryAddress, lpBalance), "failed");
		}

		uint256 mintedPlenny = mintDailyInflation(jobIdCount);
		userReward = mintedPlenny.mul(dailyInflationRewardPercentage).div(100).div(100);
		plennyToken.safeTransfer(msg.sender, userReward);
		plennyToken.safeTransfer(treasuryAddress, mintedPlenny.sub(userReward));
	}

	/// @notice Changes the buyback percentage PL2. Called by the owner.
	/// @param 	percentage percentage for buyback of PL2
	function setBuyBackPercentagePl2(uint256 percentage) external onlyOwner {
		require(percentage <= 10000, "ERR_OVER_100");
		buyBackPercentagePl2 = percentage;
	}

	/// @notice Changes the lp Burning Percentage. Called by the owner.
	/// @param 	percentage percentage for burning the collected LP fees
	function setLpBurningPercentage(uint256 percentage) external onlyOwner {
		require(percentage <= 10000, "ERR_OVER_100");
		lpBurningPercentage = percentage;
	}

	/// @notice Changes the rePLENishment Reward Percentage. Called by the owner.
	/// @param 	percentage percentage for replenishment of the fees collected
	function setReplenishRewardPercentage(uint256 percentage) external onlyOwner {
		require(percentage <= 10000, "ERR_OVER_100");
		replenishRewardPercentage = percentage;
	}

	/// @notice Changes the daily inflation reward in percentage. Called by the owner.
	/// @param 	percentage percentage for the daily inflation
	function setDailyInflationRewardPercentage(uint256 percentage) external onlyOwner {
		require(percentage <= 10000, "ERR_OVER_100");
		dailyInflationRewardPercentage = percentage;
	}

	/// @notice Changes the lp threshold for burning. Called by the owner.
	/// @param 	amount threshold amount of LP tokens for burning
	function setLpThresholdForBurning(uint256 amount) external onlyOwner {
		lpThresholdForBurning = amount;
	}

	/// @notice Changes the plenny Threshold for buyback. Called by the owner.
	/// @param 	amount threshold amount of PL2 tokens for buyback
	function setPlennyThresholdForBuyback(uint256 amount) external onlyOwner {
		plennyThresholdForBuyback = amount;
	}

	/// @notice Changes the rePLENishment Block Limit. Called by the owner.
	/// @param 	blocks blocks between 2 consecutive rePLENishment jobs
	function setMaintenanceBlockLimit(uint256 blocks) external onlyOwner {
		maintenanceBlockLimit = blocks;
	}

	/// @notice Changes the inflation amount per block. Called by the owner.
	/// @param 	amount inflation amount of PL2 tokens per block
	function setInflationAmountPerBlock(uint256 amount) external onlyOwner {
		inflationAmountPerBlock = amount;
	}

	/// @notice Mint the daily inflation supply of PL2.
	/// @param 	jobId maintenance job Id
	/// @return	mintedPlenny tokens minted as a result of the daily inflation
	function mintDailyInflation(uint jobId) private returns (uint256 mintedPlenny) {
		uint256 currBlock = jobs[jobId];
		uint256 lastBlock = jobId > 0 ? jobs[jobId - 1] : jobs[0];
		uint256 mintingAmount = currBlock.sub(lastBlock).mul(inflationAmountPerBlock);

		contractRegistry.plennyTokenContract().mint(address(this), mintingAmount);
		return mintingAmount;
	}

	/// @notice Approve spending of token.
	/// @param 	addr token owner address
	/// @param 	token token address itself
	/// @param 	amount amount to approve
	function approve(address addr, address token, uint256 amount) private {
		IPlennyERC20(token).safeApprove(addr, amount);
	}

	/// @notice Provide allowance to address.
	/// @param 	amount allowance amount
	/// @param 	token token address itself
	/// @param 	to address to
	function checkAndProvideAllowance(uint256 amount, address token, address to) private {
		uint256 allowance = IPlennyERC20(token).allowance(address(this), to);
		if (allowance > 0) {
			if (allowance < amount) {
				IPlennyERC20(token).safeIncreaseAllowance(to, amount.sub(allowance));
			}
		} else {
			approve((to), token, amount);
		}
	}

	/// @notice buyback the PL2 for ETH on DEX and provide back LP for ETH-PL2 pair on the DEX.
	/// @param 	jobId maintenance job Id
	/// @return liquidityTokensMinted LP tokens minted as a result of LP on DEX
	/// @return plennyTotalSpent total PL2 spent from fees
	/// @return ethSpent total ETH spent
	function buyBackAndLP(uint256 jobId) private returns (uint256 liquidityTokensMinted, uint256 plennyTotalSpent, uint256 ethSpent) {
		uint256 feePlennyBalance = contractRegistry.plennyTokenContract().balanceOf(address(this));
		uint256 plennyBuyBackAmount = feePlennyBalance.mul(buyBackPercentagePl2).div(100).div(100);
		(uint256 plennySold,) = sellPlennyForEth(jobId, plennyBuyBackAmount.div(2));
		(uint256 plennyProvided, uint256 ethProvided, uint256 liquidityReceived) = provideLiquidity(jobId, plennyBuyBackAmount.sub(plennySold), address(this).balance);

		emit BuybackAndLpProvided(jobId, plennySold.add(plennyProvided), ethProvided, liquidityReceived, _blockNumber());
		return (liquidityReceived, plennySold.add(plennyProvided), ethProvided);
	}

	/// @notice Remove LP from DEX and buyback PL2 with ETH.
	/// @param 	jobId maintenance job Id
	/// @return liquidityBurned total LP tokens removed
	/// @return plennyBought total PL2 bought from removing the liquidity
	function removeLpAndBuyBack(uint256 jobId) private returns (uint256 liquidityBurned, uint256 plennyBought) {
		uint256 feeLpBalance = contractRegistry.lpContract().balanceOf(address(this));
		uint256 lpBurnAmount = feeLpBalance.mul(lpBurningPercentage).div(100).div(100);
		(uint256 plennyRecievedFromLp,) = removeLiquidity(jobId, lpBurnAmount);
		(, uint256 plennyReceivedFromSwap) = sellEthForPlenny(jobId, address(this).balance);

		emit RemoveLpAndBuyBackPlenny(jobId, lpBurnAmount, plennyRecievedFromLp.add(plennyReceivedFromSwap), _blockNumber());
		return (lpBurnAmount, plennyRecievedFromLp.add(plennyReceivedFromSwap));
	}

	/// @notice Provide the ETH-Pl2 liquidity on DEX
	/// @param 	jobId maintenance job Id
	/// @param 	plennyAmount amount of PL2
	/// @param 	ethAmount amount of ETH
	/// @return plennyProvided actual PL2 provided as liquidity
	/// @return ethProvided actual ETH provided as liquidity
	/// @return liquidity LP tokens
	function provideLiquidity(uint256 jobId, uint256 plennyAmount, uint256 ethAmount)
	private returns (uint256 plennyProvided, uint256 ethProvided, uint256 liquidity) {
		uint256 ethAddAmount = getOptimalAmount(plennyAmount, ethAmount);

		uint256 minPlennyAmount = plennyAmount.sub(plennyAmount.mul(ADD_LIQUIDITY_MARGIN).div(100).div(100));
		uint256 minEthAmount = ethAddAmount.sub(ethAddAmount.mul(ADD_LIQUIDITY_MARGIN).div(100).div(100));

		checkAndProvideAllowance(plennyAmount, contractRegistry.requireAndGetAddress("PlennyERC20"), address(contractRegistry.uniswapRouterV2()));
		(uint256 amountPlenny, uint256 amountETH, uint256 liq) = contractRegistry.uniswapRouterV2().addLiquidityETH{ value: ethAddAmount }(
			contractRegistry.requireAndGetAddress("PlennyERC20"),
			plennyAmount, minPlennyAmount,
			minEthAmount, address(this),
			block.timestamp.add(3600));

		emit LiquidityProvided(jobId, amountPlenny, amountETH, liq, _blockNumber());
		return (amountPlenny, amountETH, liq);
	}

	/// @notice Remove the ETH-Pl2 liquidity from DEX.
	/// @param 	jobId maintenance job Id
	/// @param 	liquidityAmount amount of LP tokens to remove on DEX
	/// @return plennyRecieved actual PL2 received from DEX
	/// @return ethReceived actual ETH received from DEX
	function removeLiquidity(uint256 jobId, uint256 liquidityAmount) private returns (uint256 plennyRecieved, uint256 ethReceived) {

		uint256 liquidityTotalSupply = contractRegistry.lpContract().totalSupply();
		(uint256 pl2Supply, uint256 ethSupply) = getReserves(contractRegistry.lpContract());

		uint256 minPlenny = (pl2Supply.mul(liquidityAmount).div(liquidityTotalSupply));
		minPlenny = minPlenny.sub(pl2Supply.mul(liquidityAmount).mul(ADD_LIQUIDITY_MARGIN).div(liquidityTotalSupply).div(10000));
		uint256 minEth = ethSupply.mul(liquidityAmount).div(liquidityTotalSupply);
		minEth = minEth.sub(ethSupply.mul(liquidityAmount).mul(ADD_LIQUIDITY_MARGIN).div(liquidityTotalSupply).div(10000));

		require(contractRegistry.lpContract().approve(address(contractRegistry.uniswapRouterV2()), liquidityAmount), "failed");
		(uint256 amountPlenny, uint256 amountETH) = contractRegistry.uniswapRouterV2().removeLiquidityETH(
			contractRegistry.requireAndGetAddress("PlennyERC20"),
			liquidityAmount,
			minPlenny,
			minEth,
			address(this),
			block.timestamp.add(3600));

		emit LiquidityRemoved(jobId, amountPlenny, amountETH, liquidityAmount, _blockNumber());
		return (amountPlenny, amountETH);
	}

	/// @notice Sell PL2 for ETH on DEX.
	/// @param 	jobId maintenance job Id
	/// @param 	amount amount of PL2 to sell
	/// @return plennySold actual PL2 sold on DEX
	/// @return ethReceived actual ETH bought from DEX
	function sellPlennyForEth(uint256 jobId, uint256 amount) private returns (uint256 plennySold, uint256 ethReceived) {
		uint256 swappingAmount;
		uint256 amountOutMin;

		IUniswapV2Router02 uniswapRouter = contractRegistry.uniswapRouterV2();
		IUniswapV2Pair lpContract = contractRegistry.lpContract();
		address plennyAddress = contractRegistry.requireAndGetAddress("PlennyERC20");

		address[] memory path = new address[](2);
		path[0] = plennyAddress;
		path[1] = uniswapRouter.WETH();

		(uint256 pl2Supply, uint256 ethSupply) = getReserves(lpContract);

		uint256 ethQuoteOut = uniswapRouter.quote(amount, pl2Supply, ethSupply);
		//slippage percent
		if (ethQuoteOut > ethSupply.mul(SLIPPAGE_PERCENT).div(100).div(100)) {
			swappingAmount = pl2Supply.mul(SLIPPAGE_PERCENT).div(100).div(100);
		} else {
			swappingAmount = amount;
		}
		amountOutMin = ethQuoteOut.sub(ethQuoteOut.mul(ETH_OUT_AMOUNT_MARGIN).div(100).div(100));

		checkAndProvideAllowance(swappingAmount, plennyAddress, address(uniswapRouter));
		uint[] memory amountsOut = uniswapRouter.swapExactTokensForETH(
			swappingAmount,
			amountOutMin,
			path,
			address(this),
			block.timestamp.add(3600));

		emit SoldPlennyForEth(jobId, amountsOut[0], amountsOut[1], _blockNumber());
		return (amountsOut[0], amountsOut[1]);
	}

	/// @notice Sell ETH for PL2 on DEX
	/// @param 	jobId maintenance job Id
	/// @param 	ethAmount amount of ETH to sell
	/// @return ethSold actual ETH sold on DEX
	/// @return plennyReceived actual PL2 bought from DEX
	function sellEthForPlenny(uint256 jobId, uint256 ethAmount) private returns (uint256 ethSold, uint256 plennyReceived) {
		uint256 swappingAmount;

		IUniswapV2Router02 uniswapRouter = contractRegistry.uniswapRouterV2();
		IUniswapV2Pair lpContract = contractRegistry.lpContract();
		address plennyAddress = contractRegistry.requireAndGetAddress("PlennyERC20");

		address[] memory path = new address[](2);
		path[0] = uniswapRouter.WETH();
		path[1] = plennyAddress;

		(uint256 pl2Supply, uint256 ethSupply) = getReserves(lpContract);

		uint256 plennyQuoteOut = uniswapRouter.quote(ethAmount, pl2Supply, ethSupply);

		if (plennyQuoteOut > pl2Supply.mul(SLIPPAGE_PERCENT).div(100).div(100)) {
			swappingAmount = ethSupply.mul(SLIPPAGE_PERCENT).div(100).div(100);
			plennyQuoteOut = uniswapRouter.quote(swappingAmount, pl2Supply, ethSupply);
		} else {
			swappingAmount = ethAmount;
		}

		uint[] memory amounts = uniswapRouter.getAmountsOut(swappingAmount, path);
		if (amounts[amounts.length.sub(1)] < plennyQuoteOut) {
			plennyQuoteOut = amounts[amounts.length.sub(1)];
		}

		uint[] memory amountsOut = uniswapRouter.swapExactETHForTokens{value: swappingAmount}(
			plennyQuoteOut,
			path,
			address(this),
			block.timestamp.add(3600));

		emit SoldEthForPlenny(jobId, amountsOut[0], amountsOut[1], _blockNumber());
		return (amountsOut[0], amountsOut[1]);
	}

	/// @notice Get ETH-PL2 quote from DEX.
	/// @param 	plennyAmount PL2 amount
	/// @param 	ethAmount ETH amount
	/// @return optimalEthAmount quote
	function getOptimalAmount(uint256 plennyAmount, uint256 ethAmount) private view returns (uint256 optimalEthAmount) {
		(uint256 plenny, uint256 eth) = getReserves(contractRegistry.lpContract());
		uint256 amountBOptimal = contractRegistry.uniswapRouterV2().quote(plennyAmount, plenny, eth);

		if (ethAmount > amountBOptimal) {
			ethAmount = amountBOptimal;
		}
		return ethAmount;
	}

	/// @notice Get ETH-PL2 pool info from DEX.
	/// @param 	lpContract pool info
	/// @return plennySupply PL2 amount in the DEX pool
	/// @return ethSupply ETH amount in the DEX pool
	function getReserves(IUniswapV2Pair lpContract) private view returns (uint256 plennySupply, uint256 ethSupply) {
		uint256 ethReserve;
		uint256 plennyReserve;

		address token0 = lpContract.token0();
		if (token0 == contractRegistry.requireAndGetAddress("WETH")) {
			(ethReserve, plennyReserve,) = lpContract.getReserves();
		} else {
			(plennyReserve, ethReserve,) = lpContract.getReserves();
		}
		return (plennyReserve, ethReserve);
	}
}

