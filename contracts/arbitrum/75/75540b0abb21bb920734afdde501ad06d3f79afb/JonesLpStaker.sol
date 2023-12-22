// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import { INFTPool, ICamelotPair, INitroPool, IXGrailTokenUsage, IDividendsV2 } from "./Camelot.sol";
import { ITokenMinter } from "./Common.sol";
import { IJonesLpStaker } from "./Interfaces.sol";
import "./NftTransferHandler.sol";

contract JonesLpStaker is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, NftTransferHandler, IJonesLpStaker {
  uint private constant XGRAIL_MAX_REDEEM_DURATION = 15552000;

  ICamelotPair public constant TOKEN = ICamelotPair(0x460c2c075340EbC19Cf4af68E5d83C194E7D21D0);
  INFTPool public constant NFT_POOL = INFTPool(0xE20cE7d800934eC568Fe94E135E84b1e919AbB2a);
  IDividendsV2 public constant DIVIDENDS = IDividendsV2(0x5422AA06a38fd9875fc2501380b40659fEebD3bB);
  address public constant XGRAIL = 0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b;
  address public constant GRAIL = 0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8;
  address public constant WETH_USDC_CLP = 0x84652bb2539513BAf36e225c930Fdd8eaa63CE27;

  ITokenMinter public GXP;
  mapping(address => bool) public isHandler;
  address public depositor;
  address public operator;
  address public dividendOperator;
  INitroPool public nitroPool;
  uint32 public lockedTokenId;
  uint32 public unlockedTokenId;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _gxp) public virtual initializer {
    TOKEN.approve(address(NFT_POOL), type(uint256).max);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    isHandler[msg.sender] = true;
    GXP = ITokenMinter(_gxp);
  }

  function stake(uint256 _amount) external {
    if (msg.sender != depositor) revert UNAUTHORIZED();
    NFT_POOL.addToPosition(unlockedTokenId, _amount);
  }

  function claimFees(address _claimTo) external returns (uint256 _gxpAmt, uint256 _grailAmt) {
    if (msg.sender != operator) revert UNAUTHORIZED();
    // xGRAIL custodied by this contract
    (_gxpAmt, _grailAmt) = _harvestRewards();

    IXGrailTokenUsage(XGRAIL).redeem(_gxpAmt, XGRAIL_MAX_REDEEM_DURATION);
    GXP.mint(_claimTo, _gxpAmt);
    IERC20(GRAIL).transfer(_claimTo, _grailAmt);
  }

  function claimDividends(address _claimTo) external returns (uint256 _gxpAmt, uint256 _clpAmt) {
    if (msg.sender != dividendOperator) revert UNAUTHORIZED();
    // xGRAIL custodied by this contract

    (_gxpAmt, _clpAmt) = _harvestDividends();
    IXGrailTokenUsage(XGRAIL).redeem(_gxpAmt, XGRAIL_MAX_REDEEM_DURATION);
    GXP.mint(_claimTo, _gxpAmt);
    IERC20(WETH_USDC_CLP).transfer(_claimTo, _clpAmt);
  }

  function _harvestRewards() private returns (uint256 xgrailAmt, uint256 grailAmt) {
    uint[] memory tokenIds = new uint[](2);
    tokenIds[0] = lockedTokenId;
    tokenIds[1] = unlockedTokenId;

    uint _xgBefore = IERC20(XGRAIL).balanceOf(address(this));
    uint _gBefore = IERC20(GRAIL).balanceOf(address(this));
    // harvest nftPool - xGRAIL, GRAIL
    NFT_POOL.harvestPositionsTo(tokenIds, address(this));
    // harvest nitroPool - xGRAIL, GRAIL
    nitroPool.harvest();

    unchecked {
      xgrailAmt = IERC20(XGRAIL).balanceOf(address(this)) - _xgBefore;
      grailAmt = IERC20(GRAIL).balanceOf(address(this)) - _gBefore;
    }
  }

  function _harvestDividends() private returns (uint256 xgrailAmt, uint256 clpAmt) {
    // harvest dividends - ETH-USDC LP, xGRAIL
    uint _xgBefore = IERC20(XGRAIL).balanceOf(address(this));
    uint _clpBefore = IERC20(WETH_USDC_CLP).balanceOf(address(this));
    DIVIDENDS.harvestAllDividends();

    unchecked {
      xgrailAmt = IERC20(XGRAIL).balanceOf(address(this)) - _xgBefore;
      clpAmt = IERC20(WETH_USDC_CLP).balanceOf(address(this)) - _clpBefore;
    }
  }

  /** HANDLER */
  function handleRedeem(uint _amount, uint _duration) external {
    if (isHandler[msg.sender] == false) revert FAILED('JonesLpStaker: !handler');

    if (_amount == 0) {
      _amount = IERC20(XGRAIL).balanceOf(address(this));
    }

    if (_duration == 0) {
      _duration = XGRAIL_MAX_REDEEM_DURATION;
    }

    IXGrailTokenUsage(XGRAIL).redeem(_amount, _duration);
  }

  function handleCancelRedeem(uint redeemIndex) external {
    if (isHandler[msg.sender] == false) revert FAILED('JonesLpStaker: !handler');
    IXGrailTokenUsage(XGRAIL).cancelRedeem(redeemIndex);
  }

  function handleFinalizeRedeem(uint redeemIndex) external {
    if (isHandler[msg.sender] == false) revert FAILED('JonesLpStaker: !handler');
    IXGrailTokenUsage(XGRAIL).finalizeRedeem(redeemIndex);
  }

  /** OWNER NFTPOOL FUNCTIONS */
  function stakeNitro(uint _tokenId) external onlyOwner {
    transferNft(address(NFT_POOL), address(nitroPool), _tokenId);
  }

  function unstakeNitro(uint _tokenId) external onlyOwner {
    nitroPool.withdraw(_tokenId);
  }

  function relockPosition(uint _lockDuration) external onlyOwner {
    NFT_POOL.lockPosition(lockedTokenId, _lockDuration);
  }

  function setNitroPool(address _newNitroPool) external onlyOwner {
    emit NitroPoolChanged(_newNitroPool, address(nitroPool));
    nitroPool = INitroPool(_newNitroPool);
  }

  function setTokenIds(uint32 locked, uint32 unlocked) external onlyOwner {
    lockedTokenId = locked;
    unlockedTokenId = unlocked;
  }

  /** OWNER FUNCTIONS */
  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function updaterHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function recoverSpNft(uint _tokenId) external onlyOwner {
    transferNft(address(NFT_POOL), owner(), _tokenId);
  }

  function setOperator(address _newOperator) external onlyOwner {
    emit OperatorChanged(_newOperator, operator);
    operator = _newOperator;
  }

  function setDividendOperator(address _newDividendOperator) external onlyOwner {
    emit DividendOperatorChanged(_newDividendOperator, dividendOperator);
    dividendOperator = _newDividendOperator;
  }

  function setDepositor(address _newDepositor) external onlyOwner {
    emit DepositorChanged(_newDepositor, depositor);
    depositor = _newDepositor;
  }

  event HandlerUpdated(address _address, bool _isActive);
  event OperatorChanged(address indexed _new, address _old);
  event DividendOperatorChanged(address indexed _new, address _old);
  event DepositorChanged(address indexed _new, address _old);
  event NitroPoolChanged(address indexed _new, address _old);

  error UNAUTHORIZED();
  error INVALID_FEE();
}

