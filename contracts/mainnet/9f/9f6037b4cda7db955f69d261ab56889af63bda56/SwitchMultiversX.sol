// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./DataTypes.sol";
import "./Switch.sol";
import "./IMultiversXBridge.sol";
import "./ReentrancyGuard.sol";

contract SwitchMultiversX is Switch {
  error TransferAmountZero();

  using UniversalERC20 for IERC20;
  using SafeERC20 for IERC20;

  address public mxBridgeGate;

  // for recipient param, multiverseX account address should be converedt to bytes32
  // multiversX https://docs.multiversx.com/developers/sc-calls-format/
  // https://slowli.github.io/bech32-buffer/
  struct SwapArgsMxBridge {
    address srcToken;
    address bridgeToken; // in general USDC
    bytes32 id;
    bytes32 bridge;
    bytes32 dstToken;
    bytes32 recipient;
    address partner;
    uint256 partnerFeeRate;
    bytes permit;
    bytes srcParaswapData;
    uint256 amount;
    uint256 minSrcReturn; // min return from swap on src chain
    uint256 estimatedDstTokenAmount;
  }

  event SetMxBridgeGate(
    address indexed originalMxBridgeGate,
    address indexed newMxBridgeGate
  );

  constructor(
    address _weth,
    address _otherToken,
    uint256 _pathCount,
    uint256 _pathSplit,
    address[] memory _factories,
    address[] memory _switchViewAndEventAddresses,
    address _paraswapProxy,
    address _augustusSwapper,
    address _feeCollector,
    address _mxBridgeGate
  )
    Switch(
      _weth,
      _otherToken,
      _pathCount,
      _pathSplit,
      _factories,
      _switchViewAndEventAddresses[0],
      _switchViewAndEventAddresses[1],
      _paraswapProxy,
      _augustusSwapper,
      _feeCollector
    )
  {
    mxBridgeGate = _mxBridgeGate;
  }

  function setMxBridgeGate(address _mxBridgeGate) external onlyOwner {
    address tmp = mxBridgeGate;
    mxBridgeGate = _mxBridgeGate;
    emit SetMxBridgeGate(tmp, _mxBridgeGate);
  }

  function swapByMxBridge(
    SwapArgsMxBridge calldata transferArgs
  ) external payable nonReentrant {
    if (transferArgs.amount <= 0) revert TransferAmountZero();
    IERC20(transferArgs.srcToken).universalTransferFrom(
      msg.sender,
      address(this),
      transferArgs.amount
    );
    uint256 amountAfterFee = _getAmountAfterFee(IERC20(transferArgs.srcToken), transferArgs.amount, transferArgs.partner, transferArgs.partnerFeeRate);
    uint256 bridgeAmount = amountAfterFee;

    if (transferArgs.srcToken != transferArgs.bridgeToken) {
      bridgeAmount = _swapInternalWithParaSwap(
        IERC20(transferArgs.srcToken),
        IERC20(transferArgs.bridgeToken),
        bridgeAmount,
        transferArgs.srcParaswapData
      );
      require(bridgeAmount >= transferArgs.minSrcReturn, "return amount was not enough");
    }

    IERC20(transferArgs.bridgeToken).universalApprove(mxBridgeGate, bridgeAmount);

    IMultiversXBridge(mxBridgeGate).deposit(
      transferArgs.bridgeToken,
      bridgeAmount,
      transferArgs.recipient
    );

    _emitCrossChainSwapRequest(transferArgs, bridgeAmount, msg.sender);
  }

  function _emitCrossChainSwapRequest(
    SwapArgsMxBridge calldata transferArgs,
    uint256 returnAmount,
    address sender
  ) internal {
    switchEvent.emitCrosschainSwapRequest(
      transferArgs.id,
      bytes32(0),
      transferArgs.bridge,
      sender,
      transferArgs.srcToken,
      transferArgs.bridgeToken,
      address(0), // placeholder as multiversX uses bech32
      transferArgs.amount,
      returnAmount,
      transferArgs.estimatedDstTokenAmount,
      DataTypes.SwapStatus.Succeeded
    );
  }
}

