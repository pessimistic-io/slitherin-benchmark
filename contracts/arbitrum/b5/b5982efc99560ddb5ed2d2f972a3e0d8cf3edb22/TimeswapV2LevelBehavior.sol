// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ERC1155} from "./ERC1155.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {FullMath} from "./FullMath.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";
import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {IFarmingLevelMasterV2} from "./IFarmingLevelMasterV2.sol";
import {ITimeswapV2LevelBehavior} from "./ITimeswapV2LevelBehavior.sol";

import {TimeswapV2Behavior} from "./TimeswapV2Behavior.sol";

contract TimeswapV2LevelBehavior is ITimeswapV2LevelBehavior, TimeswapV2Behavior {
  using SafeERC20 for IERC20;

  address public immutable farmingMaster;
  IERC20 public immutable rewardToken;
  uint256 public immutable pid;
  address public immutable seniorToken;

  uint256 private _rewardGrowth;

  struct RewardPosition {
    uint256 rewardGrowth;
    uint256 rewardAccumulated;
  }

  mapping(bytes32 => RewardPosition) private _rewardPositions;

  constructor(
    address _timeswapV2Token,
    address _timeswapV2LendGivenPrincipal,
    address _timeswapV2CloseLendGivenPosition,
    address _timeswapV2Withdraw,
    address _timeswapV2BorrowGivenPrincipal,
    address _timeswapV2CloseBorrowGivenPosition,
    address _farmingMaster,
    uint256 _pid
  )
    TimeswapV2Behavior(
      _timeswapV2Token,
      _timeswapV2LendGivenPrincipal,
      _timeswapV2CloseLendGivenPosition,
      _timeswapV2Withdraw,
      _timeswapV2BorrowGivenPrincipal,
      _timeswapV2CloseBorrowGivenPosition
    )
    ERC1155("")
    ERC20("", "")
  {
    farmingMaster = _farmingMaster;
    rewardToken = IFarmingLevelMasterV2(_farmingMaster).rewardToken();
    pid = _pid;
    seniorToken = IFarmingLevelMasterV2(_farmingMaster).lpToken(_pid);
    // TimeswapV2Behavior.initialize();
  }

  function mint(address to, uint256 amount) external override {
    _mintRequirement(amount);
    _mint(to, amount);
  }

  function burn(address to, uint256 amount) external override {
    _burn(msg.sender, amount);
    _burnRequirement(to, amount);
  }

  function harvest(
    address token,
    uint256 strike,
    uint256 maturity,
    address to
  ) external override returns (uint256 amount) {
    uint256 rewardHarvested;
    {
      uint256 rewardBefore = rewardToken.balanceOf(address(this));
      IFarmingLevelMasterV2(farmingMaster).harvest(pid, address(this));
      rewardHarvested = rewardToken.balanceOf(address(this)) - rewardBefore;
    }

    {
      TimeswapV2TokenPosition memory position;
      position.token0 = address(this) < token ? address(this) : token;
      position.token1 = address(this) > token ? address(this) : token;
      position.strike = strike;
      position.maturity = maturity;
      position.position = address(this) < token ? TimeswapV2OptionPosition.Long0 : TimeswapV2OptionPosition.Long1;

      uint256 positionBalance = ITimeswapV2Token(timeswapV2Token).positionOf(address(this), position);
      if (positionBalance != 0) _rewardGrowth += FullMath.mulDiv(
        rewardHarvested,
        1 << 128, 
        positionBalance,
        false
      );
    }

    bytes32 key = keccak256(abi.encodePacked(token, strike, maturity, msg.sender));
    RewardPosition memory rewardPosition = _rewardPositions[key];

    amount =
      rewardPosition.rewardAccumulated +
      FullMath.mulDiv(
        _rewardGrowth - rewardPosition.rewardGrowth,
        balanceOf(
          msg.sender,
          positionId(token, strike, maturity, address(this) < token ? PositionType.Long0 : PositionType.Long1)
        ),
        1 << 128,
        false
      );
    rewardPosition.rewardGrowth = _rewardGrowth;
    delete rewardPosition.rewardAccumulated;

    rewardToken.safeTransfer(to, amount);
  }

  function _mintRequirement(uint256 tokenAmount) internal override {
    IERC20(seniorToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

    uint256 allowance = IERC20(seniorToken).allowance(address(this), farmingMaster);
    if (allowance < tokenAmount) IERC20(seniorToken).approve(farmingMaster, type(uint256).max);
    IFarmingLevelMasterV2(farmingMaster).deposit(pid, tokenAmount, address(this));
  }

  function _burnRequirement(address to, uint256 tokenAmount) internal override {
    IFarmingLevelMasterV2(farmingMaster).withdraw(pid, tokenAmount, to);
  }

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal override {
    super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

    for (uint256 i; i < ids.length; ) {
      if (amounts[i] != 0) _updateRewardPositions(from, to, ids[i], amounts[i]);

      unchecked {
        ++i;
      }
    }
  }

  function _updateRewardPositions(address from, address to, uint256 id, uint256 amount) private {
    PositionParam memory positionParam = positionParams(id);

    if (positionParam.positionType == (address(this) < positionParam.token ? PositionType.Long0 : PositionType.Long1)) {
      uint256 rewardHarvested;
      {
        uint256 rewardBefore = rewardToken.balanceOf(address(this));
        IFarmingLevelMasterV2(farmingMaster).harvest(pid, address(this));
        rewardHarvested = rewardToken.balanceOf(address(this)) - rewardBefore;
      }

      {
        TimeswapV2TokenPosition memory position;
        position.token0 = address(this) < positionParam.token ? address(this) : positionParam.token;
        position.token1 = address(this) > positionParam.token ? address(this) : positionParam.token;
        position.strike = positionParam.strike;
        position.maturity = positionParam.maturity;
        if (positionParam.positionType == PositionType.Long0) position.position = TimeswapV2OptionPosition.Long0;
        if (positionParam.positionType == PositionType.Long1) position.position = TimeswapV2OptionPosition.Long1;

        uint256 positionBalance = ITimeswapV2Token(timeswapV2Token).positionOf(address(this), position);
        if (from == address(0)) positionBalance -= amount;
        if (to == address(0)) positionBalance += amount;
        if (positionBalance != 0) _rewardGrowth += FullMath.mulDiv(rewardHarvested, 1 << 128, positionBalance, false);
      }

      if (from != address(0)) {
        bytes32 key = keccak256(
          abi.encodePacked(positionParam.token, positionParam.strike, positionParam.maturity, from)
        );
        RewardPosition storage rewardPosition = _rewardPositions[key];

        rewardPosition.rewardAccumulated += FullMath.mulDiv(
          _rewardGrowth - rewardPosition.rewardGrowth,
          balanceOf(from, id),
          1 << 128,
          false
        );
        rewardPosition.rewardGrowth = _rewardGrowth;
      }

      if (to != address(0)) {
        bytes32 key = keccak256(
          abi.encodePacked(positionParam.token, positionParam.strike, positionParam.maturity, to)
        );
        RewardPosition storage rewardPosition = _rewardPositions[key];

        rewardPosition.rewardAccumulated += FullMath.mulDiv(
          _rewardGrowth - rewardPosition.rewardGrowth,
          balanceOf(to, id),
          1 << 128,
          false
        );
        rewardPosition.rewardGrowth = _rewardGrowth;
      }
    }
  }
}

