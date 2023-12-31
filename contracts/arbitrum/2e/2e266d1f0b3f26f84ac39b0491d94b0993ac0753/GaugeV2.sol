// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./IGaugeV2.sol";
import "./INonfungiblePositionManager.sol";
import "./IFeeCollector.sol";
import "./FullMath.sol";

import "./IRamsesV2Pool.sol";

import "./States.sol";

import "./Initializable.sol";
import "./SafeERC20.sol";
import "./Math.sol";

contract GaugeV2 is Initializable, IGaugeV2 {
    using SafeERC20 for IERC20;

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant PRECISION = 10 ** 18;

    bool internal _unlocked;

    address public gaugeFactory;
    IRamsesV2Pool public pool;
    address public voter;
    IFeeCollector public feeCollector;
    INonfungiblePositionManager public nfpManager;

    /// @inheritdoc IGaugeV2
    uint256 public firstPeriod;

    /// @inheritdoc IGaugeV2
    /// @dev period => token => total supply
    mapping(uint256 => mapping(address => uint256))
        public tokenTotalSupplyByPeriod;

    /// @inheritdoc IGaugeV2
    /// @dev period => total boosted seconds
    mapping(uint256 => uint256) public periodTotalBoostedSeconds;

    /// @dev period => position hash => bool
    mapping(uint256 => mapping(bytes32 => bool)) internal periodAmountsWritten;
    /// @dev period => position hash => seconds in range
    mapping(uint256 => mapping(bytes32 => uint256))
        internal periodNfpSecondsX96;
    /// @dev period => position hash => boosted seconds in range
    mapping(uint256 => mapping(bytes32 => uint256))
        internal periodNfpBoostedSecondsX96;

    /// @inheritdoc IGaugeV2
    /// @dev period => position hash => reward token => amount
    mapping(uint256 => mapping(bytes32 => mapping(address => uint256)))
        public periodClaimedAmount;

    // token => position hash => period
    /// @inheritdoc IGaugeV2
    mapping(address => mapping(bytes32 => uint256)) public lastClaimByToken;

    /// @inheritdoc IGaugeV2
    address[] public rewards;
    /// @inheritdoc IGaugeV2
    mapping(address => bool) public isReward;

    /// @dev Mutually exclusive reentrancy protection into the pool to/from a method. This method also prevents entrance
    /// to a function before the Gauge is initialized.
    modifier lock() {
        require(_unlocked, "LOK");
        _unlocked = false;
        _;
        _unlocked = true;
    }

    /// @dev pushes fees from the pool to fee distributor on notify rewards
    modifier pushFees() {
        feeCollector.collectProtocolFees(pool);
        _;
    }

    /// @dev disables the initializer
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IGaugeV2
    function initialize(
        address _gaugeFactory,
        address _voter,
        address _nfpManager,
        address _feeCollector,
        address _pool
    ) external override initializer {
        _unlocked = true;

        gaugeFactory = _gaugeFactory;
        voter = _voter;
        feeCollector = IFeeCollector(_feeCollector);
        nfpManager = INonfungiblePositionManager(_nfpManager);
        pool = IRamsesV2Pool(_pool);

        firstPeriod = _blockTimestamp() / WEEK;
    }

    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /// @inheritdoc IGaugeV2
    function left(address token) external view override returns (uint256) {
        uint256 period = _blockTimestamp() / WEEK;
        uint256 elapsedTime = _blockTimestamp() - period;
        return (tokenTotalSupplyByPeriod[period][token] * elapsedTime) / WEEK;
    }

    /// @inheritdoc IGaugeV2
    function rewardRate(address token) external view returns (uint256) {
        uint256 period = _blockTimestamp() / WEEK;
        return (tokenTotalSupplyByPeriod[period][token] * 4) / 10 / WEEK;
    }

    /// @inheritdoc IGaugeV2
    function getRewardTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return rewards;
    }

    /// @inheritdoc IGaugeV2
    function positionHash(
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, index, tickLower, tickUpper));
    }

    /// @inheritdoc IGaugeV2
    function positionInfo(
        uint256 tokenId
    )
        external
        view
        override
        returns (uint128 liquidity, uint128 boostedLiquidity)
    {
        uint256 period = _blockTimestamp() / WEEK;
        INonfungiblePositionManager _nfpManager = nfpManager;
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager
            .positions(tokenId);

        bytes32 _positionHash = positionHash(
            address(_nfpManager),
            tokenId,
            tickLower,
            tickUpper
        );

        States.PoolStates storage states = States.getStorage();

        PositionInfo storage positionData = states.positions[_positionHash];

        BoostInfo storage boostInfo = states.boostInfos[period].positions[
            _positionHash
        ];

        bytes32 liquiditySlot;
        bytes32 boostedLiquiditySlot;
        bytes32[] memory slots = new bytes32[](2);

        // define slots to read
        // both slots are in the 0th slot of the struct
        assembly {
            liquiditySlot := positionData.slot
            boostedLiquiditySlot := boostInfo.slot
        }
        slots[0] = liquiditySlot;
        slots[1] = boostedLiquiditySlot;

        // read slots from pool
        bytes32[] memory data = pool.readStorage(slots);

        // need to shift data[1] by 128 since this slot has 2 items
        data[1] = data[1] << 128;
        data[1] = data[1] >> 128;

        liquidity = uint128(uint256(data[0]));
        boostedLiquidity = uint128(uint256(data[1]));
    }

    /// @inheritdoc IGaugeV2
    function notifyRewardAmount(
        address token,
        uint256 amount
    ) external override pushFees lock {
        uint256 period = _blockTimestamp() / WEEK;

        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        amount = balanceAfter - balanceBefore;
        tokenTotalSupplyByPeriod[period][token] += amount;
        emit NotifyReward(msg.sender, token, amount, period);
    }

    /// @inheritdoc IGaugeV2
    function earned(
        address token,
        uint256 tokenId
    ) external view returns (uint256 reward) {
        INonfungiblePositionManager _nfpManager = nfpManager;
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager
            .positions(tokenId);

        bytes32 _positionHash = positionHash(
            address(_nfpManager),
            tokenId,
            tickLower,
            tickUpper
        );

        uint256 lastClaim = Math.max(
            lastClaimByToken[token][_positionHash],
            firstPeriod
        );
        uint256 currentPeriod = _blockTimestamp() / WEEK;
        for (uint256 period = lastClaim; period <= currentPeriod; ++period) {
            reward += periodEarned(period, token, tokenId);
        }
    }

    /// @inheritdoc IGaugeV2
    function periodEarned(
        uint256 period,
        address token,
        uint256 tokenId
    ) public view override returns (uint256) {
        INonfungiblePositionManager _nfpManager = nfpManager;
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager
            .positions(tokenId);

        return
            periodEarned(
                period,
                token,
                address(_nfpManager),
                tokenId,
                tickLower,
                tickUpper
            );
    }

    /// @inheritdoc IGaugeV2
    function periodEarned(
        uint256 period,
        address token,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (uint256 amount) {
        (bool success, bytes memory data) = address(this).staticcall(
            abi.encodeCall(
                this.cachePeriodEarned,
                (period, token, owner, index, tickLower, tickUpper, false)
            )
        );

        if (!success) {
            assembly {
                // Copy the returned data.
                returndatacopy(0, 0, returndatasize())

                // delegatecall returns 0 on error.
                revert(0, returndatasize())
            }
        }

        return abi.decode(data, (uint256));
    }

    /// @inheritdoc IGaugeV2
    /// @dev used by getReward() and saves gas by saving states
    function cachePeriodEarned(
        uint256 period,
        address token,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        bool caching
    ) public override returns (uint256 amount) {
        uint256 periodSecondsInsideX96;
        uint256 periodBoostedSecondsInsideX96;

        bytes32 _positionHash = positionHash(
            owner,
            index,
            tickLower,
            tickUpper
        );

        // get seconds from pool if not already written into storage
        if (!periodAmountsWritten[period][_positionHash]) {
            (periodSecondsInsideX96, periodBoostedSecondsInsideX96) = pool
                .positionPeriodSecondsInRange(
                    period,
                    owner,
                    index,
                    tickLower,
                    tickUpper
                );

            if (period < _blockTimestamp() / WEEK && caching) {
                periodAmountsWritten[period][_positionHash] = true;
                periodNfpSecondsX96[period][
                    _positionHash
                ] = periodSecondsInsideX96;
                periodNfpBoostedSecondsX96[period][
                    _positionHash
                ] = periodBoostedSecondsInsideX96;
            }
        } else {
            periodSecondsInsideX96 = periodNfpSecondsX96[period][_positionHash];
            periodBoostedSecondsInsideX96 = periodNfpBoostedSecondsX96[period][
                _positionHash
            ];
        }

        // Get total rewards
        uint256 baseRewards = tokenTotalSupplyByPeriod[period][token];
        uint256 boostedRewards = (baseRewards * 6) / 10;
        baseRewards = baseRewards - boostedRewards;

        // Get total boosted seconds
        uint256 boostedInRange;

        // Check if boostedInRange is already stored in states
        if (period < _blockTimestamp() / WEEK) {
            boostedInRange = periodTotalBoostedSeconds[period];

            if (boostedInRange == 0) {
                uint32 previousPeriod;
                (previousPeriod, , , , , boostedInRange) = pool.periods(period);

                if (previousPeriod != 0 && caching) {
                    periodTotalBoostedSeconds[period] = boostedInRange;
                }
            }
        }

        // Use 1 week if boostedInRange is 0
        if (boostedInRange == 0) {
            boostedInRange = WEEK;
        }

        // rewards are base rewards plus boosted rewards
        amount =
            FullMath.mulDiv(baseRewards, periodSecondsInsideX96, WEEK << 96) +
            FullMath.mulDiv(
                boostedRewards,
                periodBoostedSecondsInsideX96,
                boostedInRange << 96
            );

        amount -= periodClaimedAmount[period][_positionHash][token];

        return amount;
    }

    /// @inheritdoc IGaugeV2
    function getPeriodReward(
        uint256 period,
        address[] calldata tokens,
        uint256 tokenId,
        address receiver
    ) external override lock {
        INonfungiblePositionManager _nfpManager = nfpManager;
        address owner = _nfpManager.ownerOf(tokenId);
        address operator = _nfpManager.getApproved(tokenId);

        require(
            msg.sender == owner || msg.sender == operator,
            "Not authorized"
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager
            .positions(tokenId);

        bytes32 _positionHash = positionHash(
            address(_nfpManager),
            tokenId,
            tickLower,
            tickUpper
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (
                period > lastClaimByToken[tokens[i]][_positionHash] &&
                period < _blockTimestamp() / WEEK - 1
            ) {
                lastClaimByToken[tokens[i]][_positionHash] = period;
            }

            _getReward(
                period,
                tokens[i],
                address(_nfpManager),
                tokenId,
                tickLower,
                tickUpper,
                _positionHash,
                receiver
            );
        }
    }

    /// @inheritdoc IGaugeV2
    function getPeriodReward(
        uint256 period,
        address[] calldata tokens,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        address receiver
    ) external override lock {
        require(msg.sender == owner, "Not authorized");
        bytes32 _positionHash = positionHash(
            owner,
            index,
            tickLower,
            tickUpper
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (
                period > lastClaimByToken[tokens[i]][_positionHash] &&
                period < _blockTimestamp() / WEEK - 1
            ) {
                lastClaimByToken[tokens[i]][_positionHash] = period;
            }

            _getReward(
                period,
                tokens[i],
                owner,
                index,
                tickLower,
                tickUpper,
                _positionHash,
                receiver
            );
        }
    }

    function getReward(
        uint256[] calldata tokenIds,
        address[] memory tokens
    ) external {
        uint256 length = tokenIds.length;

        for (uint256 i = 0; i < length; ++i) {
            getReward(tokenIds[i], tokens);
        }
    }

    function getReward(uint256 tokenId, address[] memory tokens) public lock {
        INonfungiblePositionManager _nfpManager = nfpManager;
        address owner = _nfpManager.ownerOf(tokenId);
        address operator = _nfpManager.getApproved(tokenId);

        require(
            msg.sender == owner || msg.sender == operator,
            "Not authorized"
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager
            .positions(tokenId);

        _getAllRewards(
            address(_nfpManager),
            tokenId,
            tickLower,
            tickUpper,
            tokens,
            msg.sender
        );
    }

    function getRewardForOwner(
        uint256 tokenId,
        address[] memory tokens
    ) external lock {
        require(msg.sender == voter, "Not authorized");

        INonfungiblePositionManager _nfpManager = nfpManager;
        address owner = _nfpManager.ownerOf(tokenId);

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager
            .positions(tokenId);

        _getAllRewards(
            address(_nfpManager),
            tokenId,
            tickLower,
            tickUpper,
            tokens,
            owner
        );
    }

    function getReward(
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        address[] memory tokens,
        address receiver
    ) external lock {
        require(msg.sender == owner, "Not authorized");
        _getAllRewards(owner, index, tickLower, tickUpper, tokens, receiver);
    }

    function _getAllRewards(
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        address[] memory tokens,
        address receiver
    ) internal {
        bytes32 _positionHash = positionHash(
            owner,
            index,
            tickLower,
            tickUpper
        );
        uint256 currentPeriod = _blockTimestamp() / WEEK;
        uint256 lastClaim;
        for (uint256 i = 0; i < tokens.length; ++i) {
            lastClaim = Math.max(
                lastClaimByToken[tokens[i]][_positionHash],
                firstPeriod
            );
            for (
                uint256 period = lastClaim;
                period <= currentPeriod;
                ++period
            ) {
                _getReward(
                    period,
                    tokens[i],
                    owner,
                    index,
                    tickLower,
                    tickUpper,
                    _positionHash,
                    receiver
                );
            }
            lastClaimByToken[tokens[i]][_positionHash] = currentPeriod - 1;
        }
    }

    function _getReward(
        uint256 period,
        address token,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        bytes32 _positionHash,
        address receiver
    ) internal {
        uint256 _reward = cachePeriodEarned(
            period,
            token,
            owner,
            index,
            tickLower,
            tickUpper,
            true
        );

        periodClaimedAmount[period][_positionHash][token] += _reward;

        if (_reward > 0) {
            IERC20(token).safeTransfer(receiver, _reward);
            emit ClaimRewards(period, _positionHash, receiver, token, _reward);
        }
    }
}

