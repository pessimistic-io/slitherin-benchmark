// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {ERC1155} from "./ERC1155.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {FullMath} from "./FullMath.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";
import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {IStableJoeStaking} from "./IStableJoeStaking.sol";
import {ITimeswapV2StableJoeStakingBehavior} from "./ITimeswapV2StableJoeStakingBehavior.sol";
// import "forge-std/console.sol";

import {TimeswapV2Behavior} from "./TimeswapV2Behavior.sol";

contract TimeswapV2StableJoeStakingBehavior is ITimeswapV2StableJoeStakingBehavior, TimeswapV2Behavior {
  using SafeERC20 for IERC20;

  /// @notice The farming master contract
  address public immutable stableJoeStakingProxy;
  /// @notice The reward token
  IERC20 public immutable rewardToken;
  // /// @notice The tranche id for level
  // uint256 public immutable pid;
  /// @notice The staking token for joe
  address public immutable joeToken;
  /// @notice The reward growth
  uint256 private _rewardGrowth;

  uint256 public immutable ACC_REWARD_PER_SHARE_PRECISION;

  /// @notice The reward position to accumulate the rewards from staked level tokens
  struct RewardPosition {
    uint256 rewardGrowth;
    uint256 rewardAccumulated;
  }

  /// @notice The reward positions mapping to a user
  mapping(bytes32 => RewardPosition) private _rewardPositions;

  struct PoolRewardGrowth {
    bool hasMatured;
    uint256 rewardGrowth;
  }

  mapping(bytes32 => PoolRewardGrowth) private _poolRewardGrowths;

  constructor(
    address _timeswapV2Token,
    address _timeswapV2LendGivenPrincipal,
    address _timeswapV2CloseLendGivenPosition,
    address _timeswapV2Withdraw,
    address _timeswapV2BorrowGivenPrincipal,
    address _timeswapV2CloseBorrowGivenPosition,
    address _stableJoeStakingProxy,
    address _rewardToken
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
    ACC_REWARD_PER_SHARE_PRECISION = IStableJoeStaking(_stableJoeStakingProxy).ACC_REWARD_PER_SHARE_PRECISION();
    stableJoeStakingProxy = _stableJoeStakingProxy;
    joeToken = IStableJoeStaking(_stableJoeStakingProxy).joe();
    rewardToken = IERC20(_rewardToken);
  }

  function mint(address to, uint256 amount) external {
    // Perform the mint requirement checks and actions
    _mintRequirement(amount);
    // Mint the tokens to the specified address
    _mint(to, amount);
  }

  function burn(address to, uint256 amount) external {
    // Burn the tokens from the caller
    _burn(msg.sender, amount);
    // Perform the burn requirement checks and actions
    _burnRequirement(to, amount);
  }

  /// @notice Get the reward amount for a user
  function pendingReward(address token, uint256 strike, uint256 maturity) external view returns (uint256 amount) {
    bytes32 poolKey = keccak256(abi.encodePacked(token, strike, maturity));

    uint256 rewardGrowth;
    uint256 poolRewardGrowth;

    if ((maturity > block.timestamp) || ((maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured))) {
      // Get the pending reward from the farming contract
      //   pending reward = (user.amount * accRewardPerShare) - user.rewardDebt[token]

      {
        // Calculate the total staked LP tokens
        (uint256 totalStakedLPToken, uint256 rewardDebt) = IStableJoeStaking(stableJoeStakingProxy).getUserInfo(
          address(this),
          address(rewardToken)
        );
        uint256 accRewardPerShare = IStableJoeStaking(stableJoeStakingProxy).accRewardPerShare(address(rewardToken));

        uint256 rewardHarvested = FullMath.mulDiv(
          totalStakedLPToken,
          accRewardPerShare,
          ACC_REWARD_PER_SHARE_PRECISION,
          false
        ) - rewardDebt;

        if (totalStakedLPToken != 0) {
          // Calculate the updated reward growth based on the harvested reward
          rewardGrowth = _rewardGrowth + FullMath.mulDiv(rewardHarvested, 1 << 128, totalStakedLPToken, false);
        }
      }
      if ((maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured)) {
        // If the pool has matured and not marked as matured yet, use the current reward growth
        poolRewardGrowth = rewardGrowth;
      } else {
        // Otherwise, use the reward growth stored in the pool reward growth mapping
        poolRewardGrowth = _poolRewardGrowths[poolKey].rewardGrowth;
      }
    }

    if (maturity <= block.timestamp) {
      // If the maturity has passed, use the pool reward growth for the reward calculation
      rewardGrowth = poolRewardGrowth;
    }

    {
      // Generate a unique key for the reward position
      bytes32 key = keccak256(abi.encodePacked(token, strike, maturity, msg.sender));
      // Get the reward position for the user
      RewardPosition memory rewardPosition = _rewardPositions[key];

      // Generate a unique ID for the position
      uint256 id = uint256(
        keccak256(
          abi.encodePacked(token, strike, maturity, address(this) < token ? PositionType.Long0 : PositionType.Long1)
        )
      );

      // Calculate the accumulated reward amount for the user
      amount =
        rewardPosition.rewardAccumulated +
        FullMath.mulDiv(rewardGrowth - rewardPosition.rewardGrowth, balanceOf(msg.sender, id), 1 << 128, false);
    }
  }

  function harvest(address token, uint256 strike, uint256 maturity, address to) external returns (uint256 amount) {
    // Generate a unique key for the pool using keccak256 hash function
    bytes32 poolKey = keccak256(abi.encodePacked(token, strike, maturity));

    // Check if the maturity timestamp is in the future or if the pool has not matured yet
    if ((maturity > block.timestamp) || ((maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured))) {
      uint256 rewardHarvested;
      {
        // Get the balance of the reward token before harvesting
        uint256 rewardBefore = rewardToken.balanceOf(address(this));

        // Call the `harvest` function on the `IFarmingLevelMasterV2` contract
        IStableJoeStaking(stableJoeStakingProxy).deposit(0);

        // Calculate the harvested reward amount
        rewardHarvested = rewardToken.balanceOf(address(this)) - rewardBefore;
      }

      {
        // Get the total amount of staked LP tokens
        (uint256 totalStakedLPToken, ) = IStableJoeStaking(stableJoeStakingProxy).getUserInfo(
          address(this),
          address(rewardToken)
        );

        // Update the reward growth based on the harvested reward and staked LP tokens
        if (totalStakedLPToken != 0) {
          _rewardGrowth += FullMath.mulDiv(rewardHarvested, 1 << 128, totalStakedLPToken, false);
        }
      }

      // If the pool has matured and not marked as matured yet, perform additional actions
      if ((maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured)) {
        // Mark the pool as matured and set the reward growth
        _poolRewardGrowths[poolKey].hasMatured = true;
        _poolRewardGrowths[poolKey].rewardGrowth = _rewardGrowth;

        {
          TimeswapV2TokenPosition memory position;
          // Determine the token order for the position
          position.token0 = address(this) < token ? address(this) : token;
          position.token1 = address(this) > token ? address(this) : token;
          position.strike = strike;
          position.maturity = maturity;
          // Determine the position type based on the token order
          position.position = address(this) < token ? TimeswapV2OptionPosition.Long0 : TimeswapV2OptionPosition.Long1;

          // Get the long position ID from the TimeswapV2Token contract
          uint256 longPosition = ITimeswapV2Token(timeswapV2Token).positionOf(address(this), position);

          // Withdraw the long position from the farming contract
          IStableJoeStaking(stableJoeStakingProxy).withdraw(longPosition);
        }
      }
    }

    {
      uint256 rewardGrowth;
      // Determine the reward growth based on the maturity timestamp
      if (maturity > block.timestamp) {
        rewardGrowth = _rewardGrowth;
      } else {
        rewardGrowth = _poolRewardGrowths[poolKey].rewardGrowth;
      }

      {
        // Generate a unique key for the reward position using keccak256 hash function
        bytes32 key = keccak256(abi.encodePacked(token, strike, maturity, msg.sender));

        // Retrieve the reward position from the mapping
        RewardPosition storage rewardPosition = _rewardPositions[key];

        // Generate a unique ID for the position using keccak256 hash function
        uint256 id = uint256(
          keccak256(
            abi.encodePacked(token, strike, maturity, address(this) < token ? PositionType.Long0 : PositionType.Long1)
          )
        );

        // Update the reward accumulation based on the reward growth, user balance, and scaling factor
        rewardPosition.rewardAccumulated += FullMath.mulDiv(
          rewardGrowth - rewardPosition.rewardGrowth,
          balanceOf(msg.sender, id),
          1 << 128,
          false
        );
        rewardPosition.rewardGrowth = rewardGrowth;

        // Set the `amount` to the accumulated reward
        amount = rewardPosition.rewardAccumulated;
        delete rewardPosition.rewardAccumulated;

        // Transfer the accumulated reward to the specified address
        rewardToken.safeTransfer(to, amount);
      }
    }
  }

  function _mintRequirement(uint256 tokenAmount) internal override {
    // Transfer `tokenAmount` of LP tokens from the caller to the contract
    IERC20(joeToken).safeTransferFrom(msg.sender, address(this), tokenAmount);
  }

  function _burnRequirement(address to, uint256 tokenAmount) internal override {
    // Transfer `tokenAmount` of LP tokens from the contract to the specified address
    IERC20(joeToken).safeTransfer(to, tokenAmount);
  }

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal override {
    // Call the base contract's `_beforeTokenTransfer` function
    super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

    // Loop through the `ids` array
    for (uint256 i; i < ids.length; ) {
      // If the `amounts[i]` is not zero, update the reward positions
      if (amounts[i] != 0) _updateRewardPositions(from, to, ids[i], amounts[i]);

      unchecked {
        ++i;
      }
    }
  }

  // function to update reward positions
  function _updateRewardPositions(address from, address to, uint256 id, uint256 tokenAmount) private {
    // Retrieve the position parameters for the given `id`
    PositionParam memory positionParam = positionParams(id);
    // Generate a unique key for the pool using keccak256 hash function
    bytes32 poolKey = keccak256(abi.encodePacked(positionParam.token, positionParam.strike, positionParam.maturity));
    // Check if the position is eligible for reward updates
    if (
      ((positionParam.maturity > block.timestamp) &&
        (positionParam.positionType ==
          (address(this) < positionParam.token ? PositionType.Long0 : PositionType.Long1))) ||
      ((positionParam.maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured))
    ) {
      uint256 rewardHarvested;
      {
        uint256 rewardBefore = rewardToken.balanceOf(address(this));
        // Harvest rewards from the farming contract to the contract ie deposit(0)
        IStableJoeStaking(stableJoeStakingProxy).deposit(0);
        rewardHarvested = rewardToken.balanceOf(address(this)) - rewardBefore;
      }
      {
        (uint256 totalStakedLPToken, ) = IStableJoeStaking(stableJoeStakingProxy).getUserInfo(
          address(this),
          address(rewardToken)
        );
        if (totalStakedLPToken != 0) {
          _rewardGrowth += FullMath.mulDiv(rewardHarvested, 1 << 128, totalStakedLPToken, false);
        }
      }
      // If the pool has matured and not marked as matured yet, perform additional actions
      if ((positionParam.maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured)) {
        _poolRewardGrowths[poolKey].hasMatured = true;
        _poolRewardGrowths[poolKey].rewardGrowth = _rewardGrowth;
        {
          TimeswapV2TokenPosition memory position;
          // Determine the token order for the position
          position.token0 = address(this) < positionParam.token ? address(this) : positionParam.token;
          position.token1 = address(this) > positionParam.token ? address(this) : positionParam.token;
          position.strike = positionParam.strike;
          position.maturity = positionParam.maturity;
          // Determine the position type based on the token order
          position.position = address(this) < positionParam.token
            ? TimeswapV2OptionPosition.Long0
            : TimeswapV2OptionPosition.Long1;
          // Get the long position ID from the TimeswapV2Token contract
          uint256 longPosition = ITimeswapV2Token(timeswapV2Token).positionOf(address(this), position);
          //  Withdraw the long position from the farming contract
          IStableJoeStaking(stableJoeStakingProxy).withdraw(longPosition);
        }
      }
    }
    //     // If the position type matches the token order, update the reward positions
    if (positionParam.positionType == (address(this) < positionParam.token ? PositionType.Long0 : PositionType.Long1)) {
      uint256 rewardGrowth;
      if (positionParam.maturity > block.timestamp) {
        rewardGrowth = _rewardGrowth;
        // Check if the `from` address is the zero address (mint)
        if (from == address(0)) {
          // Check the allowance and approve the farming contract if needed
          uint256 allowance = IERC20(joeToken).allowance(address(this), stableJoeStakingProxy);
          if (allowance < tokenAmount) IERC20(joeToken).approve(stableJoeStakingProxy, type(uint256).max);
          // Deposit the LP tokens to the farming contract
          IStableJoeStaking(stableJoeStakingProxy).deposit(tokenAmount);
          //   console.log("tokenAmount", tokenAmount);
        }
        // Check if the `to` address is the zero address (burn)
        if (to == address(0)) {
          // Withdraw the LP tokens from the farming contract to the contract
          IStableJoeStaking(stableJoeStakingProxy).withdraw(tokenAmount);
        }
      } else {
        rewardGrowth = _poolRewardGrowths[poolKey].rewardGrowth;
      }
      // Update the reward positions for the `from` address
      if (from != address(0)) {
        bytes32 key = keccak256(
          abi.encodePacked(positionParam.token, positionParam.strike, positionParam.maturity, from)
        );
        RewardPosition storage rewardPosition = _rewardPositions[key];
        rewardPosition.rewardAccumulated += FullMath.mulDiv(
          rewardGrowth - rewardPosition.rewardGrowth,
          balanceOf(from, id),
          1 << 128,
          false
        );
        rewardPosition.rewardGrowth = rewardGrowth;
      }
      // Update the reward positions for the `to` address
      if (to != address(0)) {
        bytes32 key = keccak256(
          abi.encodePacked(positionParam.token, positionParam.strike, positionParam.maturity, to)
        );
        RewardPosition storage rewardPosition = _rewardPositions[key];
        rewardPosition.rewardAccumulated += FullMath.mulDiv(
          rewardGrowth - rewardPosition.rewardGrowth,
          balanceOf(to, id),
          1 << 128,
          false
        );
        rewardPosition.rewardGrowth = rewardGrowth;
      }
    }
  }
}

