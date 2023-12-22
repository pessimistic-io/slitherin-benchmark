// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { Ownable } from "./Ownable.sol";
import { Ownable2Step } from "./Ownable2Step.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Pausable } from "./Pausable.sol";
import { IWNT } from "./IWNT.sol";
import { IGMXVault } from "./IGMXVault.sol";
import { ILendingVault } from "./ILendingVault.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { IGMXOracle } from "./IGMXOracle.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";
import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { ISwap } from "./ISwap.sol";
import { Errors } from "./Errors.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXDeposit } from "./GMXDeposit.sol";
import { GMXWithdraw } from "./GMXWithdraw.sol";
import { GMXRebalance } from "./GMXRebalance.sol";
import { GMXCompound } from "./GMXCompound.sol";
import { GMXEmergency } from "./GMXEmergency.sol";
import { GMXReader } from "./GMXReader.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { IGMXOracle } from "./IGMXOracle.sol";

contract GMXTest is Ownable {
  using SafeERC20 for IERC20;

  IExchangeRouter public exchangeRouter = IExchangeRouter(0x3B070aA6847bd0fB56eFAdB351f49BBb7619dbc2);
  address public tokenA = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public tokenB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
  address public lpToken = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
  address public depositVault = 0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;
  address public withdrawalVault = 0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55;
  IGMXOracle public gmxOracle = IGMXOracle(0xd2511f5b1d8818041bFd961cF3CEF23a4Cd0E72f);
  IChainlinkOracle public chainlinkOracle = IChainlinkOracle(0xb6C62D5EB1F572351CC66540d043EF53c4Cd2239);
  uint256 public constant SAFE_MULTIPLIER = 1e18;

  constructor() Ownable(msg.sender) {}

  function convertToUsdValue(
    address token,
    uint256 amt
  ) public view returns (uint256) {
    return amt * 10**(18 - IERC20Metadata(token).decimals())
                * chainlinkOracle.consultIn18Decimals(token)
                / SAFE_MULTIPLIER;
  }

  function tokenWeights() public view returns (uint256, uint256) {
    // Get amounts of tokenA and tokenB in liquidity pool in token decimals
    (uint256 _reserveA, uint256 _reserveB) = gmxOracle.getLpTokenReserves(
      address(lpToken),
      address(tokenA),
      address(tokenA),
      address(tokenB)
    );

    // Get value of tokenA and tokenB in 1e18
    uint256 _tokenAValue = convertToUsdValue(address(tokenA), _reserveA);
    uint256 _tokenBValue = convertToUsdValue(address(tokenB), _reserveB);

    uint256 _totalLpValue = _tokenAValue + _tokenBValue;

    return (
      _tokenAValue * SAFE_MULTIPLIER / _totalLpValue,
      _tokenBValue * SAFE_MULTIPLIER / _totalLpValue
    );
  }

  function calcMinTokensSlippageAmt(
    uint256 lpAmt,
    address withdrawToken, // tokenA only, tokenB only or both if lpToken passed
    uint256 slippage
  ) external view returns (uint256, uint256) {
    uint256 _withdrawValue = lpAmt
      * gmxOracle.getLpTokenValue(
        address(lpToken),
        address(tokenA),
        address(tokenA),
        address(tokenB),
        false,
        false
      )
      / SAFE_MULTIPLIER;

    (uint256 _tokenAWeight, uint256 _tokenBWeight) = tokenWeights();

    uint256 _tokenADecimals = IERC20Metadata(address(tokenA)).decimals();
    uint256 _tokenBDecimals = IERC20Metadata(address(tokenB)).decimals();

    uint256 _minWithdrawTokenAAmt;
    uint256 _minWithdrawTokenBAmt;

    if (withdrawToken == lpToken) {
      _minWithdrawTokenAAmt = _withdrawValue
        * _tokenAWeight / SAFE_MULTIPLIER
        * SAFE_MULTIPLIER
        / convertToUsdValue(
          address(tokenA),
          10**(_tokenADecimals)
        )
        / (10 ** (18 - _tokenADecimals));

      _minWithdrawTokenBAmt = _withdrawValue
        * _tokenBWeight / SAFE_MULTIPLIER
        * SAFE_MULTIPLIER
        / convertToUsdValue(
          address(tokenB),
          10**(_tokenBDecimals)
        )
        / (10 ** (18 - _tokenBDecimals));
    } else if (withdrawToken == tokenA) {
      _minWithdrawTokenAAmt = _withdrawValue
        * SAFE_MULTIPLIER
        / convertToUsdValue(
          address(tokenA),
          10**(_tokenADecimals)
        )
        / (10 ** (18 - _tokenADecimals));
    } else if (withdrawToken == tokenB) {
      _minWithdrawTokenBAmt = _withdrawValue
        * SAFE_MULTIPLIER
        / convertToUsdValue(
          address(tokenB),
          10**(_tokenBDecimals)
        )
        / (10 ** (18 - _tokenBDecimals));
    }

    return (
      _minWithdrawTokenAAmt * (10000 - slippage) / 10000,
      _minWithdrawTokenBAmt * (10000 - slippage) / 10000
    );
  }

  function addLiquidity(
    GMXTypes.AddLiquidityParams memory alp
  ) payable external returns (bytes32) {
    // Send native token for execution fee
    exchangeRouter.sendWnt{ value: alp.executionFee }(
      depositVault,
      alp.executionFee
    );

    // Send tokens
    exchangeRouter.sendTokens(
      address(tokenA),
      depositVault,
      alp.tokenAAmt
    );

    exchangeRouter.sendTokens(
      address(tokenB),
      depositVault,
      alp.tokenBAmt
    );

    // Create deposit
    IExchangeRouter.CreateDepositParams memory _cdp =
      IExchangeRouter.CreateDepositParams({
        receiver: address(this),
        callbackContract: address(0),
        uiFeeReceiver: msg.sender,
        market: address(lpToken),
        initialLongToken: address(tokenA),
        initialShortToken: address(tokenB),
        longTokenSwapPath: new address[](0),
        shortTokenSwapPath: new address[](0),
        minMarketTokens: alp.minMarketTokenAmt,
        shouldUnwrapNativeToken: false,
        executionFee: alp.executionFee,
        callbackGasLimit: 2000000
      });

    return exchangeRouter.createDeposit(_cdp);
  }

  function removeLiquidity(
    GMXTypes.RemoveLiquidityParams memory rlp
  ) payable external returns (bytes32) {
    // Send native token for execution fee
    exchangeRouter.sendWnt{value: rlp.executionFee }(
      withdrawalVault,
      rlp.executionFee
    );

    // Send GM LP tokens
    exchangeRouter.sendTokens(
      address(lpToken),
      withdrawalVault,
      rlp.lpAmt
    );

    // Create withdrawal
    IExchangeRouter.CreateWithdrawalParams memory _cwp =
      IExchangeRouter.CreateWithdrawalParams({
        receiver: address(this),
        callbackContract: address(0),
        uiFeeReceiver: msg.sender,
        market: address(lpToken),
        longTokenSwapPath: rlp.tokenASwapPath,
        shortTokenSwapPath: rlp.tokenBSwapPath,
        minLongTokenAmount: rlp.minTokenAAmt,
        minShortTokenAmount: rlp.minTokenBAmt,
        shouldUnwrapNativeToken: false,
        executionFee: rlp.executionFee,
        callbackGasLimit: 2000000
      });

    return exchangeRouter.createWithdrawal(_cwp);
  }

  function resetVault() external onlyOwner {
    IWNT(tokenA).withdraw(address(this).balance);
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed.");


    IERC20(tokenA).safeTransfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));
    IERC20(tokenB).safeTransfer(msg.sender, IERC20(tokenB).balanceOf(address(this)));
    IERC20(lpToken).safeTransfer(msg.sender, IERC20(lpToken).balanceOf(address(this)));
  }

  /* ========== FALLBACK FUNCTIONS ========== */

  /**
    * Fallback function to receive native token sent to this contract,
  */
  receive() external payable {

  }
}

