// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.10;

import "./IERC20.sol";
import "./IAntfarmFactory.sol";
import "./IAntfarmAtfPair.sol";
import "./IAntfarmOracle.sol";
import "./IAntfarmToken.sol";
import "./math.sol";
import "./UQ112x112.sol";
import "./TransferHelper.sol";
import "./AntfarmPairErrors.sol";
import "./ReentrancyGuard.sol";

/// @title Core contract for Antfarm Pairs with ATF token
/// @notice Low-level contract to mint/burn/swap and claim
contract AntfarmAtfPair is IAntfarmAtfPair, ReentrancyGuard, Math {
    using UQ112x112 for uint224;

    /// @inheritdoc IAntfarmPairState
    address public immutable factory;

    /// @inheritdoc IAntfarmPairState
    address public token0;

    /// @inheritdoc IAntfarmPairState
    address public token1;

    /// @inheritdoc IAntfarmPairState
    uint16 public fee;

    /// @inheritdoc IAntfarmPairState
    uint256 public totalSupply;

    /// @inheritdoc IAntfarmAtfPair
    uint256 public price1CumulativeLast;

    /// @inheritdoc IAntfarmPairState
    uint256 public antfarmTokenReserve;

    /// @inheritdoc IAntfarmAtfPair
    address public antfarmOracle;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    // DIVIDEND VARIABLES
    uint256 private totalDividendPoints;
    uint256 private constant POINT_MULTIPLIER = 1 ether;

    uint256 private constant MINIMUM_LIQUIDITY = 1000;

    struct Position {
        uint128 lp;
        uint256 dividend;
        uint256 lastDividendPoints;
    }

    mapping(address => mapping(uint256 => Position)) public positions;

    modifier updateDividend(address operator, uint256 positionId) {
        if (positions[operator][positionId].lp > 0) {
            uint256 owing = newDividends(
                operator,
                positionId,
                totalDividendPoints
            );
            if (owing > 0) {
                positions[operator][positionId].dividend += owing;
                positions[operator][positionId]
                    .lastDividendPoints = totalDividendPoints;
            }
        } else {
            positions[operator][positionId]
                .lastDividendPoints = totalDividendPoints;
        }
        _;
    }

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address _token0,
        address _token1,
        uint16 _fee
    ) external {
        if (msg.sender != factory) revert SenderNotFactory();
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    /// @inheritdoc IAntfarmPairActions
    function mint(address to, uint256 positionId)
        external
        override
        nonReentrant
        updateDividend(to, positionId)
        returns (uint256)
    {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this)) -
            antfarmTokenReserve;
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 liquidity;

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            totalSupply = MINIMUM_LIQUIDITY;
        } else {
            liquidity = Math.min(
                (amount0 * totalSupply) / _reserve0,
                (amount1 * totalSupply) / _reserve1
            );
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        positions[to][positionId].lp += uint128(liquidity);
        totalSupply = totalSupply + liquidity;

        _update(balance0, balance1, _reserve0, _reserve1);
        if (_totalSupply == 0) {
            if (fee == 10) {
                setOracleInstance();
            }
        }
        emit Mint(to, amount0, amount1);
        return liquidity;
    }

    /// @inheritdoc IAntfarmPairActions
    function burn(
        address to,
        uint256 positionId,
        uint256 liquidity
    )
        external
        override
        nonReentrant
        updateDividend(msg.sender, positionId)
        returns (uint256, uint256)
    {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings

        uint256 balance0 = IERC20(token0).balanceOf(address(this)) -
            antfarmTokenReserve;
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        if (positions[msg.sender][positionId].lp < liquidity) {
            revert InsufficientLiquidity();
        }

        positions[msg.sender][positionId].lp -= uint128(liquidity);

        if (liquidity == 0) revert InsufficientLiquidity();

        uint256 _totalSupply = totalSupply; // gas savings
        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;
        totalSupply = totalSupply - liquidity;

        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

        TransferHelper.safeTransfer(token0, to, amount0);
        TransferHelper.safeTransfer(token1, to, amount1);

        balance0 =
            IERC20(token0).balanceOf(address(this)) -
            antfarmTokenReserve;
        balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
        return (amount0, amount1);
    }

    /// @inheritdoc IAntfarmPairActions
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) {
            revert InsufficientOutputAmount();
        }

        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) {
            revert InsufficientLiquidity();
        }

        uint256 balance0;
        uint256 balance1;
        address _token0 = token0;
        {
            address _token1 = token1;
            if (to == _token0 || to == _token1) revert InvalidReceiver();
            if (amount0Out > 0)
                TransferHelper.safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0)
                TransferHelper.safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            balance0 =
                IERC20(_token0).balanceOf(address(this)) -
                antfarmTokenReserve;
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint256 amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);

        // MINIMUM_LIQUIDITY is used instead of 1000
        uint256 feeToPay = ((amount0In * fee) / (MINIMUM_LIQUIDITY + fee)) +
            ((amount0Out * fee) / (MINIMUM_LIQUIDITY - fee));
        if (feeToPay < MINIMUM_LIQUIDITY) revert SwapAmountTooLow();
        balance0 -= feeToPay;

        if (balance0 * balance1 < uint256(_reserve0) * _reserve1) revert K();
        _update(balance0, balance1, _reserve0, _reserve1);

        // only 1% pool have oracles
        if (fee == 10) {
            IAntfarmOracle(antfarmOracle).update(
                price1CumulativeLast,
                blockTimestampLast
            );
        }

        uint256 feeToDisburse = (feeToPay * 8500) / 10000;
        uint256 feeToBurn = feeToPay - feeToDisburse;

        _disburse(feeToDisburse);
        // burned to reduce totalSupply isntead of sending to addressZero
        IAntfarmToken(_token0).burn(feeToBurn);
    }

    /// @inheritdoc IAntfarmPairActions
    function claimDividend(address to, uint256 positionId)
        external
        override
        nonReentrant
        updateDividend(msg.sender, positionId)
        returns (uint256 claimAmount)
    {
        claimAmount = positions[msg.sender][positionId].dividend;
        if (claimAmount != 0) {
            positions[msg.sender][positionId].dividend = 0;
            antfarmTokenReserve -= claimAmount;
            TransferHelper.safeTransfer(token0, to, claimAmount);
        }
    }

    /// @inheritdoc IAntfarmPairActions
    function skim(address to) external nonReentrant {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        TransferHelper.safeTransfer(
            _token0,
            to,
            IERC20(_token0).balanceOf(address(this)) -
                reserve0 -
                antfarmTokenReserve
        );
        TransferHelper.safeTransfer(
            _token1,
            to,
            IERC20(_token1).balanceOf(address(this)) - reserve1
        );
    }

    /// @inheritdoc IAntfarmPairActions
    function sync() external nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)) - antfarmTokenReserve,
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    /// @inheritdoc IAntfarmPairDerivedState
    function getPositionLP(address operator, uint256 positionId)
        external
        view
        override
        returns (uint128)
    {
        return positions[operator][positionId].lp;
    }

    /// @inheritdoc IAntfarmPairDerivedState
    function getReserves()
        public
        view
        override
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /// @inheritdoc IAntfarmPairDerivedState
    function claimableDividends(address operator, uint256 positionId)
        external
        view
        override
        returns (uint256 amount)
    {
        uint256 tempTotalDividendPoints = totalDividendPoints;

        uint256 newDividend = newDividends(
            operator,
            positionId,
            tempTotalDividendPoints
        );
        amount = positions[operator][positionId].dividend + newDividend;
    }

    function newDividends(
        address operator,
        uint256 positionId,
        uint256 tempTotalDividendPoints
    ) internal view returns (uint256 amount) {
        uint256 newDividendPoints = tempTotalDividendPoints -
            positions[operator][positionId].lastDividendPoints;
        amount =
            (positions[operator][positionId].lp * newDividendPoints) /
            POINT_MULTIPLIER;
    }

    function setOracleInstance() internal {
        antfarmOracle = address(
            new AntfarmOracle(token1, price1CumulativeLast, blockTimestampLast)
        );
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert BalanceOverflow();
        }
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed;

        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        }

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price1CumulativeLast =
                price1CumulativeLast +
                (uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                    timeElapsed);
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _disburse(uint256 amount) private {
        totalDividendPoints =
            totalDividendPoints +
            ((amount * POINT_MULTIPLIER) / (totalSupply - MINIMUM_LIQUIDITY));
        antfarmTokenReserve = antfarmTokenReserve + amount;
    }
}

