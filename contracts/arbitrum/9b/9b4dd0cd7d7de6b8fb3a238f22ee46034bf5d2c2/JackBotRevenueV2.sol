// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./IERC20.sol";

import "./ICamelotFactory.sol";
import "./ICamelotRouter.sol";

contract JackBotRevenueV2 is Ownable {
  using SafeMath for uint256;

  address public immutable jackbotAddress;
  // https://docs.camelot.exchange/contracts/amm-v2/router
  ICamelotRouter public immutable camelotRouter;
  address public immutable camelotPair;

  event SwapAndLiquify(
    uint256 tokensSwapped,
    uint256 ethReceived,
    uint256 tokensIntoLiquidity
  );

  constructor(address _jackbotAddress) {
    jackbotAddress = _jackbotAddress;

    ICamelotRouter _camelotRouter = ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);

    // excludeFromMaxTransaction(address(_camelotRouter), true);
    camelotRouter = _camelotRouter;

    camelotPair = ICamelotFactory(_camelotRouter.factory()).createPair(_jackbotAddress, _camelotRouter.WETH());
    // excludeFromMaxTransaction(address(camelotPair), true);
    // _setAutomatedMarketMakerPair(address(camelotPair), true);
  }

  receive() external payable {}

  function swapTokensForEth(uint256 tokenAmount) internal {
    // generate the camelot pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = jackbotAddress;
    path[1] = camelotRouter.WETH();

    IERC20(jackbotAddress).approve(address(camelotRouter), tokenAmount);

    // make the swap
    camelotRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this),
      address(0), // no referrer
      block.timestamp
    );
  }

  function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
    // approve token transfer to cover all possible scenarios
    IERC20(jackbotAddress).approve(address(camelotRouter), tokenAmount);

    // add the liquidity
    camelotRouter.addLiquidityETH{value: ethAmount}(
      jackbotAddress,
      tokenAmount,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      owner(),
      block.timestamp
    );
  }

  struct SwapBackInfo {
    uint256 liquidityTokens;
    uint256 amountToSwapForETH;
    uint256 initialETHBalance;
    uint256 ethBalance;
    uint256 ethForBankroll;
    uint256 ethForRevShare;
    uint256 ethForTeam;
    uint256 ethForLiquidity;
  }

  function swapBack(
    uint256 contractBalance,
    uint256 tokensForBankroll,
    uint256 tokensForLiquidity,
    uint256 tokensForRevShare,
    uint256 tokensForTeam,
    uint256 swapTokensAtAmount,
    address teamWallet,
    address revShareWallet,
    address bankrollWallet
  ) external {
    uint256 totalTokensToSwap = tokensForBankroll + tokensForLiquidity + tokensForRevShare + tokensForTeam;
    bool success;

    if (contractBalance == 0 || totalTokensToSwap == 0) {
      return;
    }

    SwapBackInfo memory info;

    // Halve the amount of liquidity tokens
    info.liquidityTokens = (contractBalance * tokensForLiquidity) / totalTokensToSwap / 2;
    info.amountToSwapForETH = contractBalance.sub(info.liquidityTokens);

    info.initialETHBalance = address(this).balance;

    // this will receive WETH, not ETH
    swapTokensForEth(info.amountToSwapForETH);

    info.ethBalance = address(this).balance.sub(info.initialETHBalance);
    info.ethForBankroll = info.ethBalance.mul(tokensForBankroll).div(totalTokensToSwap - (tokensForLiquidity / 2));
    info.ethForRevShare = info.ethBalance.mul(tokensForRevShare).div(totalTokensToSwap - (tokensForLiquidity / 2));
    info.ethForTeam = info.ethBalance.mul(tokensForTeam).div(totalTokensToSwap - (tokensForLiquidity / 2));
    info.ethForLiquidity = info.ethBalance - info.ethForBankroll - info.ethForRevShare - info.ethForTeam;

    tokensForLiquidity = 0;
    tokensForRevShare = 0;
    tokensForTeam = 0;

    (success, ) = address(teamWallet).call{value: info.ethForTeam}("");

    if (info.liquidityTokens > 0 && info.ethForLiquidity > 0) {
      addLiquidity(info.liquidityTokens, info.ethForLiquidity);
      emit SwapAndLiquify(
        info.amountToSwapForETH,
        info.ethForLiquidity,
        tokensForLiquidity
      );
    }

    (success, ) = address(revShareWallet).call{value: info.ethForRevShare}("");
    (success, ) = address(bankrollWallet).call{value: address(this).balance}("");
  }

  function withdrawStuckJackbot() external onlyOwner {
    uint256 balance = IERC20(address(this)).balanceOf(address(this));
    IERC20(jackbotAddress).transfer(msg.sender, balance);
    payable(msg.sender).transfer(address(this).balance);
  }

  function withdrawStuckToken(address _token, address _to) external onlyOwner {
    require(_token != address(0), "_token address cannot be 0");
    uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
    IERC20(_token).transfer(_to, _contractBalance);
  }

  function withdrawStuckEth(address toAddr) external onlyOwner {
    (bool success, ) = toAddr.call{value: address(this).balance} ("");
    require(success);
  }
}

