// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./IFeeCollector.sol";

import "./IVoter.sol";
import "./IFeeDistributor.sol";

import "./IRamsesV2Pool.sol";

import "./Initializable.sol";
import "./SafeERC20.sol";

contract FeeCollector is Initializable, IFeeCollector {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS = 10_000;

    address public treasury;
    IVoter public voter;

    uint256 public treasuryFees;

    /// @dev disables initiliazers on deploy
    constructor() {
        _disableInitializers();
    }

    /// @dev initializes the contract
    function initialize(
        address _treasury,
        address _voter
    ) external initializer {
        treasury = _treasury;
        voter = IVoter(_voter);
    }

    /// @dev Prevents calling a function from anyone except the treasury
    modifier onlyTreasury() {
        require(msg.sender == treasury, "AUTH");
        _;
    }

    /// @inheritdoc IFeeCollector
    function setTreasury(address _treasury) external override onlyTreasury {
        emit TreasuryChanged(treasury, _treasury);

        treasury = _treasury;
    }

    /// @inheritdoc IFeeCollector
    function setTreasuryFees(
        uint256 _treasuryFees
    ) external override onlyTreasury {
        require(_treasuryFees <= BASIS, ">100%");
        emit TreasuryFeesChanged(treasuryFees, _treasuryFees);

        treasuryFees = _treasuryFees;
    }

    /// @inheritdoc IFeeCollector
    function collectProtocolFees(IRamsesV2Pool pool) external override {
        // get tokens
        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());

        // check if there's a gauge
        IVoter _voter = voter;
        address gauge = _voter.gauges(address(pool));
        bool isAlive = _voter.isAlive(gauge);

        // if there's no gauge, there's no fee distributor, send everything to the treasury directly
        if (gauge == address(0) || !isAlive) {
            (uint128 _amount0, uint128 _amount1) = pool.collectProtocol(
                treasury,
                type(uint128).max,
                type(uint128).max
            );

            emit FeesCollected(address(pool), 0, 0, _amount0, _amount1);
            return;
        }

        // get the fee distributor
        IFeeDistributor feeDist = IFeeDistributor(
            _voter.feeDistributers(gauge)
        );

        // using uint128.max here since the pool automatically determines the owed amount
        pool.collectProtocol(
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        // get balances, not using the return values in case of transfer fees
        uint256 amount0 = token0.balanceOf(address(this));
        uint256 amount1 = token1.balanceOf(address(this));

        uint256 amount0Treasury;
        uint256 amount1Treasury;

        // put into memory to save gas
        uint256 _treasuryFees = treasuryFees;
        if (_treasuryFees != 0) {
            amount0Treasury = (amount0 * _treasuryFees) / BASIS;
            amount1Treasury = (amount1 * _treasuryFees) / BASIS;

            amount0 = amount0 - amount0Treasury;
            amount1 = amount1 - amount1Treasury;

            address _treasury = treasury;

            token0.safeTransfer(_treasury, amount0Treasury);
            token1.safeTransfer(_treasury, amount1Treasury);
        }

        // approve then notify the fee distributor
        token0.approve(address(feeDist), amount0);
        token1.approve(address(feeDist), amount1);
        feeDist.notifyRewardAmount(address(token0), amount0);
        feeDist.notifyRewardAmount(address(token1), amount1);

        emit FeesCollected(
            address(pool),
            amount0,
            amount1,
            amount0Treasury,
            amount1Treasury
        );
    }
}

