// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixStrategyBase.sol";
import "./MatrixSwapHelper.sol";
import "./IBeetsVault.sol";
import "./IMasterChef.sol";
import "./EnumerableSet.sol";
import "./IUniswapV2Router02.sol";

/// @title Beets Lp+MasterChef AutoCompound Strategy Framework,
contract BeetsMatrixLpAutoCompound is MatrixStrategyBase, MatrixSwapHelper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public immutable poolId;
    bytes32 public immutable vaultPoolId;
    address public immutable masterchef;

    address public output;
    address public output2;

    address[] public tokens;

    address public constant USDC = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant DEUS = 0xDE5ed76E7c05eC5e4572CfC88d1ACEA165109E44;
    address internal constant DEI = 0xDE1E704dae0B4051e80DAbB26ab6ad6c12262DA0;
    address internal constant SPOOKYSWAP_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    address internal constant RING = 0x582423C10c9e83387a96d00A69bA3D11ee47B7b5;

    address internal constant BEETS_VAULT =
        0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce;
    IBeetsVault internal constant beetsVault = IBeetsVault(BEETS_VAULT);

    // token index in LP used to swap rewards
    uint256 internal defaultTokenIndex = 0;

    constructor(
        address _want,
        uint256 _poolId,
        bytes32 _vaultPoolId,
        address _masterchef,
        address _output,
        address _output2,
        address _uniRouter,
        address _vault,
        address _treasury
    )
        MatrixStrategyBase(_want, _vault, _treasury)
        MatrixSwapHelper(_uniRouter)
    {
        masterchef = _masterchef;
        poolId = _poolId;
        vaultPoolId = _vaultPoolId;

        (address[] memory _tokens, , ) = beetsVault.getPoolTokens(_vaultPoolId);
        for (uint256 i; i < _tokens.length; i++) tokens.push(_tokens[i]);

        output = _output;
        output2 = _output2;

        _setWhitelistedAddresses();
        _setDefaultSwapPaths();
        _giveAllowances();
    }

    /// @notice Allows strategy governor to setup custom path and dexes for token swaps
    function setSwapPath(
        address _fromToken,
        address _toToken,
        address _unirouter,
        address[] memory _path
    ) external onlyOwner {
        _setSwapPath(_fromToken, _toToken, _unirouter, _path);
    }

    /// @notice Override this to enable other routers or token swap paths
    function _setWhitelistedAddresses() internal virtual {
        whitelistedAddresses.add(unirouter);
        whitelistedAddresses.add(SPOOKYSWAP_ROUTER);
        whitelistedAddresses.add(USDC);
        whitelistedAddresses.add(want);
        whitelistedAddresses.add(DEUS);
        whitelistedAddresses.add(DEI);
        whitelistedAddresses.add(WFTM);
        whitelistedAddresses.add(RING);
        whitelistedAddresses.add(output);
        if (output2 != address(0)) whitelistedAddresses.add(output2);
        whitelistedAddresses.add(wrapped);

        for (uint256 i; i < tokens.length; i++) {
            whitelistedAddresses.add(tokens[i]);
        }
    }

    function _setDefaultSwapPaths() internal virtual {
        for (uint256 i; i < tokens.length; i++) {
            if (tokens[i] == wrapped) {
                address[] memory _path = new address[](2);
                _path[0] = output;
                _path[1] = wrapped;
                _setSwapPath(output, tokens[i], address(0), _path);

                if (output2 != address(0)) {
                    address[] memory _path2 = new address[](2);
                    _path2[0] = output;
                    _path2[1] = wrapped;
                    _setSwapPath(output, tokens[i], address(0), _path2);
                }
            } else {
                if (tokens[i] != output) {
                    address[] memory _path = new address[](3);
                    _path[0] = output;
                    _path[1] = wrapped;
                    _path[2] = tokens[i];
                    _setSwapPath(output, tokens[i], address(0), _path);
                }
                if (tokens[i] != output2) {
                    address[] memory _path = new address[](3);
                    _path[0] = output2;
                    _path[1] = wrapped;
                    _path[2] = tokens[i];
                    _setSwapPath(output2, tokens[i], address(0), _path);
                }
            }
        }

        if (output != wrapped) {
            address[] memory _outputToWrapped = new address[](2);
            _outputToWrapped[0] = output;
            _outputToWrapped[1] = wrapped;
            _setSwapPath(output, wrapped, address(0), _outputToWrapped);
        }
        if (output2 != address(0) && output2 != wrapped) {
            address[] memory _output2ToWrapped = new address[](2);
            _output2ToWrapped[0] = output2;
            _output2ToWrapped[1] = wrapped;
            _setSwapPath(output2, wrapped, address(0), _output2ToWrapped);
        }

        // DEUS -> USDC
        address[] memory _deusUsdc = new address[](3);
        _deusUsdc[0] = DEUS;
        _deusUsdc[1] = WFTM;
        _deusUsdc[2] = USDC;
        _setSwapPath(DEUS, USDC, SPOOKYSWAP_ROUTER, _deusUsdc);

        // WFTM -> DEI
        address[] memory _wftmDei = new address[](3);
        _wftmDei[0] = WFTM;
        _wftmDei[1] = USDC;
        _wftmDei[2] = DEI;
        _setSwapPath(WFTM, DEI, SPOOKYSWAP_ROUTER, _wftmDei);

        // DEI -> WFTM
        address[] memory _deiWftm = new address[](3);
        _deiWftm[0] = DEI;
        _deiWftm[1] = USDC;
        _deiWftm[2] = WFTM;
        _setSwapPath(DEI, WFTM, SPOOKYSWAP_ROUTER, _deiWftm);

        // DEUS -> DEI
        address[] memory _deusDei = new address[](4);
        _deusDei[0] = DEUS;
        _deusDei[1] = WFTM;
        _deusDei[2] = USDC;
        _deusDei[3] = DEI;
        _setSwapPath(DEUS, DEI, SPOOKYSWAP_ROUTER, _deusDei);

        // RING -> USDC
        address[] memory _ringUsdc = new address[](2);
        _ringUsdc[0] = RING;
        _ringUsdc[1] = USDC;
        _setSwapPath(RING, USDC, SPOOKYSWAP_ROUTER, _ringUsdc);

        // RING -> WFTM
        address[] memory _ringWftm = new address[](3);
        _ringWftm[0] = RING;
        _ringWftm[1] = USDC;
        _ringWftm[2] = WFTM;
        _setSwapPath(RING, WFTM, SPOOKYSWAP_ROUTER, _ringWftm);
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(masterchef, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);

        if (output2 != address(0))
            IERC20(output2).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        if (output2 != address(0))
            IERC20(output2).safeApprove(unirouter, type(uint256).max);
    }

    /// @dev total value managed by strategy is want + want staked in MasterChef
    function totalValue() public view override returns (uint256) {
        (uint256 _totalStaked, ) = IMasterChef(masterchef).userInfo(
            poolId,
            address(this)
        );
        return IERC20(want).balanceOf(address(this)) + _totalStaked;
    }

    function _deposit() internal virtual override {
        uint256 _wantBalance = IERC20(want).balanceOf(address(this));
        IMasterChef(masterchef).deposit(poolId, _wantBalance, address(this));
    }

    function _beforeWithdraw(uint256 _amout) internal override {
        IMasterChef(masterchef).withdrawAndHarvest(
            poolId,
            _amout,
            address(this)
        );
    }

    function _harvest()
        internal
        virtual
        override
        returns (uint256 _wantHarvested, uint256 _wrappedFeesAccrued)
    {
        IMasterChef(masterchef).harvest(poolId, address(this));
        uint256 _outputBalance = IERC20(output).balanceOf(address(this));
        if (_outputBalance > 0) {
            _wrappedFeesAccrued = _swap(
                output,
                wrapped,
                (_outputBalance * totalFee) / PERCENT_DIVISOR
            );
        }
        if (output2 != address(0)) {
            uint256 _output2Balance = IERC20(output2).balanceOf(address(this));
            if (_output2Balance > 0) {
                _wrappedFeesAccrued += _swap(
                    output2,
                    wrapped,
                    (_output2Balance * totalFee) / PERCENT_DIVISOR
                );
            }
        }
        _wantHarvested = _addLiquidity();
    }

    function _addLiquidity() internal virtual returns (uint256 _wantHarvested) {
        uint256 _wantBalanceBefore = IERC20(want).balanceOf(address(this));

        uint256 _outputBalance = IERC20(output).balanceOf(address(this));
        if (_outputBalance > 0) {
            _swap(output, tokens[defaultTokenIndex], _outputBalance);
        }
        if (output2 != address(0)) {
            uint256 _output2Balance = IERC20(output2).balanceOf(address(this));
            if (_output2Balance > 0) {
                _swap(output2, tokens[defaultTokenIndex], _output2Balance);
            }
        }

        uint256 _tokenForLpBalance = IERC20(tokens[defaultTokenIndex])
            .balanceOf(address(this));

        if (_tokenForLpBalance > 0) {
            IERC20(tokens[defaultTokenIndex]).safeApprove(BEETS_VAULT, 0);
            IERC20(tokens[defaultTokenIndex]).safeApprove(
                BEETS_VAULT,
                _tokenForLpBalance
            );

            IVault.JoinPoolRequest memory _joinPoolRequest;
            _joinPoolRequest.assets = tokens;
            _joinPoolRequest.maxAmountsIn = new uint256[](tokens.length);
            _joinPoolRequest.maxAmountsIn[
                defaultTokenIndex
            ] = _tokenForLpBalance;
            _joinPoolRequest.userData = abi.encode(
                1,
                _joinPoolRequest.maxAmountsIn,
                1
            );

            beetsVault.joinPool(
                vaultPoolId,
                address(this),
                address(this),
                _joinPoolRequest
            );
        }

        return IERC20(want).balanceOf(address(this)) - _wantBalanceBefore;
    }

    function _beforePanic() internal virtual override {
        IMasterChef(masterchef).emergencyWithdraw(poolId, address(this));
    }

    /// @dev _beforeRetireStrat behaves exactly like _beforePanic hook
    function _beforeRetireStrat() internal override {
        _beforePanic();
    }
}

