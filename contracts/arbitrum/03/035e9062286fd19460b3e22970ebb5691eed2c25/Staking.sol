// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;

import "./SafeCast.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Multicall.sol";

contract Staking is Multicall {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @notice The time interval for redeeming staking
    uint96 public constant REDEEM_DELAY_INTERVAL = 1 days;

    struct Info {
        /// @dev The owner of the staking
        address owner;
        /// @dev The amount of staking
        uint96 amount;
        /// @dev The time when the staking can be redeemed
        uint96 redeemableTime;
    }

    /// @notice Emitted when a staking is created
    /// @param id The id of the staking
    /// @param owner The owner of the staking
    /// @param amount The amount of staking
    event Stake(uint256 indexed id, address indexed owner, uint96 amount);

    /// @notice Emitted when a staking is unstaked
    /// @param id The id of the staking
    /// @param redeemableTime The time when the staking can be redeemed
    event Unstake(uint256 indexed id, uint96 redeemableTime);

    /// @notice Emitted when a staking is redeemed
    /// @param id The id of the staking
    event Redeem(uint256 indexed id);

    /// @notice The token to be staked
    IERC20 public immutable token;

    uint256 private _stakingId;

    /// @notice The mapping of staking id to staking info
    mapping(uint256 => Info) public stakingInfos;

    constructor(IERC20 _token) {
        token = _token;
    }

    /// @notice Stake the token
    /// @param amount The amount of token to be staked
    /// @return The id of the staking
    function stake(uint96 amount) external returns (uint256) {
        require(amount > 0, "Staking: amount must be greater than 0");

        token.safeTransferFrom(msg.sender, address(this), uint256(amount));

        _stakingId++;
        stakingInfos[_stakingId] = Info({
            owner: msg.sender,
            amount: amount,
            redeemableTime: 0
        });

        emit Stake(_stakingId, msg.sender, amount);

        return _stakingId;
    }

    /// @notice Unstake the token
    /// @param id The id of the staking
    function unstake(uint256 id) external {
        Info storage info = stakingInfos[id];
        require(info.owner == msg.sender, "Staking: not owner");
        require(info.redeemableTime == 0, "Staking: already unstaked");
        info.redeemableTime =
            block.timestamp.toUint96() +
            REDEEM_DELAY_INTERVAL;

        emit Unstake(id, info.redeemableTime);
    }

    /// @notice Redeem the token
    /// @param id The id of the staking
    function redeem(uint256 id) external {
        Info memory info = stakingInfos[id];
        require(info.owner == msg.sender, "Staking: not owner");
        require(info.redeemableTime != 0, "Staking: not unstaked");
        require(
            info.redeemableTime <= block.timestamp,
            "Staking: not redeemable"
        );

        delete stakingInfos[id];

        token.safeTransfer(msg.sender, uint256(info.amount));

        emit Redeem(id);
    }
}

