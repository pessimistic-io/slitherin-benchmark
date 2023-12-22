// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./IWETH.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router01.sol";
import "./IMiniChef.sol";
import "./ISwapPlusv1.sol";
import "./IFeeTierStrate.sol";
import "./ILCPoolUniV2Ledger.sol";

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./StringUtils.sol";

contract LCPoolUniV2 is Ownable {
  using SafeERC20 for IERC20;

  address public v2Router;
  address public v2MasterChef;
  address public WETH;
  address public rewardToken;
  address public swapRouter;
  address public feeStrate;
  address public ledger;
  string public pendingRewardsFunctionName;

  uint256 private constant coreDecimal = 1000000;
  bool public reinvestAble = true;
  uint256 public reinvestEdge = 100;

  struct Operator {
    address account;
    address[2] pair;
    uint256 meta; // poolId
    uint256 basketId;
    address token;
    uint256 amount;
  }

  struct swapPath {
    ISwapPlusv1.swapBlock[] path;
  }

  mapping (address => bool) public managers;
  mapping (address => bool) public operators;
  modifier onlyManager() {
    require(managers[msg.sender], "LC pool: !manager");
    _;
  }

  event Deposit(uint256 poolId, uint256 liquiidty);
  event Withdraw(uint256 poolId, uint256 liquiidty, uint256 amountOut);
  event ReInvest(address token0, address token1, uint256 poolId, uint256 reward, uint256 extraLp);
  event RemovePool(address operator, address from, uint256 tokenId, address token0, address token1, uint24 fee, bytes data);
  event LcFee(address account, address token, uint256 amount);
  event ClaimReward(address account, uint256 poolId, uint256 basketId, uint256 extraLp, uint256 reward);

  constructor (
    address _v2Router,
    address _v2MasterChef,
    address _swapRouter,
    address _feeStrate,
    address _ledger,
    address _WETH,
    address _reward,
    string memory _pendingRewardsFunctionName
  ) {
    require(_v2Router != address(0), "LC pool: router");
    require(_v2MasterChef != address(0), "LC pool: master chef");
    require(_swapRouter != address(0), "LC pool: swap router");
    require(_feeStrate != address(0), "LC pool: feeStrate");
    require(_ledger != address(0), "LC pool: ledger");
    require(_WETH != address(0), "LC pool: WETH");
    require(_reward != address(0), "LC pool: reward");

    v2Router = _v2Router;
    v2MasterChef = _v2MasterChef;
    swapRouter = _swapRouter;
    feeStrate = _feeStrate;
    ledger = _ledger;
    WETH = _WETH;
    rewardToken = _reward;
    pendingRewardsFunctionName = _pendingRewardsFunctionName;
    managers[msg.sender] = true;
  }

  receive() external payable {
  }

  /**
   * mtoken     0: tokenMReward, 1: tM'
   * percent    0: tM->t0%       1: tM->t1%
   * paths      0: tIn->tM,      1: tM->t0,  2: tM->t1
   * minAmounts 0: lpMin0        1: lpMin1
   */
  // function deposit(uint256 tokenId, uint256 basketId, uint256 liquidity, uint256 reward, uint256 exRate) public payable {
  function deposit(
    Operator calldata info,
    address[2][2] calldata mtoken,
    uint256[2][2] calldata percent,
    swapPath[3] calldata paths,
    swapPath[3] calldata rpaths,
    uint256[2][2] calldata minAmounts
  ) public payable returns(uint256, uint256) {
    require(msg.sender == info.account || operators[msg.sender], "LC pool: no access");
    uint256[] memory dpvar = new uint256[](4);
    dpvar[0] = 0; // reward
    dpvar[1] = 0; // exLp
    dpvar[2] = 0; // rewardReserve
    dpvar[3] = 0; // iAmount
    if (info.token != address(0)) {  // If address is not null, send this amount to contract.
      dpvar[3] = IERC20(info.token).balanceOf(address(this));
      IERC20(info.token).safeTransferFrom(info.account, address(this), info.amount);
      dpvar[3] = IERC20(info.token).balanceOf(address(this)) - dpvar[3];
    }
    else {
      IWETH(WETH).deposit{value: msg.value}();
      dpvar[3] = msg.value;
    }

    
    (dpvar[1], dpvar[0], dpvar[2], ,) = _reinvest(info, mtoken[1], percent[1], rpaths, minAmounts[1], false);

    dpvar[3] = _distributeFee(info.basketId, (info.token==address(0)?WETH:info.token), dpvar[3], 1);
    uint256 liquidity = _deposit(info, dpvar[3], mtoken[0], percent[0], paths, minAmounts[0]);
    ILCPoolUniV2Ledger(ledger).updateInfo(info.account, info.meta, info.basketId, liquidity, dpvar[0], dpvar[2], dpvar[1], true);

    return (info.meta, liquidity);
  }

  function withdraw(
    address receiver,
    Operator calldata info,
    address[2][2] calldata mtoken,
    uint256[2] calldata percent,
    swapPath[3] calldata paths,
    swapPath[3] calldata rpaths,
    uint256[2][2] calldata minAmounts
  ) public returns(uint256) {
    require(receiver == info.account || operators[msg.sender], "LC pool: no access");
    // 0: reward
    // 1: exLp
    // 2: rewardReserve
    // 3: tokenId
    // 4: outAmount
    // 5: claim extra lp
    // 6: claim reward amount
    // 7: withdrawn liquidity amount
    // 8: current reward
    uint256[] memory wvar = new uint256[](9);
    
    (wvar[1], wvar[0], wvar[2], wvar[5], wvar[6]) = _reinvest(info, mtoken[1], percent, rpaths, minAmounts[1], true);
    wvar[8] = IERC20(rewardToken).balanceOf(address(this));
    if (wvar[8] < wvar[6]) {
      wvar[6] = wvar[8];
    }
    if (wvar[6] > 0) {
      IERC20(rewardToken).safeTransfer(info.account, wvar[6]);
    }

    bool isCoin = false;
    if (info.token == address(0)) {
      isCoin = true;
    }
    // return tokenId, withdraw liquidity amount, receive token amount
    (wvar[3], wvar[7], wvar[4]) = _withdraw(info, wvar[5], mtoken[0], paths, minAmounts[0]);
    ILCPoolUniV2Ledger(ledger).updateInfo(info.account, wvar[3], info.basketId, wvar[7], wvar[0], wvar[2], wvar[1], false);

    wvar[4] = _distributeFee(info.basketId, isCoin?WETH:info.token, wvar[4], 0);

    if (wvar[4] > 0) {
      if (isCoin) {
        IWETH(WETH).withdraw(wvar[4]);
        (bool success, ) = payable(receiver).call{value: wvar[4]}("");
        require(success, "LC pool: Failed receipt");
      }
      else {
        IERC20(info.token).safeTransfer(receiver, wvar[4]);
      }
    }
    if (wvar[5] > 0 || wvar[6] > 0) {
      emit ClaimReward(info.account, wvar[3], info.basketId, wvar[5], wvar[6]);
    }
    return wvar[4];
  }

  /**
   * tokens   0: token0,  1: token1,
   * mtokens  0: tokenM,  1: tM'
   * paths    0: t->tM,   1: tM->t0,   2: tM->t1
   * percents 0: tM->t0%  1: tM->t1%
   * return amount0, amount1
   */
  function _depositSwap(
    address tokenIn,
    uint256 amountIn,
    address[2] memory tokens,
    address[2] calldata mTokens,
    uint256[2] calldata percents,
    swapPath[3] calldata paths
  ) internal returns(uint256, uint256) {
    uint256[2] memory outs;
    outs[0] = amountIn;
    outs[1] = amountIn;
    uint256 amountM = amountIn;
    if (tokenIn == address(0)) tokenIn = WETH;

    if (paths[0].path.length > 0) {
      _approveTokenIfNeeded(tokenIn, swapRouter, amountM);
      (, amountM) = ISwapPlusv1(swapRouter).swap(tokenIn, amountM, mTokens[0], address(this), paths[0].path);
    }
    if (paths[1].path.length > 0) {
      _approveTokenIfNeeded(mTokens[0], swapRouter, amountM);
      (, outs[0]) = ISwapPlusv1(swapRouter).swap(mTokens[0], amountM*percents[0]/coreDecimal, tokens[0], address(this), paths[1].path);
      amountM -= amountM*percents[0]/coreDecimal;
      outs[1] = amountM;
    }
    if (paths[2].path.length > 0) {
      if (mTokens[0] == mTokens[1]) {
        _approveTokenIfNeeded(mTokens[1], swapRouter, amountM);
        (, outs[1]) = ISwapPlusv1(swapRouter).swap(mTokens[1], amountM, tokens[1], address(this), paths[2].path);
      }
      else {
        _approveTokenIfNeeded(mTokens[1], swapRouter, outs[0]);
        (, outs[1]) = ISwapPlusv1(swapRouter).swap(mTokens[1], outs[0]*percents[1]/coreDecimal, tokens[1], address(this), paths[2].path);
        outs[0] -= outs[0]*percents[1]/coreDecimal;
      }
    }
    return (outs[0], outs[1]);
  }

  /**
   * return extraLp, reward, reserved reward
   */
  function _reinvest(
    Operator calldata info,
    address[2] calldata mtoken,
    uint256[2] calldata percents,
    swapPath[3] calldata paths,
    uint256[2] calldata minAmounts,
    bool claimReward
  ) internal returns(uint256, uint256, uint256, uint256, uint256) {
    uint256[] memory rvar = new uint256[](8);
    rvar[1] = IERC20(rewardToken).balanceOf(address(this)); // reward
    rvar[2] = 0; // extraLp
    rvar[6] = 0; // claim extra lp
    rvar[7] = 0; // claim reward amount
    if (_rewardsAvailable(info.meta) > 0) {
      IMiniChef(v2MasterChef).deposit(info.meta, 0, address(this));
    }
    rvar[1] = IERC20(rewardToken).balanceOf(address(this)) - rvar[1];
    if (claimReward) {
      (rvar[6], rvar[7]) = ILCPoolUniV2Ledger(ledger).getSingleReward(info.account, info.meta, info.basketId, rvar[1], false);
    }
    rvar[1] += ILCPoolUniV2Ledger(ledger).getLastRewardAmount(info.meta);

    rvar[1] = _distributeFee(info.basketId, rewardToken, rvar[1], 2);
    rvar[1] = rvar[1] >= rvar[7] ? rvar[1] - rvar[7] : 0;
    rvar[3] = rvar[1]; // reserveReward

    if (reinvestAble && rvar[1] >= reinvestEdge) {
      rvar[3] = IERC20(rewardToken).balanceOf(address(this));
      (rvar[4], rvar[5]) = _depositSwap(rewardToken, rvar[1], info.pair, mtoken, percents, paths);
      (rvar[2], , ) = _increaseLiquidity(info.meta, info.pair, rvar[4], rvar[5], minAmounts[0], minAmounts[1]);
      rvar[3] = rvar[1] + IERC20(rewardToken).balanceOf(address(this)) - rvar[3];
      emit ReInvest(info.pair[0], info.pair[1], info.meta, rvar[1], rvar[2]);
    }
    return (rvar[2], rvar[1], rvar[3], rvar[6], rvar[7]);
  }

  function _rewardsAvailable(uint256 poolId) public view returns (uint256) {
    string memory signature = StringUtils.concat(pendingRewardsFunctionName, "(uint256,address)");
    bytes memory result = Address.functionStaticCall(
      v2MasterChef, 
      abi.encodeWithSignature(
        signature,
        poolId,
        address(this)
      )
    );  
    return abi.decode(result, (uint256));
  }

  /**
   * return tokenId, liquidity
   */
  function _deposit(
    Operator calldata info,
    uint256 iAmount,
    address[2] calldata mtoken,
    uint256[2] calldata percents,
    swapPath[3] calldata paths,
    uint256[2] calldata minAmounts
  ) internal returns(uint256) {
    (uint256 amount0, uint256 amount1) = _depositSwap(info.token, iAmount, info.pair, mtoken, percents, paths);
    uint256 liquidity = 0;
    uint256[] memory amount = new uint256[](2);
    (liquidity, amount[0], amount[1]) = _increaseLiquidity(info.meta, info.pair, amount0, amount1, minAmounts[0], minAmounts[1]);
    _refundReserveToken(info.account, info.pair[0], info.pair[1], amount0-amount[0], amount1-amount[1]);
    emit Deposit(info.meta, liquidity);
    return liquidity;
  }

  function _increaseLiquidity(
    uint256 tokenId,
    address[2] calldata tokens,
    uint256 amount0ToAdd,
    uint256 amount1ToAdd,
    uint256 amount0Min,
    uint256 amount1Min
  ) internal returns (uint256 liquidity, uint256 amount0, uint256 amount1) {
    _approveTokenIfNeeded(tokens[0], v2Router, amount0ToAdd);
    _approveTokenIfNeeded(tokens[1], v2Router, amount1ToAdd);
    (amount0, amount1, liquidity) = IUniswapV2Router01(v2Router).addLiquidity(
      tokens[0],
      tokens[1],
      amount0ToAdd,
      amount1ToAdd,
      amount0Min,
      amount1Min,
      address(this),
      block.timestamp
    );

    address pair = _getPair(tokens[0], tokens[1]);
    _approveTokenIfNeeded(pair, v2MasterChef, liquidity);
    IMiniChef(v2MasterChef).deposit(tokenId, liquidity, address(this));
  }

  function _getPair(address token0, address token1) internal view returns(address) {
    address factory = IUniswapV2Router01(v2Router).factory();
    return IUniswapV2Factory(factory).getPair(token0, token1);
  }

  function _refundReserveToken(address account, address token0, address token1, uint256 amount0, uint256 amount1) internal {
    if (amount0 > 0) {
      IERC20(token0).safeTransfer(account, amount0);
    }
    if (amount1 > 0) {
      IERC20(token1).safeTransfer(account, amount1);
    }
  }

  function _withdrawSwap(
    address tokenOut,
    address[2] memory tokens,
    uint256[2] memory amount,
    address[2] memory mTokens,
    swapPath[3] memory paths
  ) internal returns(uint256) {
    uint256 amountM0 = amount[0];
    uint256 amountM1 = amount[1];
    if (paths[2].path.length > 0) {
      _approveTokenIfNeeded(tokens[1], swapRouter, amount[1]);
      (, amountM1) = ISwapPlusv1(swapRouter).swap(tokens[1], amount[1], mTokens[1], address(this), paths[2].path);
    }

    if (paths[1].path.length == 0) {
      return amount[0] + amountM1;
    }
    else {
      if (mTokens[1] == tokens[0]) {
        amount[0] += amountM1;
      }
      _approveTokenIfNeeded(tokens[0], swapRouter, amount[0]);
      (, amountM0) = ISwapPlusv1(swapRouter).swap(tokens[0], amount[0], mTokens[0], address(this), paths[1].path);
    }

    if (paths[0].path.length == 0) {
      if (mTokens[0] == mTokens[1]) return amountM0+amountM1;
      else return amountM0;
    }
    else {
      _approveTokenIfNeeded(mTokens[0], swapRouter, amountM0+amountM1);
      (, amountM0) = ISwapPlusv1(swapRouter).swap(mTokens[0], amountM0+amountM1, tokenOut, address(this), paths[0].path);
      return amountM0;
    }
  }

  /**
   * return tokenId, withdraw liquidity amount, receive token amount
   */
  function _withdraw(
    Operator calldata info,
    uint256 extraLp,
    address[2] memory mtoken,
    swapPath[3] memory paths,
    uint256[2] memory minAmounts
  ) internal returns(uint256, uint256, uint256) {
    uint256 withdrawAmount = info.amount;
    uint256 userLiquidity = ILCPoolUniV2Ledger(ledger).getUserLiquidity(info.account, info.meta, info.basketId);
    if (userLiquidity < withdrawAmount) {
      withdrawAmount = userLiquidity;
    }
    uint256[] memory amount = new uint256[](3);
    withdrawAmount += extraLp;
    (uint256 liquidity0, ) = IMiniChef(v2MasterChef).userInfo(info.meta, address(this));
    if (liquidity0 < withdrawAmount) {
      withdrawAmount = liquidity0;
    }
    if (withdrawAmount > 0) {
      (amount[0], amount[1]) = _decreaseLiquidity(info.meta, info.pair, withdrawAmount, minAmounts[0], minAmounts[1]);
      amount[2] = _withdrawSwap(info.token, info.pair, [amount[0], amount[1]], mtoken, paths);
      emit Withdraw(info.meta, withdrawAmount, amount[2]);
      return (info.meta, withdrawAmount, amount[2]);
    }
    else {
      return (info.meta, withdrawAmount, 0);
    }
  }

  function _decreaseLiquidity(
    uint256 tokenId,
    address[2] calldata tokens,
    uint256 liquidity,
    uint256 amount0Min,
    uint256 amount1Min
  ) internal returns (uint256, uint256) {
    address pair = _getPair(tokens[0], tokens[1]);
    uint256 balanceLP = IERC20(pair).balanceOf(address(this));
    IMiniChef(v2MasterChef).withdraw(tokenId, liquidity, address(this));
    liquidity = IERC20(pair).balanceOf(address(this)) - balanceLP;

    _approveTokenIfNeeded(pair, v2Router, liquidity);

    return IUniswapV2Router01(v2Router).removeLiquidity(
      tokens[0],
      tokens[1],
      liquidity,
      amount0Min,
      amount1Min,
      address(this),
      block.timestamp
    );
  }

  // mode 0: withdraw 1: deposit 2: reward
  function _distributeFee(uint256 basketId, address token, uint256 amount, uint256 mode) internal returns(uint256) {
    uint256[] memory fvar = new uint256[](4);
    fvar[0] = 0; // totalFee
    fvar[1] = 0; // baseFee
    if (mode == 0) {
      (fvar[0], fvar[1]) = IFeeTierStrate(feeStrate).getWithdrawFee(basketId);
    }
    else if (mode == 1) {
      (fvar[0], fvar[1]) = IFeeTierStrate(feeStrate).getDepositFee(basketId);
    }
    else if (mode == 2) {
      (fvar[0], fvar[1]) = IFeeTierStrate(feeStrate).getTotalFee(basketId);
    }

    fvar[2] = amount; // rewardReserve
    require(fvar[1] > 0, "LC pool: wrong fee configure");
    fvar[3] = amount * fvar[0] / fvar[1]; // rewardLc

    if (fvar[3] > 0) {
      uint256[] memory feeIndexs = IFeeTierStrate(feeStrate).getAllTier();
      uint256 len = feeIndexs.length;
      uint256 maxFee = IFeeTierStrate(feeStrate).getMaxFee();
      for (uint256 i=0; i<len; i++) {
        (address feeAccount, ,uint256 fee) = IFeeTierStrate(feeStrate).getTier(feeIndexs[i]);
        uint256 feeAmount = fvar[3] * fee / maxFee;
        if (feeAmount > 0 && fvar[2] >= feeAmount && IERC20(token).balanceOf(address(this)) > feeAmount) {
          IERC20(token).safeTransfer(feeAccount, feeAmount);
          emit LcFee(feeAccount, token, feeAmount);
          fvar[2] -= feeAmount;
        }
      }
    }
    return fvar[2];
  }

  function setManager(address account, bool access) public onlyOwner {
    managers[account] = access;
  }

  function setOperator(address account, bool access) public onlyManager {
    operators[account] = access;
  }

  function setFeeStrate(address _feeStrate) external onlyManager {
    require(_feeStrate != address(0), "LC pool: Fee Strate");
    feeStrate = _feeStrate;
  }

  function setSwapRouter(address _swapRouter) external onlyManager {
    require(_swapRouter != address(0), "LC pool: Swap Router");
    swapRouter = _swapRouter;
  }

  function setReinvestInfo(bool able, uint256 edge) public onlyManager {
    reinvestAble = able;
    reinvestEdge = edge;
  }

  function _approveTokenIfNeeded(address token, address spender, uint256 amount) private {
    if (IERC20(token).allowance(address(this), spender) < amount) {
      IERC20(token).safeApprove(spender, 0);
      IERC20(token).safeApprove(spender, type(uint256).max);
    }
  }
}

