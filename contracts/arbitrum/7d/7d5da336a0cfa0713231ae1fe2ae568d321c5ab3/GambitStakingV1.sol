//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./IGov.sol";

import "./GambitErrorsV1.sol";

abstract contract GambitStakingV1 is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32[63] private _gap0; // storage slot gap (1 slot for Initializeable)

    // Contracts & Addresses (constant)
    IGov public storageT; // We may need storageT.gov() for authentication in the future.
    IERC20Upgradeable public token; // CNG
    IERC20Upgradeable public usdc; // USDC
    address public treasury;

    bytes32[60] private _gap1; // storage slot gap (4 slots for above variables)

    // Pool state
    uint public accUsdcPerToken; // 1e24 (USDC) or 1e36 (DAI)
    uint public tokenBalance; // 1e18, CNG

    bytes32[62] private _gap2; // storage slot gap (2 slots for above variables)

    // Pool stats
    uint public totalRewardsDistributedUsdc; // 1e6 (USDC) or 1e18 (DAI)

    bytes32[63] private _gap3; // storage slot gap (1 slot for above variable)

    // Mappings
    mapping(address => User) public users;

    bytes32[63] private _gap4; // storage slot gap (1 slot for above variable)

    // Structs
    struct User {
        uint stakedTokens; // 1e18
        uint debtUsdc; // 1e6 (USDC) or 1e18 (DAI)
        uint harvestedRewardsUsdc; // 1e6 (USDC) or 1e18 (DAI)
        // gap for future upgrade
        bytes32 _gap0; // storage slot gap
        bytes32 _gap1; // storage slot gap
        bytes32 _gap2; // storage slot gap
    }

    // Events
    event UsdcDistributed(uint amount);
    event UsdcHarvested(address indexed user, uint amount);

    event TreasuryUpdated(address indexed treasury);

    event TokensStaked(address indexed user, uint amount);
    event TokensUnstaked(address indexed user, uint amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IGov _storageT,
        IERC20Upgradeable _token,
        IERC20Upgradeable _usdc,
        address _treasury
    ) external initializer {
        if (
            address(_storageT) == address(0) ||
            address(_token) == address(0) ||
            address(_usdc) == address(0) ||
            _treasury == address(0)
        ) revert GambitErrorsV1.WrongParams();

        if (
            IERC20MetadataUpgradeable(address(_usdc)).decimals() !=
            usdcDecimals()
        ) revert GambitErrorsV1.StablecoinDecimalsMismatch();

        storageT = _storageT;
        token = _token;
        usdc = _usdc;
        treasury = _treasury;
    }

    // Manage Treasury
    function updateTreasury(address _treasury) external {
        if (msg.sender != storageT.gov()) revert GambitErrorsV1.NotGov();
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    // Distribute rewards
    function distributeRewardUsdc(
        uint amount // 1e6 (USDC) or 1e18 (DAI)
    ) external {
        if (tokenBalance > 0) {
            accUsdcPerToken += (amount * 1e36) / tokenBalance; // 1e24 (USDC) or 1e36 (DAI);
            totalRewardsDistributedUsdc += amount;
            usdc.safeTransferFrom(msg.sender, address(this), amount);
        } else {
            usdc.safeTransferFrom(msg.sender, treasury, amount);
        }

        emit UsdcDistributed(amount);
    }

    // Rewards to be harvested
    function pendingRewardUsdc(
        address sender
    )
        public
        view
        returns (
            uint // 1e6 (USDC) or 1e18 (DAI)
        )
    {
        User memory u = users[sender];

        return
            (u.stakedTokens * accUsdcPerToken) / // 1e42 (USDC) or 1e54 (DAI)
            1e36 - // 1e6 (USDC) or 1e18 (DAI)
            u.debtUsdc;
    }

    // Harvest rewards
    function harvest() public {
        uint pendingUsdc = pendingRewardUsdc(msg.sender); // 1e6 (USDC) or 1e18 (DAI)

        User storage u = users[msg.sender];
        u.debtUsdc =
            (u.stakedTokens * accUsdcPerToken) / // 1e42 (USDC) or 1e54 (DAI)
            1e36; // 1e6 (USDC) or 1e18 (DAI)
        u.harvestedRewardsUsdc += pendingUsdc; // 1e6 (USDC) or 1e18 (DAI)

        usdc.safeTransfer(msg.sender, pendingUsdc);

        emit UsdcHarvested(msg.sender, pendingUsdc);
    }

    // Stake tokens
    function stakeTokens(
        uint amount // 1e18
    ) external {
        User storage u = users[msg.sender];

        harvest();

        u.stakedTokens += amount;
        u.debtUsdc = (u.stakedTokens * accUsdcPerToken) / 1e36; // 1e6 (USDC) or 1e18 (DAI)
        tokenBalance += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit TokensStaked(msg.sender, amount);
    }

    // Unstake tokens
    function unstakeTokens(
        uint amount // 1e18
    ) external {
        User storage u = users[msg.sender];

        harvest();

        u.stakedTokens -= amount;
        u.debtUsdc = (u.stakedTokens * accUsdcPerToken) / 1e36; // 1e6 (USDC) or 1e18 (DAI)
        tokenBalance -= amount;

        token.safeTransfer(msg.sender, amount);
        emit TokensUnstaked(msg.sender, amount);
    }

    function usdcDecimals() public pure virtual returns (uint8);
}

/**
 * @dev GambitStakingV1 with stablecoin decimals set to 6.
 */
contract GambitStakingV1____6 is GambitStakingV1 {
    function usdcDecimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @dev GambitStakingV1 with stablecoin decimals set to 18.
 */
contract GambitStakingV1____18 is GambitStakingV1 {
    function usdcDecimals() public pure override returns (uint8) {
        return 18;
    }
}

