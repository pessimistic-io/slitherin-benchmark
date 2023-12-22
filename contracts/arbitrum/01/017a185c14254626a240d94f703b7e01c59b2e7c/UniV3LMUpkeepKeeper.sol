// SPDX-License-Identifire: MIt
pragma solidity 0.8.19;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {AutomationCompatible} from "./AutomationCompatible.sol";

import {IUniV3LiquidityMining} from "./IUniV3LiquidityMining.sol";
import {IKeeperRegistry} from "./IKeeperRegistry.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IWETH} from "./IWETH.sol";

import {AutoRefill} from "./AutoRefill.sol";

contract UniV3LMUpkeepKeeper is AutomationCompatible, Ownable {
  using SafeERC20 for IERC20;

  IUniV3LiquidityMining public uniV3Lm;

  uint256 public topupAmountEth;
  uint256 public keeperId;
  uint64 public maxIndex;

  /// Vendors
  ISwapRouter public immutable router;
  IKeeperRegistry public immutable keeperRegistry;

  address public immutable treasury;
  IERC20 public immutable link;

  IWETH public constant WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

  event LogSetUniV3LiquidityMining(
    address oldAddress, address indexed newAddress
  );
  event LogSetMaxIndex(uint64 oldMaxIndex, uint64 newMaxIndex);
  event LogSetTopupAmountEth(uint256 topupAmountEth);
  event LogSetKeeperId(uint256 keeperId);
  event LogTopup(uint256 amount);

  constructor(
    address _uniswapV3LiquidityMining,
    address _router,
    address _keeperRegistry,
    address _treasury,
    address _link,
    uint64 _maxIndex,
    uint256 _topupAmountETH
  ) {
    uniV3Lm = IUniV3LiquidityMining(_uniswapV3LiquidityMining);
    router = ISwapRouter(_router);
    keeperRegistry = IKeeperRegistry(payable(_keeperRegistry));
    treasury = _treasury;
    maxIndex = _maxIndex;
    topupAmountEth = _topupAmountETH;
    link = IERC20(_link);

    // Approve router
    IERC20(WETH).safeApprove(_router, type(uint256).max);
    link.safeApprove(_router, type(uint256).max);
    // Approve registry
    link.safeApprove(_keeperRegistry, type(uint256).max);
  }

  // NOTE: this method is calculated off-chain by Chainlink Automation
  function checkUpkeep(bytes calldata /* checkData */ )
    external
    view
    override
    returns (bool upkeepNeeded, bytes memory /* performData */ )
  {
    // SLOAD
    IUniV3LiquidityMining _uniV3Lm = uniV3Lm;
    (,,,, uint64 endTime) = _uniV3Lm.incentives(_uniV3Lm.activeIncentiveId());

    upkeepNeeded =
      (block.timestamp >= endTime) && (_uniV3Lm.keeper() == address(this));
  }

  function performUpkeep(bytes calldata /* performData */ ) external override {
    // SLOAD
    IUniV3LiquidityMining _uniV3Lm = uniV3Lm;

    // re-check condition before perform, best practice
    (,,,, uint64 endTime) = _uniV3Lm.incentives(_uniV3Lm.activeIncentiveId());
    if((block.timestamp >= endTime) && (_uniV3Lm.keeper() == address(this))){
      _uniV3Lm.upKeep(maxIndex, true);
    }
    uint256 linkReceived = AutoRefill.addFundsIfNeeded(
      keeperRegistry,
      router,
      WETH,
      link,
      keeperId,
      treasury,
      topupAmountEth,
      5 ether
    );
    emit LogTopup(linkReceived);
  }

  function setUniV3LiquidityMining(address _newAddress) external onlyOwner {
    require(_newAddress != address(0), "Invalid Address");
    emit LogSetUniV3LiquidityMining(address(uniV3Lm), _newAddress);
    uniV3Lm = IUniV3LiquidityMining(_newAddress);
  }

  function setMaxIndex(uint64 _newMaxIndex) external onlyOwner {
    require(_newMaxIndex >= 0, "Invalid Index");
    emit LogSetMaxIndex(maxIndex, _newMaxIndex);
    maxIndex = _newMaxIndex;
  }

  function setKeeperId(uint256 _keeperId) external onlyOwner {
    keeperId = _keeperId;
    emit LogSetKeeperId(_keeperId);
  }

  function setTopupAmountEth(uint256 _topupAmountEth) external onlyOwner {
    require(_topupAmountEth > 0, "Invalid Amount");
    topupAmountEth = _topupAmountEth;
    emit LogSetTopupAmountEth(_topupAmountEth);
  }

  receive() external payable {}
}

