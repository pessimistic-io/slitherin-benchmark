// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import "./IUniswapV3Factory.sol";
import "./IUniswapV3PoolDeployer.sol";
import "./IUniswapV3Pool.sol";

import "./NoDelegateCall.sol";

/// @title Canonical Uniswap V3 factory
/// @notice Deploys Uniswap V3 pools and manages ownership and control over pool protocol fees
contract UniswapV3Factory is IUniswapV3Factory, NoDelegateCall {
    /// @inheritdoc IUniswapV3Factory
    address public override owner;

    /// @inheritdoc IUniswapV3Factory
    uint8 public override defaultProtocolFees;

    /// @dev pool deployer contract address
    address public immutable poolDeployer;

    /// @dev contract address where all the protocol fees will be sent - ProtocolFeeSplitter
    address public immutable PROTOCOL_FEES_RECIPIENT;

    /// @inheritdoc IUniswapV3Factory
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @inheritdoc IUniswapV3Factory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor(address _poolDeployer, address _protocolFeesRecipient) {
        poolDeployer = _poolDeployer;
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        feeAmountTickSpacing[80] = 1;
        emit FeeAmountEnabled(80, 1);
        feeAmountTickSpacing[450] = 10;
        emit FeeAmountEnabled(450, 10);
        feeAmountTickSpacing[2500] = 60;
        emit FeeAmountEnabled(2500, 60);
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);

        defaultProtocolFees = 1 + (1 << 4); // setting default fees to 100%
        emit DefaultProtocolFeesChanged(0, 0, defaultProtocolFees % 16, defaultProtocolFees >> 4);

        PROTOCOL_FEES_RECIPIENT = _protocolFeesRecipient;
    }

    /// @inheritdoc IUniswapV3Factory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));
        pool = IUniswapV3PoolDeployer(poolDeployer).deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IUniswapV3Factory
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }

    /// @inheritdoc IUniswapV3Factory
    function setDefaultProtocolFees(uint8 feeProtocol0, uint8 feeProtocol1) public override{
        require(msg.sender == owner, "Not owner");
        require(feeProtocol0 <= 10 && feeProtocol1 <= 10, "Invalid Fees");

        uint8 feeProtocolOld = defaultProtocolFees;
        defaultProtocolFees = feeProtocol0 + (feeProtocol1 << 4);
        emit DefaultProtocolFeesChanged(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    /// @inheritdoc IUniswapV3Factory
    function collectProtocolFees(
        address pool,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public override returns (uint128 amount0, uint128 amount1) {
        require(msg.sender == owner || msg.sender == PROTOCOL_FEES_RECIPIENT, "Unauthorised");
        return IUniswapV3Pool(pool).collectProtocol(PROTOCOL_FEES_RECIPIENT, amount0Requested, amount1Requested);
    }
}

