//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IWeightedPoolFactory, IWeightedPool, IAsset, IVault } from "./IWeightedPoolFactory.sol";

abstract contract PepeLPHelper {
    string public constant NAME = "Balancer 80peg-20WETH";
    string public constant SYMBOL = "PEG_80-WETH_20";
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant VAULT_ADDRESS = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address public immutable peg;
    IWeightedPoolFactory public immutable poolFactory;

    address public lpTokenAddr;
    bytes32 public poolId;

    event PoolCreated(
        address indexed pool,
        address indexed token0,
        address indexed token1,
        uint256 token0Weight,
        uint256 token1Weight,
        bytes32 poolId
    );

    event PoolInitialized(
        address indexed initializer,
        uint256 indexed token0Amount,
        uint256 indexed token1Amount,
        uint256 lpAmount
    );

    constructor(address _peg, address _poolFactory) {
        peg = _peg;
        poolFactory = IWeightedPoolFactory(_poolFactory);
    }

    function _initializePool(uint256 _wethAmount, uint256 _pegAmount, address _poolAdmin) internal {
        require(lpTokenAddr == address(0), "Already initialized");
        (address token0, address token1) = sortTokens(WETH, peg);
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(token0);
        tokens[1] = IERC20(token1);

        address[] memory rateProviders = new address[](2);
        rateProviders[0] = 0x0000000000000000000000000000000000000000;
        rateProviders[1] = 0x0000000000000000000000000000000000000000;

        uint256 swapFeePercentage = 10000000000000000;

        uint256[] memory weights = new uint256[](2);

        if (token0 == peg) {
            weights[0] = 800000000000000000;
            weights[1] = 200000000000000000;
        } else {
            weights[0] = 200000000000000000;
            weights[1] = 800000000000000000;
        }

        address _lpTokenAddr = poolFactory.create(
            NAME,
            SYMBOL,
            tokens,
            weights,
            rateProviders,
            swapFeePercentage,
            _poolAdmin
        );

        lpTokenAddr = _lpTokenAddr;

        poolId = IWeightedPool(_lpTokenAddr).getPoolId();

        emit PoolCreated(_lpTokenAddr, token0, token1, weights[0], weights[1], poolId);

        _initPool(_wethAmount, _pegAmount, _poolAdmin);
    }

    function _initPool(uint256 _wethAmt, uint256 _pegAmt, address _poolAdmin) private {
        (address token0, address token1) = sortTokens(peg, WETH);
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(token0);
        assets[1] = IAsset(token1);

        uint256[] memory maxAmountsIn = new uint256[](2);
        if (token0 == WETH) {
            maxAmountsIn[0] = _wethAmt;
            maxAmountsIn[1] = _pegAmt;
        } else {
            maxAmountsIn[0] = _pegAmt;
            maxAmountsIn[1] = _wethAmt;
        }

        require(IERC20(peg).transferFrom(msg.sender, address(this), _pegAmt), "peg transfer failed");
        require(IERC20(WETH).transferFrom(msg.sender, address(this), _wethAmt), "weth transfer failed");

        IERC20(peg).approve(VAULT_ADDRESS, _pegAmt);
        IERC20(WETH).approve(VAULT_ADDRESS, _wethAmt);

        bytes memory userDataEncoded = abi.encode(IWeightedPool.JoinKind.INIT, maxAmountsIn, 1);
        IVault.JoinPoolRequest memory inRequest = IVault.JoinPoolRequest(assets, maxAmountsIn, userDataEncoded, false);
        IVault(VAULT_ADDRESS).joinPool(poolId, address(this), _poolAdmin, inRequest); //send the LP tokens to the pool admin

        emit PoolInitialized(msg.sender, _wethAmt, _pegAmt, IERC20(lpTokenAddr).balanceOf(_poolAdmin));
    }

    function _joinPool(uint256 _wethAmt, uint256 _pegAmt, uint256 _minBlpOut) internal {
        (address token0, address token1) = sortTokens(peg, WETH);
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(token0);
        assets[1] = IAsset(token1);

        uint256[] memory maxAmountsIn = new uint256[](2);
        if (token0 == WETH) {
            maxAmountsIn[0] = _wethAmt;
            maxAmountsIn[1] = _pegAmt;
        } else {
            maxAmountsIn[0] = _pegAmt;
            maxAmountsIn[1] = _wethAmt;
        }

        IERC20(peg).transferFrom(msg.sender, address(this), _pegAmt);
        IERC20(WETH).transferFrom(msg.sender, address(this), _wethAmt);

        IERC20(peg).approve(VAULT_ADDRESS, _pegAmt);
        IERC20(WETH).approve(VAULT_ADDRESS, _wethAmt);

        bytes memory userDataEncoded = abi.encode(
            IWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            maxAmountsIn,
            _minBlpOut
        );
        IVault.JoinPoolRequest memory inRequest = IVault.JoinPoolRequest(assets, maxAmountsIn, userDataEncoded, false);
        IVault(VAULT_ADDRESS).joinPool(poolId, address(this), address(this), inRequest);
    }

    function _exitPool(uint256 lpAmount) internal {
        (address token0, address token1) = sortTokens(peg, WETH);
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(token0);
        assets[1] = IAsset(token1);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;

        IERC20(lpTokenAddr).approve(VAULT_ADDRESS, lpAmount);

        bytes memory userData = abi.encode(IWeightedPool.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, lpAmount);

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
        IVault(VAULT_ADDRESS).exitPool(poolId, address(this), payable(msg.sender), request); //send both peg and weth to the locker (user).
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(tokenA != address(0), "ZERO_ADDRESS");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function balanceOfTokens() external view returns (uint256[] memory) {
        (, uint256[] memory balances, ) = IVault(VAULT_ADDRESS).getPoolTokens(poolId);
        return balances;
    }

    function getNormalizedWeights() external view returns (uint256[] memory) {
        return IWeightedPool(lpTokenAddr).getNormalizedWeights();
    }
}

