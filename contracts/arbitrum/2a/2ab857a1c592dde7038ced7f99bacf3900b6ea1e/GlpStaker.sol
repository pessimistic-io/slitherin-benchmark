// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./IERC721Enumerable.sol";
import "./IRewardRouterV2.sol";

interface IWETH is IERC20 {
  function withdrawTo(address account, uint256 amount) external;
}

contract GlpStaker is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  uint256 private constant FEE_DIVISOR = 1e4;
  IERC20 private constant sGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE); // transfers
  IWETH private constant WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  IRewardRouterV2 private constant REWARD_ROUTER_V2 = IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);

  mapping(address => bool) public operators;
  address public depositor;
  address public compounder;
  bool public shouldCompound;
  uint32 public fee;
  address private feeCollector;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _feeCollector, address _compounder) public virtual initializer {
    fee = 1000; // fee in bp - 10%;
    feeCollector = _feeCollector; //set fee collector
    compounder = _compounder;
    shouldCompound = true;

    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function handleRewards() external returns (uint256) {
    if (operators[msg.sender] == false) revert UNAUTHORIZED();
    REWARD_ROUTER_V2.handleRewards(true, true, true, true, true, true, false);

    uint256 _rawWethYield = WETH.balanceOf(address(this));
    if (_rawWethYield == 0) return 0;

    (uint256 _fee, uint256 _wethYieldLessFee) = _calculateFee(_rawWethYield);
    uint256 keeperFee = _fee / 20; // 5% of fee / 0.5% of total;
    uint256 feeLessKeeperFee = _fee - keeperFee;

    WETH.transfer(feeCollector, feeLessKeeperFee);
    WETH.withdrawTo(msg.sender, keeperFee);
    WETH.transfer(compounder, _wethYieldLessFee);

    if (shouldCompound) {
      compounder.call(abi.encodeWithSelector(0x2dbf4dd9, depositor));
    }

    emit Harvested(feeLessKeeperFee, _wethYieldLessFee);

    return _wethYieldLessFee;
  }

  function _calculateFee(uint256 _totalAmount) private view returns (uint256 _fee, uint256 _amountLessFee) {
    unchecked {
      _fee = (_totalAmount * fee) / FEE_DIVISOR;
      _amountLessFee = _totalAmount - _fee;
    }
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  /**
    Owner can retrieve stuck funds
   */
  function retrieve(IERC20 token) external onlyOwner {
    if (address(this).balance != 0) {
      owner().call{ value: address(this).balance }('');
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  function retrieveNFT(IERC721Enumerable token, uint256 tokenId) external onlyOwner {
    token.approve(owner(), tokenId);
    token.transferFrom(address(this), owner(), tokenId);
  }

  function setFee(uint32 _newFee) external onlyOwner {
    if (_newFee > FEE_DIVISOR) revert BAD_FEE();
    fee = _newFee;
  }

  function updateOperator(address _operator, bool _isActive) external onlyOwner {
    emit OperatorUpdated(_operator, _isActive);
    operators[_operator] = _isActive;
  }

  function setDepositor(address _newDepositor) external onlyOwner {
    sGLP.approve(_newDepositor, type(uint256).max);
    if (depositor != address(0)) {
      sGLP.approve(depositor, 0);
    }

    emit DepositorChanged(_newDepositor, depositor);

    depositor = _newDepositor;
  }

  function updateCompounder(address _newCompounder, bool _shouldCompound) external onlyOwner {
    emit CompounderUpdated(_newCompounder, compounder, _shouldCompound);

    compounder = _newCompounder;
    shouldCompound = _shouldCompound;
  }

  function setFeeCollector(address _newFeeCollector) external onlyOwner {
    emit FeeCollectorUpdated(_newFeeCollector, feeCollector);
    feeCollector = _newFeeCollector;
  }

  event OperatorUpdated(address indexed _new, bool _isActive);
  event DepositorChanged(address indexed _new, address _old);
  event CompounderUpdated(address indexed _new, address _old, bool _shouldCompound);
  event KeeperFeeUpdated(uint80 _newFee, uint80 _oldFee);
  event FeeCollectorUpdated(address _new, address _old);
  event Harvested(uint256 fee, uint256 rewardsLessFee);

  error UNAUTHORIZED();
  error BAD_FEE();
}

