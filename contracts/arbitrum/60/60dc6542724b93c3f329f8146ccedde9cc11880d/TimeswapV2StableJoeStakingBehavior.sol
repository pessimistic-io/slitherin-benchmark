// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {FullMath} from "./FullMath.sol";
import {TimeswapV2OptionPosition} from "./structs_Position.sol";
import {TimeswapV2TokenPosition} from "./structs_Position.sol";
import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";
import {ITimeswapV2StableJoeStakingBehavior} from "./ITimeswapV2StableJoeStakingBehavior.sol";
import {TimeswapV2Behavior} from "./TimeswapV2Behavior.sol";
import {IStableJoeStaking} from "./IStableJoeStaking.sol";

contract TimeswapV2StableJoeStakingBehavior is ITimeswapV2StableJoeStakingBehavior, TimeswapV2Behavior {
    using SafeERC20 for IERC20;

    /// @notice The farming master contract
    IStableJoeStaking public immutable stableJoeStakingFarm;
    /// @notice The reward token
    IERC20 public immutable rewardToken;
    /// @notice The staking token for joe
    IERC20 public immutable joeToken;
    /// @notice The reward growth
    uint256 private _rewardGrowth;

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
        address _stableJoeStaking,
        address _rewardToken
    )
        TimeswapV2Behavior(
            _timeswapV2Token,
            _timeswapV2LendGivenPrincipal,
            _timeswapV2CloseLendGivenPosition,
            _timeswapV2Withdraw,
            _timeswapV2BorrowGivenPrincipal,
            _timeswapV2CloseBorrowGivenPosition,
            "TimeswapV2_StableJoeStaking_Position",
            "TimeswapV2_StakedJoe",
            ""
        )
    {
        require(_stableJoeStaking != address(0), "TimeswapV2StableJoeStakingBehavior: stableJoeStaking can't be address(0)");
        require(_rewardToken != address(0), "TimeswapV2StableJoeStakingBehavior:  rewardToken can't be address(0)");

        stableJoeStakingFarm = IStableJoeStaking(_stableJoeStaking);
        rewardToken = IERC20(_rewardToken);
        joeToken = IERC20(stableJoeStakingFarm.joe());
    }

    function mint(address to, uint256 amount) external {
        // Perform the mint requirement checks and actions
        _mintRequirement(amount);
        // Mint the tokens to the specified address
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        // Perform the burn requirement checks and actions
        _burnRequirement(to, amount);
        // Burn the tokens from the caller
        _burn(msg.sender, amount);
    }

    /// @notice Get the reward amount for a user
    function pendingReward(address token, uint256 strike, uint256 maturity) external view returns (uint256 amount) {
        bytes32 poolKey = keccak256(abi.encodePacked(token, strike, maturity));

        uint256 rewardGrowth;

        if ((maturity > block.timestamp) || ((maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured))) {
            // Get the pending reward from the farming contract
            uint256 rewardHarvested = stableJoeStakingFarm.pendingReward(address(this), address(rewardToken));

            {
                // Get the total staked JOE tokens
                (uint256 totalStakedLPToken,) = stableJoeStakingFarm.getUserInfo(address(this), address(rewardToken));

                rewardGrowth = _rewardGrowth + (totalStakedLPToken != 0 ? FullMath.mulDiv(rewardHarvested, 1 << 128, totalStakedLPToken, false) : 0);
            }
        } else {
            rewardGrowth = _poolRewardGrowths[poolKey].rewardGrowth;
        }

        {
            // Generate a unique key for the reward position
            bytes32 key = keccak256(abi.encodePacked(token, strike, maturity, msg.sender));
            // Get the reward position for the user
            RewardPosition memory rewardPosition = _rewardPositions[key];

            // Generate a unique ID for the position
            uint256 id = uint256(keccak256(abi.encodePacked(token, strike, maturity, address(this) < token ? PositionType.Long0 : PositionType.Long1)));

            // Calculate the accumulated reward amount for the user
            amount = rewardPosition.rewardAccumulated + FullMath.mulDiv(rewardGrowth - rewardPosition.rewardGrowth, balanceOf(msg.sender, id), 1 << 128, false);
        }
    }

    function harvest(address token, uint256 strike, uint256 maturity, address to) external returns (uint256 amount) {
        // Generate a unique key for the pool using keccak256 hash function
        bytes32 poolKey = keccak256(abi.encodePacked(token, strike, maturity));

        // Check if the maturity timestamp is in the future or if the pool has not matured yet
        if ((maturity > block.timestamp) || ((maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured))) {
            _update(token, strike, maturity, poolKey);
        }

        {
            uint256 rewardGrowth = maturity > block.timestamp ? _rewardGrowth : _poolRewardGrowths[poolKey].rewardGrowth;
            // Determine the reward growth based on the maturity timestamp

            {
                // Generate a unique key for the reward position using keccak256 hash function
                bytes32 key = keccak256(abi.encodePacked(token, strike, maturity, msg.sender));

                // Retrieve the reward position from the mapping
                RewardPosition storage rewardPosition = _rewardPositions[key];

                // Generate a unique ID for the position using keccak256 hash function
                uint256 id = uint256(keccak256(abi.encodePacked(token, strike, maturity, address(this) < token ? PositionType.Long0 : PositionType.Long1)));

                // Set the `amount` to the accumulated reward
                amount = rewardPosition.rewardAccumulated + FullMath.mulDiv(rewardGrowth - rewardPosition.rewardGrowth, balanceOf(msg.sender, id), 1 << 128, false);
                rewardPosition.rewardGrowth = rewardGrowth;

                delete rewardPosition.rewardAccumulated;

                // Transfer the accumulated reward to the specified address
                rewardToken.safeTransfer(to, amount);
            }
        }
    }

    function _mintRequirement(uint256 tokenAmount) internal override {
        // Transfer `tokenAmount` of JOE tokens from the caller to the contract
        joeToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
    }

    // @audit-todo : behavior contract must have sufficient JOe tokens to transfer to the user
    function _burnRequirement(address to, uint256 tokenAmount) internal override {
        // Transfer `tokenAmount` of JOE tokens from the contract to the specified address
        joeToken.safeTransfer(to, tokenAmount);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal override {
        // Call the base contract's `_beforeTokenTransfer` function
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        // Loop through the `ids` array
        for (uint256 i; i < ids.length;) {
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
            ((positionParam.maturity > block.timestamp) && (positionParam.positionType == (address(this) < positionParam.token ? PositionType.Long0 : PositionType.Long1)))
                || ((positionParam.maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured))
        ) {
            _update(positionParam.token, positionParam.strike, positionParam.maturity, poolKey);
        }

        // If the position type matches the token order, update the reward positions
        if (positionParam.positionType == (address(this) < positionParam.token ? PositionType.Long0 : PositionType.Long1)) {
            uint256 rewardGrowth;
            if (positionParam.maturity > block.timestamp) {
                rewardGrowth = _rewardGrowth;
                // Check if the `from` address is the zero address (mint)
                if (from == address(0)) {
                    // Check the allowance and approve the farming contract if needed
                    uint256 allowance = joeToken.allowance(address(this), address(stableJoeStakingFarm));
                    if (allowance < tokenAmount) joeToken.approve(address(stableJoeStakingFarm), type(uint256).max);
                    // Deposit the JOE tokens to the farming contract
                    stableJoeStakingFarm.deposit(tokenAmount);
                }
                // Check if the `to` address is the zero address (burn)
                // Withdraw the JOE tokens from the farming contract to the contract
                if (to == address(0)) stableJoeStakingFarm.withdraw(tokenAmount);
            } else {
                rewardGrowth = _poolRewardGrowths[poolKey].rewardGrowth;
            }

            // Update the reward positions for the `from` address
            if (from != address(0)) {
                bytes32 key = keccak256(abi.encodePacked(positionParam.token, positionParam.strike, positionParam.maturity, from));
                RewardPosition storage rewardPosition = _rewardPositions[key];

                rewardPosition.rewardAccumulated += FullMath.mulDiv(rewardGrowth - rewardPosition.rewardGrowth, balanceOf(from, id), 1 << 128, false);

                rewardPosition.rewardGrowth = rewardGrowth;
            }

            // Update the reward positions for the `to` address
            if (to != address(0)) {
                bytes32 key = keccak256(abi.encodePacked(positionParam.token, positionParam.strike, positionParam.maturity, to));
                RewardPosition storage rewardPosition = _rewardPositions[key];

                rewardPosition.rewardAccumulated += FullMath.mulDiv(rewardGrowth - rewardPosition.rewardGrowth, balanceOf(to, id), 1 << 128, false);

                rewardPosition.rewardGrowth = rewardGrowth;
            }
        }
    }

    function _update(address token, uint256 strike, uint256 maturity, bytes32 poolKey) private {
        uint256 rewardHarvested;
        {
            // Get the balance of the reward token before harvesting
            uint256 rewardBefore = rewardToken.balanceOf(address(this));

            // Call the `deposit` function on the `StablJoeStaking` contract -- harvest reward
            stableJoeStakingFarm.deposit(0);

            // Calculate the harvested reward amount
            rewardHarvested = rewardToken.balanceOf(address(this)) - rewardBefore;
        }

        {
            // Get the total amount of staked JOE tokens
            (uint256 totalStakedLPToken,) = stableJoeStakingFarm.getUserInfo(address(this), address(rewardToken));

            // Update the reward growth based on the harvested reward and staked JOE tokens
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
                stableJoeStakingFarm.withdraw(longPosition);
            }
        }
    }

    function update(address token, uint256 strike, uint256 maturity) external {
        bytes32 poolKey = keccak256(abi.encodePacked(token, strike, maturity));

        require(((maturity <= block.timestamp) && (!_poolRewardGrowths[poolKey].hasMatured)));

        _update(token, strike, maturity, poolKey);
    }
}

