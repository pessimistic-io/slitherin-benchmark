// SPDX-License-Identifier: None
pragma solidity =0.8.12;

import {IERC20Minimal} from "./IERC20Minimal.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IAlcorOptionPoolFactory} from "./IAlcorOptionPoolFactory.sol";
import {IBaseAlcorPool} from "./IBaseAlcorPool.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {ERC20} from "./ERC20.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {SafeCast} from "./SafeCast.sol";
import {AlcorUtils} from "./AlcorUtils.sol";

abstract contract BaseOptionPool is IBaseAlcorPool {
    using FullMath for uint256;
    using FullMath for int256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    ///// events
    event AlcorSwap(address recipient, int256 amount0, int256 amount1);
    event AlcorMint(address owner, uint256 amount0, uint256 amount1);
    event AlcorBurn(address owner, uint256 amount0, uint256 amount1);
    event AlcorCollect(address owner, uint256 amount0, uint256 amount1);
    event OptionExpired(uint256 price, uint256 payoffCoefficient);
    event AlcorWithdraw(uint256 payoutAmount);
    event AlcorUpdatePosition(address owner, int24 tickLower, int24 tickUpper, uint128 newLiquidity);

    ///// errors
    error OnlyUniswapV3Pool();
    error transferFromFailed();
    error notYetExpired();
    error LOK();
    error zeroOptionBalance();
    error ZeroLiquidity();

    address public immutable factoryOwner;
    uint256 public payoffCoefficient;

    address public immutable factory;
    IUniswapV3Pool public immutable uniswapV3Pool;
    IUniswapV3Pool public immutable realUniswapV3Pool;

    struct OptionPoolInfo {
        uint256 strikePrice;
        uint256 expiry;
        bool isCall;
        address token0;
        address token1;
        // uint24 _fee;
        int16 _tokensDeltaDecimals;
    }
    OptionPoolInfo public optionPoolInfo;

    // each user may have different positions. Here we store the hash of every position and get info
    mapping(bytes32 => LPPosition) public LPpositionInfos;
    // users balances reflect actual amount of options bought/sold by user
    mapping(address => int256) public usersBalances;

    mapping(address => EnumerableSet.Bytes32Set) internal userLPpositions;

    // responsible for the duration of the TWAP when the option pool becomes expired
    uint32 constant TWAP_DURATION = 1000;

    ///// interfaces
    function expiry() external view override returns (uint256) {
        return optionPoolInfo.expiry;
    }

    function isCall() external view override returns (bool) {
        return optionPoolInfo.isCall;
    }

    function strikePrice() external view override returns (uint256) {
        return optionPoolInfo.strikePrice;
    }

    function tokensDeltaDecimals() external view override returns (int16) {
        return optionPoolInfo._tokensDeltaDecimals;
    }

    ///// set functionality
    function addPos(address owner, bytes32 _value) internal {
        userLPpositions[owner].add(_value);
    }

    function removePos(address owner, bytes32 _value) internal {
        userLPpositions[owner].remove(_value);
    }

    function containsBytes32(address owner, bytes32 _value) external view returns (bool) {
        return userLPpositions[owner].contains(_value);
    }

    function totalBytes32Values(address owner) external view returns (uint256) {
        return userLPpositions[owner].length();
    }

    function getBytes32AtIndex(address owner, uint256 index) external view returns (bytes32) {
        require(index < userLPpositions[owner].length(), 'Index out of bounds');
        return userLPpositions[owner].at(index);
    }

    function getAllBytes32Values(address owner) public view returns (bytes32[] memory) {
        return userLPpositions[owner].values();
    }

    ///// used by front-end
    function getUserLPPositionsInfos(address owner) external view returns (LPPosition[] memory userLPPositions) {
        bytes32[] memory positionsKeys = getAllBytes32Values(owner);
        userLPPositions = new LPPosition[](positionsKeys.length);
        for (uint i = 0; i < positionsKeys.length; i++) {
            userLPPositions[i] = LPpositionInfos[positionsKeys[i]];
        }
        return userLPPositions;
    }

    ///// wrappers
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    ///// used by alcor-uni pool
    function sqrtPriceX96ToUint(uint160 sqrtPriceX96, int16 decimalsTokensDelta) public pure returns (uint256) {
        return AlcorUtils.sqrtPriceX96ToUint(sqrtPriceX96, decimalsTokensDelta);
    }

    ///// used by factory
    function getDeltaDecimalsToken1Token0() public view returns (int16) {
        return AlcorUtils.getDeltaDecimalsToken1Token0(realUniswapV3Pool);
    }

    ///// modifiers
    modifier OnlyFactoryOwner() {
        require(msg.sender == factoryOwner, 'not factory owner');
        _;
    }

    bool public isExpired;
    modifier WhenNotExpired() {
        require(!isExpired, 'expired');
        _;
    }

    bool unlocked;
    modifier lock() {
        if (!unlocked) revert LOK();
        unlocked = false;
        _;
        unlocked = true;
    }

    uint24 UNISWAP_POOL_FEE = 500;

    struct HelpfulStruct {
        address _realUniswapV3FactoryAddress;
        address _conjugatedUniswapV3PoolAddress;
    }
    HelpfulStruct private helpfulStruct;

    // @dev uniswapV3Pool is conjugated uniswap v3 pool
    // @dev realUniswapV3Pool is used as the price oracle at the expiry of the option
    constructor() {
        //ERC721('Alcor Finance Call Option', 'ALCR_CALL')
        factoryOwner = IAlcorOptionPoolFactory(msg.sender).factoryOwner();

        (
            factory,
            optionPoolInfo.strikePrice,
            optionPoolInfo.expiry,
            helpfulStruct._realUniswapV3FactoryAddress,
            helpfulStruct._conjugatedUniswapV3PoolAddress,
            optionPoolInfo.token0,
            optionPoolInfo.token1
        ) = IAlcorOptionPoolFactory(msg.sender).parameters();

        uniswapV3Pool = IUniswapV3Pool(helpfulStruct._conjugatedUniswapV3PoolAddress);
        realUniswapV3Pool = IUniswapV3Pool(
            IUniswapV3Factory(helpfulStruct._realUniswapV3FactoryAddress).getPool(
                optionPoolInfo.token0,
                optionPoolInfo.token1,
                UNISWAP_POOL_FEE
            )
        );
        // set the delta of tokens decimals
        optionPoolInfo._tokensDeltaDecimals = AlcorUtils.getDeltaDecimalsToken1Token0(uniswapV3Pool);
    }

    function initializeWithTick(int24 tick) external OnlyFactoryOwner WhenNotExpired {
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(-tick);
        // if uni pool was already initialized, this will revert
        uniswapV3Pool.initialize(sqrtPriceX96);
        // pool initialized, so is now unlocked
        unlocked = true;
    }

    // @dev bring the option pool to expired state
    // @dev changes the flag isExpired to true
    // @dev save the oracle price at the expiry
    // @dev works both for call and put option
    function toExpiredState() external lock {
        if (optionPoolInfo.expiry > _blockTimestamp()) revert notYetExpired();

        int24 twap = AlcorUtils.getTwap(realUniswapV3Pool, TWAP_DURATION);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(twap);
        uint256 price = AlcorUtils.sqrtPriceX96ToUint(sqrtPriceX96, optionPoolInfo._tokensDeltaDecimals);

        // call option
        if (optionPoolInfo.isCall) {
            if (price > optionPoolInfo.strikePrice) {
                payoffCoefficient = (price - optionPoolInfo.strikePrice).mulDiv(1 ether, price);
            } else {
                payoffCoefficient = 0;
            }
        }
        // put option
        else {
            if (price < optionPoolInfo.strikePrice) {
                payoffCoefficient = (optionPoolInfo.strikePrice - price).mulDiv(1 ether, price);
            } else {
                payoffCoefficient = 0;
            }
        }
        // set expired state
        isExpired = true;

        emit OptionExpired(price, payoffCoefficient);
    }

    // @dev this function allows collect the protocol fees
    // @param address which will recieve the collected fees
    // @param amounts requested: if higher than actual, then will collect maximum amount of fees
    function collectProtocolFees(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override OnlyFactoryOwner lock returns (uint128 amount0, uint128 amount1) {
        // calculated accrued amount of protocol fees
        (amount0, amount1) = uniswapV3Pool.collectProtocol(recipient, amount0Requested, amount1Requested);
        // do transfers to recipient
        ERC20(optionPoolInfo.token0).safeTransfer(recipient, uint256(amount0));
        ERC20(optionPoolInfo.token1).safeTransfer(recipient, uint256(amount1));
    }
}

