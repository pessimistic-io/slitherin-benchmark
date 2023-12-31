// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPositionManager} from "./IPositionManager.sol";
import {ERC20} from "./ERC20.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {ILeveragedPool} from "./ILeveragedPool.sol";
import {IPoolCommitter} from "./IPoolCommitter.sol";
import {PerpPoolUtils} from "./PerpPoolUtils.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {PositionType} from "./PositionType.sol";
import {ProtohedgeVault} from "./ProtohedgeVault.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract PerpPoolPositionManager is IPositionManager, Initializable, UUPSUpgradeable, OwnableUpgradeable {
  string private positionName;
  ERC20 private poolToken;
  PriceUtils private priceUtils;
  ILeveragedPool private leveragedPool;
  IPoolCommitter private poolCommitter;
  ERC20 private usdcToken; 
  PerpPoolUtils private perpPoolUtils;
  ProtohedgeVault private protohedgeVault;

  uint256 private constant USDC_MULTIPLIER = 1*10**6; 
  uint256 private _costBasis;
  ERC20 private trackingToken;
  uint256 private lastIntervalId;
  bool private _canRebalance;

	function initialize(
    string memory _positionName,
    address _poolTokenAddress,
    address _priceUtilsAddress,
    address _leveragedPoolAddress,
    address _trackingTokenAddress,
    address _poolCommitterAddress,
    address _usdcAddress,
    address _perpPoolUtilsAddress,
    address _protohedgeVaultAddress 
  ) public initializer {
    poolToken = ERC20(_poolTokenAddress);
    priceUtils = PriceUtils(_priceUtilsAddress);
    leveragedPool = ILeveragedPool(_leveragedPoolAddress);
    trackingToken = ERC20(_trackingTokenAddress);
    poolCommitter = IPoolCommitter(_poolCommitterAddress);
    usdcToken = ERC20(_usdcAddress);
    perpPoolUtils = PerpPoolUtils(_perpPoolUtilsAddress);
    protohedgeVault = ProtohedgeVault(_protohedgeVaultAddress);
    positionName = _positionName;
    _canRebalance = true;

    __Ownable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function name() override public view returns (string memory) {
    return positionName;
  }

  function positionWorth() override public view returns (uint256) {
    uint256 claimedUsdcWorth = perpPoolUtils.getClaimedUsdcWorth(address(poolToken), address(this), address(leveragedPool));
    uint256 committedUsdcWorth = perpPoolUtils.getCommittedUsdcWorth(address(poolCommitter), address(this));

    return claimedUsdcWorth + committedUsdcWorth;
  }

  function costBasis() override public view returns (uint256) {
    return _costBasis; 
  }

  function pnl() override external view returns (int256) {
    return int256(positionWorth()) - int256(costBasis());
  }

  function buy(uint256 usdcAmount) override external returns (uint256) {
    bytes32 commitParams = perpPoolUtils.encodeCommitParams(usdcAmount, IPoolCommitter.CommitType.ShortMint, false, false);
    usdcToken.transferFrom(address(protohedgeVault), address(this), usdcAmount);
    usdcToken.approve(address(leveragedPool), usdcAmount);
    poolCommitter.commit(commitParams);

    _costBasis += usdcAmount;
    return usdcAmount;
  }

  function sell(uint256 usdcAmount) override external returns (uint256) {
    uint256 tokensToSell = usdcAmount * this.price() / USDC_MULTIPLIER;
    bytes32 commitParams = perpPoolUtils.encodeCommitParams(tokensToSell, IPoolCommitter.CommitType.ShortBurn, false, false);
    poolCommitter.commit(commitParams);
    _costBasis -= usdcAmount;

    return tokensToSell;
  }

  function exposures() override external view returns (TokenExposure[] memory) {
    TokenExposure[] memory tokenExposures = new TokenExposure[](1);
    tokenExposures[0] = TokenExposure({
      amount: -1 * int256(positionWorth()) * 3,
      token: address(trackingToken),
      symbol: trackingToken.symbol()
    });

    return tokenExposures;
  }

  function allocation() override external view returns (TokenAllocation[] memory) {
    TokenAllocation[] memory tokenAllocations = new TokenAllocation[](1);
    tokenAllocations[0] = TokenAllocation({
      tokenAddress: address(trackingToken),
      symbol: trackingToken.symbol(),
      percentage: 10000,
      leverage: 3,
      positionType: PositionType.Short 
    });
    return tokenAllocations;
  }

  function price() override external view returns (uint256) {
    return priceUtils.perpPoolTokenPrice(address(leveragedPool), PositionType.Short);
  }

  function claim() external {
    uint256 amountOfClaimedTokens = poolToken.balanceOf(address(this));
    poolCommitter.claim(address(this));
    uint256 amountOfClaimedTokensAfter = poolToken.balanceOf(address(this));

    if (amountOfClaimedTokensAfter > amountOfClaimedTokens && !this.canRebalance()) {
      _canRebalance = true; 
    }
  }

  function compound() override external {}

  function canRebalance() override external view returns (bool) {
    return _canRebalance;
  }
}

