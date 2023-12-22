// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";
import "./IUniswapV2Router02.sol";
import "./EnumerableSet.sol";
import "./IGauge.sol";
import "./IVelodromeRouter.sol";

//import "hardhat/console.sol";

/// @title Velodrome Matrix Lp AutoCompound Strategy
contract VeloMatrixLpAutoCompound is MatrixLpAutoCompound {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public isStable;

    address internal constant sUSD = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;
    address internal constant MAI = 0xdFA46478F9e5EA86d57387849598dbFB2e964b02;
    address internal constant OP = 0x4200000000000000000000000000000000000042;
    address internal constant LYRA = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address internal constant THALES =
        0x217D47011b23BB961eB6D93cA9945B7501a5BB11;
    address internal constant LUSD = 0xc40F949F8a4e094D1b49a23ea9241D289B7b2819;
    address internal constant alUSD =
        0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address internal constant FRAX = 0x2E3D870790dC77A83DD1d18184Acc7439A53f475;
    address internal constant sETH = 0xE405de8F52ba7559f9df3C368500B6E6ae6Cee49;
    address internal constant HND = 0x10010078a54396F62c96dF8532dc2B4847d47ED3;
    address internal constant L2DAO = 0xd52f94DF742a6F4B4C8b033369fE13A41782Bf44;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        bool _isStable,
        address _vault,
        address _treasury
    )
        MatrixLpAutoCompound(
            _want,
            _poolId,
            _masterchef,
            _output,
            _uniRouter,
            _vault,
            _treasury
        )
    {
        isStable = _isStable;
    }

    function _initialize(address _masterchef, address _output, uint256 _poolId) internal override {
        wrapped = 0x4200000000000000000000000000000000000006;
        treasury = 0xEaD9f532C72CF35dAb18A42223eE7A1B19bC5aBF;
        USDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
        partner = address(0xb074ec6c37659525EEf2Fb44478077901F878012);
        treasuryFee = 4500;
        partnerFee = 4500;
        super._initialize(_masterchef, _output, _poolId);
    }

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(USDC);
        whitelistedAddresses.add(L2DAO);
        whitelistedAddresses.add(OP);
        whitelistedAddresses.add(sUSD);
        whitelistedAddresses.add(MAI);
        whitelistedAddresses.add(USDC);
        whitelistedAddresses.add(LYRA);
        whitelistedAddresses.add(THALES);
        whitelistedAddresses.add(LUSD);
        whitelistedAddresses.add(alUSD);
        whitelistedAddresses.add(FRAX);
        whitelistedAddresses.add(sETH);
        whitelistedAddresses.add(HND);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // VELO -> USDC
        address[] memory _VELOsUSD = new address[](4);
        _VELOsUSD[0] = output;
        _VELOsUSD[1] = wrapped;
        _VELOsUSD[2] = USDC;
        _VELOsUSD[3] = sUSD;
        _setSwapPath(output, sUSD, unirouter, _VELOsUSD);

        // VELO -> WETH
        address[] memory _VELOWETH = new address[](3);
        _VELOWETH[0] = output;
        _VELOWETH[1] = USDC;
        _VELOWETH[2] = wrapped;
        _setSwapPath(output, wrapped, unirouter, _VELOWETH);

        // VELO -> MAI
        address[] memory _VELOMAI = new address[](3);
        _VELOMAI[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        _VELOMAI[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _VELOMAI[2] = 0xdFA46478F9e5EA86d57387849598dbFB2e964b02;
        _setSwapPath(output, MAI, unirouter, _VELOMAI);

        // VELO -> OP
        address[] memory _VELOOP = new address[](3);
        _VELOOP[0] = output;
        _VELOOP[1] = USDC;
        _VELOOP[2] = OP;
        _setSwapPath(output, OP, unirouter, _VELOOP);

        // VELO -> L2DAO
        address[] memory _VELOL2DAO = new address[](4);
        _VELOL2DAO[0] = output;
        _VELOL2DAO[1] = USDC;
        _VELOL2DAO[2] = OP;
        _VELOL2DAO[3] = L2DAO;
        _setSwapPath(output, L2DAO, unirouter, _VELOL2DAO);

        // VELO -> LYRA
        address[] memory _VELOLYRA = new address[](3);
        _VELOLYRA[0] = output;
        _VELOLYRA[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _VELOLYRA[2] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
        _setSwapPath(output, LYRA, unirouter, _VELOLYRA);

        // VELO -> THALES
        address[] memory _VELOTHALES = new address[](3);
        _VELOTHALES[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        _VELOTHALES[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _VELOTHALES[2] = 0x217D47011b23BB961eB6D93cA9945B7501a5BB11;
        _setSwapPath(output, THALES, unirouter, _VELOTHALES);

        // VELO -> LUSD
        address[] memory _VELOLUSD = new address[](3);
        _VELOLUSD[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        _VELOLUSD[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _VELOLUSD[2] = 0xc40F949F8a4e094D1b49a23ea9241D289B7b2819;
        _setSwapPath(output, LUSD, unirouter, _VELOLUSD);

        // VELO -> alUSD
        address[] memory _VELOalUSD = new address[](3);
        _VELOalUSD[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        _VELOalUSD[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _VELOalUSD[2] = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
        _setSwapPath(output, alUSD, unirouter, _VELOalUSD);

        // VELO -> FRAX
        address[] memory _VELOFRAX = new address[](3);
        _VELOFRAX[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        _VELOFRAX[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _VELOFRAX[2] = 0x2E3D870790dC77A83DD1d18184Acc7439A53f475;
        _setSwapPath(output, FRAX, unirouter, _VELOFRAX);

        // VELO -> sETH
        address[] memory _VELOsETH = new address[](4);
        _VELOsETH[0] = output;
        _VELOsETH[1] = USDC;
        _VELOsETH[2] = wrapped;
        _VELOsETH[3] = sETH;
        _setSwapPath(output, sETH, unirouter, _VELOsETH);

        // VELO -> HND
        address[] memory _VELOHND = new address[](3);
        _VELOHND[0] = output;
        _VELOHND[1] = USDC;
        _VELOHND[2] = HND;
        _setSwapPath(output, HND, unirouter, _VELOHND);
    }

    function totalValue() public view override returns (uint256) {
        uint256 _totalStaked = IGauge(masterchef).balanceOf(address(this));
        return IERC20(want).balanceOf(address(this)) + _totalStaked;
    }

    function _beforeWithdraw(uint256 _amount) internal override {
        IGauge(masterchef).withdraw(_amount);
    }

    function _beforeHarvest() internal override {
        address[] memory _tokens = new address[](1);
        _tokens[0] = output;
        IGauge(masterchef).getReward(address(this), _tokens);
    }

    function _deposit() internal virtual override {
        uint256 _wantBalance = IERC20(want).balanceOf(address(this));
        if (_wantBalance > 0) IGauge(masterchef).deposit(_wantBalance, poolId);
    }

    function _beforePanic() internal virtual override {
        IGauge(masterchef).withdrawAll();
    }

    function _getRatio(address _lpToken) internal view returns (uint256) {
        address _token0 = IUniswapV2Pair(_lpToken).token0();
        address _token1 = IUniswapV2Pair(_lpToken).token1();

        (uint256 opLp0, uint256 opLp1, ) = IUniswapV2Pair(_lpToken)
            .getReserves();
        uint256 lp0Amt = (opLp0 * (10**18)) /
            (10**IERC20Metadata(_token0).decimals());
        uint256 lp1Amt = (opLp1 * (10**18)) /
            (10**IERC20Metadata(_token1).decimals());
        uint256 totalSupply = lp0Amt + (lp1Amt);
        return (lp0Amt * (10**18)) / (totalSupply);
    }

    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amount
    ) internal override returns (uint256 _toTokenAmount) {
        if (_fromToken == _toToken) return _amount;
        SwapPath memory _swapPath = getSwapPath(_fromToken, _toToken);

        route[] memory _routes = new route[](_swapPath.path.length - 1);

        uint256 _lastAmountBack = _amount;
        for (uint256 i; i < _swapPath.path.length - 1; i++) {
            (uint256 _amountBack, bool _stable) = IVelodromeRouter(
                _swapPath.unirouter
            ).getAmountOut(
                    _lastAmountBack,
                    _swapPath.path[i],
                    _swapPath.path[i + 1]
                );
            _lastAmountBack = _amountBack;
            _routes[i] = route({
                from: _swapPath.path[i],
                to: _swapPath.path[i + 1],
                stable: _stable
            });
        }

        IERC20(_fromToken).safeApprove(_swapPath.unirouter, 0);
        IERC20(_fromToken).safeApprove(_swapPath.unirouter, type(uint256).max);

        // debugging: uncomment this block
        // console.log("++++++++++");
        // console.log("_fromToken:", IERC20Metadata(_fromToken).symbol());
        // console.log("_fromAddr:", _fromToken);
        // console.log("_toToken:", IERC20Metadata(_toToken).symbol());
        // console.log("_toAddr:", _toToken);
        // console.log("_amount:", _amount);
        // console.log("_path:");
        // for (uint256 i; i < _swapPath.path.length; i++) {
        //     console.log(
        //         IERC20Metadata(_swapPath.path[i]).symbol(),
        //         _swapPath.path[i]
        //     );
        //     console.log("-----");
        // }
        // console.log("++++++++++");
        // console.log("");

        uint256 _toTokenBefore = IERC20(_toToken).balanceOf(address(this));
        IVelodromeRouter(_swapPath.unirouter).swapExactTokensForTokens(
            _amount,
            0,
            _routes,
            address(this),
            block.timestamp
        );

        _toTokenAmount =
            IERC20(_toToken).balanceOf(address(this)) -
            _toTokenBefore;
    }

    function _addLiquidity(uint256 _outputAmount)
        internal
        override
        returns (uint256 _wantHarvested)
    {
        uint256 _wantBalanceBefore = IERC20(want).balanceOf(address(this));
        uint256 _lpToken0BalanceBefore = IERC20(lpToken0).balanceOf(
            address(this)
        );
        uint256 _lpToken1BalanceBefore = IERC20(lpToken1).balanceOf(
            address(this)
        );
        //console.log(IERC20(output).balanceOf(address(this)));

        if (!isStable) {
            if (output == lpToken0) {
                _swap(output, lpToken1, _outputAmount / 2);
            } else if (output == lpToken1) {
                _swap(output, lpToken0, _outputAmount / 2);
            } else {
                _swap(output, lpToken0, _outputAmount / 2);
                _swap(
                    output,
                    lpToken1,
                    IERC20(output).balanceOf(address(this))
                );
            }
        } else {
            uint256 _amount0In = (_outputAmount * _getRatio(want)) / 10**18;
            uint256 _amount1In = _outputAmount - _amount0In;
            _swap(output, lpToken0, _amount0In);
            _swap(output, lpToken1, _amount1In);
        }

        uint256 _lp0Balance = (lpToken0 != wrapped)
            ? IERC20(lpToken0).balanceOf(address(this))
            : IERC20(lpToken0).balanceOf(address(this)) -
                _lpToken0BalanceBefore;
        uint256 _lp1Balance = (lpToken1 != wrapped)
            ? IERC20(lpToken1).balanceOf(address(this))
            : IERC20(lpToken1).balanceOf(address(this)) -
                _lpToken1BalanceBefore;

        // console.log(lpToken0);
        // console.log(lpToken1);
        // console.log("_lp0Balance", _lp0Balance);
        // console.log("_lp1Balance", _lp1Balance);
        //console.log("_lp0Balance new", _lp0Balance);
        //console.log("_lp1Balance new", _lp1Balance);

        IVelodromeRouter(unirouter).addLiquidity(
            lpToken0,
            lpToken1,
            isStable,
            _lp0Balance,
            _lp1Balance,
            1,
            1,
            address(this),
            block.timestamp
        );
        return IERC20(want).balanceOf(address(this)) - _wantBalanceBefore;
    }
}

