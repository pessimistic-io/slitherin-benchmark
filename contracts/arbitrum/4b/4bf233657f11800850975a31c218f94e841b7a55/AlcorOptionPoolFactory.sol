// SPDX-License-Identifier: None
pragma solidity =0.8.12;

import {AlcorOptionPoolDeployer} from "./AlcorOptionPoolDeployer.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";

import {AlcorUtils} from "./AlcorUtils.sol";
import {FullMath} from "./FullMath.sol";

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IBaseAlcorPool} from "./IBaseAlcorPool.sol";
import {IERC20Minimal} from "./IERC20Minimal.sol";

contract AlcorOptionPoolFactory is AlcorOptionPoolDeployer, NoDelegateCall {
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event OptionPoolCreated(
        address indexed token0,
        address indexed token1,
        uint256 optionExpiration,
        bool isCall,
        uint256 indexed optionStrikePrice,
        address pool,
        address realUniswapV3PoolAddress
    );

    address public factoryOwner;
    mapping(uint24 => int24) public feeAmountTickSpacing;
    // token0 => token1 => optionExpiration => isCall => optionStrikePrice => pool
    // token1 => token0 => optionExpiration => isCall => optionStrikePrice => pool
    mapping(address => mapping(address => mapping(uint256 => mapping(bool => mapping(uint256 => address)))))
        public getPool;
    mapping(address => bool) public isPool;
    // the info about all pools for the token pair and expiration
    // token0 => token1 => optionExpiration => isCall => strikes[]
    mapping(address => mapping(address => mapping(uint256 => mapping(bool => uint256[]))))
        public _getStrikesForPairAndExpiration;

    struct OptionPoolInfo {
        address token0;
        address token1;
        uint256 optionExpiration;
        bool isCall;
        uint256 optionStrikePrice;
        uint256 TVL;
        uint256 optionPrice;
        address optionPoolAddress;
        address conjugateUniPoolAddress;
        address realUniswapV3PoolAddress;
    }

    struct AuxillaryInfo {
        address optionPoolAddress;
        IUniswapV3Pool conjugateUniPool;
        IUniswapV3Pool realUniswapV3Pool;
        uint256 assetPrice;
        uint256 optionPrice;
        uint256 TVLOfToken0;
        uint256 TVLOfToken1;
    }

    modifier OnlyFactoryOwner() {
        require(msg.sender == factoryOwner, 'not factory owner');
        _;
    }

    function getOptionPoolInfo(address poolAddress) public view returns (OptionPoolInfo memory optionPoolInfo) {
        AuxillaryInfo memory auxillaryInfo;

        auxillaryInfo.optionPoolAddress = poolAddress;
        auxillaryInfo.conjugateUniPool = IBaseAlcorPool(auxillaryInfo.optionPoolAddress).uniswapV3Pool();
        auxillaryInfo.realUniswapV3Pool = IBaseAlcorPool(auxillaryInfo.optionPoolAddress).realUniswapV3Pool();

        (uint160 sqrtOptionPriceX96, , , , , , ) = IUniswapV3Pool(auxillaryInfo.conjugateUniPool).slot0();
        (uint160 sqrtAssetPriceX96, , , , , , ) = IUniswapV3Pool(auxillaryInfo.realUniswapV3Pool).slot0();
        int16 tokensDeltaDecimals = IBaseAlcorPool(auxillaryInfo.optionPoolAddress).tokensDeltaDecimals();

        // uint8 token0Decimals = IERC20Minimal(auxillaryInfo.realUniswapV3Pool.token0()).decimals();

        auxillaryInfo.assetPrice = AlcorUtils.sqrtPriceX96ToUint(sqrtAssetPriceX96, tokensDeltaDecimals);
        // not works for arbitrary tokens
        auxillaryInfo.optionPrice = tokensDeltaDecimals > 0
            ? AlcorUtils.sqrtPriceX96ToUint(sqrtOptionPriceX96, tokensDeltaDecimals)
            : AlcorUtils.sqrtPriceX96ToUint(sqrtOptionPriceX96, -tokensDeltaDecimals);

        auxillaryInfo.TVLOfToken0 =
            IERC20Minimal(auxillaryInfo.realUniswapV3Pool.token0()).balanceOf(auxillaryInfo.optionPoolAddress) +
            IERC20Minimal(auxillaryInfo.realUniswapV3Pool.token0()).balanceOf(address(auxillaryInfo.conjugateUniPool));
        auxillaryInfo.TVLOfToken1 = FullMath.mulDiv(
            IERC20Minimal(auxillaryInfo.realUniswapV3Pool.token1()).balanceOf(auxillaryInfo.optionPoolAddress) +
                IERC20Minimal(auxillaryInfo.realUniswapV3Pool.token1()).balanceOf(
                    address(auxillaryInfo.conjugateUniPool)
                ),
            auxillaryInfo.assetPrice,
            1 ether // 1e18
        );
        optionPoolInfo = OptionPoolInfo({
            token0: auxillaryInfo.conjugateUniPool.token0(),
            token1: auxillaryInfo.conjugateUniPool.token1(),
            optionExpiration: IBaseAlcorPool(auxillaryInfo.optionPoolAddress).expiry(),
            isCall: IBaseAlcorPool(auxillaryInfo.optionPoolAddress).isCall(),
            optionStrikePrice: IBaseAlcorPool(auxillaryInfo.optionPoolAddress).strikePrice(),
            TVL: tokensDeltaDecimals > 0
                ? auxillaryInfo.TVLOfToken0 * 10 ** uint16(tokensDeltaDecimals) + auxillaryInfo.TVLOfToken1
                : auxillaryInfo.TVLOfToken1 * 10 ** uint16(-tokensDeltaDecimals) + auxillaryInfo.TVLOfToken0,
            optionPrice: auxillaryInfo.optionPrice,
            optionPoolAddress: auxillaryInfo.optionPoolAddress,
            conjugateUniPoolAddress: address(auxillaryInfo.conjugateUniPool),
            realUniswapV3PoolAddress: address(auxillaryInfo.realUniswapV3Pool)
        });
    }

    function getOptionsTableForPairAndExpiration(
        address token0,
        address token1,
        uint256 optionExpiration,
        bool isCall
    ) external view returns (OptionPoolInfo[] memory optionsTable) {
        address[] memory poolsAddresses = getAddressesForPairAndExpiration(token0, token1, optionExpiration, isCall);
        optionsTable = new OptionPoolInfo[](poolsAddresses.length);

        for (uint32 i = 0; i < poolsAddresses.length; i++) {
            optionsTable[i] = getOptionPoolInfo(poolsAddresses[i]);
        }
    }

    function getStrikesForPairAndExpiration(
        address token0,
        address token1,
        uint256 optionExpiration,
        bool isCall
    ) public view returns (uint256[] memory strikes) {
        strikes = _getStrikesForPairAndExpiration[token0][token1][optionExpiration][isCall];
    }

    function getAddressesForPairAndExpiration(
        address token0,
        address token1,
        uint256 optionExpiration,
        bool isCall
    ) public view returns (address[] memory poolsAddresses) {
        uint256[] memory strikes = _getStrikesForPairAndExpiration[token0][token1][optionExpiration][isCall];
        poolsAddresses = new address[](strikes.length);
        for (uint32 i = 0; i < strikes.length; i++) {
            poolsAddresses[i] = getPool[token0][token1][optionExpiration][isCall][strikes[i]];
        }
    }

    constructor() {
        factoryOwner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
    }

    // @dev dollars always must be token0, token1 must be risky asset
    function createPoolCallOption(
        uint256 optionStrikePrice,
        uint256 optionExpiration,
        address realUniswapV3PoolAddress,
        address conjugatedUniswapV3PoolAddress,
        address tokenA,
        address tokenB
    ) external virtual noDelegateCall OnlyFactoryOwner returns (address pool) {
        require(tokenA != tokenB);
        // (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (address token0, address token1) = (tokenA, tokenB);
        require(token0 != address(0));

        bool isCall = true;

        require(getPool[token0][token1][optionExpiration][isCall][optionStrikePrice] == address(0));
        pool = deployCallOption(
            address(this),
            optionStrikePrice,
            optionExpiration,
            realUniswapV3PoolAddress,
            conjugatedUniswapV3PoolAddress,
            token0,
            token1
        );
        // pool = deploy(address(this), strikePrice, expiry, realUniswapV3PoolAddress, token0, token1, fee, tickSpacing);

        getPool[token0][token1][optionExpiration][isCall][optionStrikePrice] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][optionExpiration][isCall][optionStrikePrice] = pool;
        // lookup table for pools
        isPool[pool] = true;

        _getStrikesForPairAndExpiration[token0][token1][optionExpiration][isCall].push(optionStrikePrice);
        _getStrikesForPairAndExpiration[token1][token0][optionExpiration][isCall].push(optionStrikePrice);

        emit OptionPoolCreated(
            token0,
            token1,
            optionExpiration,
            isCall,
            optionStrikePrice,
            pool,
            realUniswapV3PoolAddress
        );
    }

    function setOwner(address _factoryOwner) external {
        require(msg.sender == factoryOwner);
        emit OwnerChanged(factoryOwner, _factoryOwner);
        factoryOwner = _factoryOwner;
    }

    // @ AlcorFinance
    function setAlcorOptionPoolAddress(
        address _alcorOptionPoolAddress_,
        address tokenA,
        address tokenB,
        uint256 optionExpiration,
        bool isCall,
        uint256 optionStrikePrice
    ) external OnlyFactoryOwner {
        // token0 => token1 => optionExpiration => isCall => optionStrikePrice => pool
        IUniswapV3Pool(getPool[tokenA][tokenB][optionExpiration][isCall][optionStrikePrice]).setAlcorOptionPoolAddress(
            _alcorOptionPoolAddress_
        );
    }
}

