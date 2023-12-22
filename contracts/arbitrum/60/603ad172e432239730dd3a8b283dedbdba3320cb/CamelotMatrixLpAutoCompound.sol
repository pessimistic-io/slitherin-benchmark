// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";
import "./IUniswapV2Router02.sol";
import "./EnumerableSet.sol";
import "./INFTPool.sol";
import "./ICamelotRouter.sol";

/// @title Velodrome Matrix Lp AutoCompound Strategy
contract CamelotMatrixLpAutoCompound is MatrixLpAutoCompound {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    address public constant TREASURY = 0xEaD9f532C72CF35dAb18A42223eE7A1B19bC5aBF;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    bool public isStable;
    uint256 public positionId;
    uint256 lockDuration = 0;

    modifier isPositionSet() {
        if (positionId != 0) {
            _;
        }
    }

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        bool _isStable,
        address _vault,
        address _treasury
    ) MatrixLpAutoCompound(_want, _poolId, _masterchef, _output, _uniRouter, _vault, _treasury) {
        isStable = _isStable;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) external returns (bytes4) {
        require(msg.sender == masterchef, 'only-master');
        require(positionId == 0, 'position-set');
        positionId = tokenId;
        return this.onERC721Received.selector;
    }

    function onNFTWithdraw(
        address operator,
        uint256 tokenId,
        uint256 lpAmount
    ) external returns (bool) {
        require(msg.sender == masterchef, 'only-master');
        return true;
    }

    function onNFTAddToPosition(
        address operator,
        uint256 tokenId,
        uint256 lpAmount
    ) external returns (bool) {
        require(msg.sender == masterchef, 'only-master');
        return true;
    }

    function onNFTHarvest(
        address operator,
        address to,
        uint256 tokenId,
        uint256 grailAmount,
        uint256 xGrailAmount
    ) external returns (bool) {
        require(msg.sender == masterchef, 'only-master');
        return true;
    }

    function _initialize(
        address _masterchef,
        address _output,
        uint256 _poolId
    ) internal override {
        super._initialize(_masterchef, _output, _poolId);
    }

    function _setWhitelistedAddresses() internal override {
        wrapped = WETH;
        super._setWhitelistedAddresses();
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();
    }

    function totalValue() public view override returns (uint256) {
        (uint256 _totalStaked, , , , , , , ) = INFTPool(masterchef).getStakingPosition(positionId);
        return IERC20(want).balanceOf(address(this)) + _totalStaked;
    }

    function _beforeWithdraw(uint256 _amount) internal override {
        INFTPool(masterchef).withdrawFromPosition(positionId, _amount);
    }

    function _beforeHarvest() internal override {
        address[] memory _tokens = new address[](1);
        _tokens[0] = output;
        INFTPool(masterchef).harvestPosition(positionId);
    }

    function _deposit() internal virtual override {
        uint256 _wantBalance = IERC20(want).balanceOf(address(this));
        if (_wantBalance > 0) {
            if (positionId == 0) {
                INFTPool(masterchef).createPosition(_wantBalance, lockDuration);
            } else {
                INFTPool(masterchef).addToPosition(positionId, _wantBalance);
            }
        }
    }

    function _beforePanic() internal virtual override isPositionSet {
        INFTPool(masterchef).emergencyWithdraw(positionId);
    }

    function _getRatio(address _lpToken) internal view returns (uint256) {
        address _token0 = IUniswapV2Pair(_lpToken).token0();
        address _token1 = IUniswapV2Pair(_lpToken).token1();

        (uint256 opLp0, uint256 opLp1, ) = IUniswapV2Pair(_lpToken).getReserves();
        uint256 lp0Amt = (opLp0 * (10**18)) / (10**IERC20Metadata(_token0).decimals());
        uint256 lp1Amt = (opLp1 * (10**18)) / (10**IERC20Metadata(_token1).decimals());
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

        ICamelotRouter(_swapPath.unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(_amount, 0, _swapPath.path, address(this), TREASURY, block.timestamp);

        _toTokenAmount = IERC20(_toToken).balanceOf(address(this)) - _toTokenBefore;
    }

    function _addLiquidity(uint256 _outputAmount) internal override returns (uint256 _wantHarvested) {
        uint256 _wantBalanceBefore = IERC20(want).balanceOf(address(this));
        uint256 _lpToken0BalanceBefore = IERC20(lpToken0).balanceOf(address(this));
        uint256 _lpToken1BalanceBefore = IERC20(lpToken1).balanceOf(address(this));

        if (!isStable) {
            if (output == lpToken0) {
                _swap(output, lpToken1, _outputAmount / 2);
            } else if (output == lpToken1) {
                _swap(output, lpToken0, _outputAmount / 2);
            } else {
                _swap(output, lpToken0, _outputAmount / 2);
                _swap(output, lpToken1, IERC20(output).balanceOf(address(this)));
            }
        } else {
            uint256 _amount0In = (_outputAmount * _getRatio(want)) / 10**18;
            uint256 _amount1In = _outputAmount - _amount0In;
            _swap(output, lpToken0, _amount0In);
            _swap(output, lpToken1, _amount1In);
        }

        uint256 _lp0Balance = (lpToken0 != wrapped) ? IERC20(lpToken0).balanceOf(address(this)) : IERC20(lpToken0).balanceOf(address(this)) - _lpToken0BalanceBefore;
        uint256 _lp1Balance = (lpToken1 != wrapped) ? IERC20(lpToken1).balanceOf(address(this)) : IERC20(lpToken1).balanceOf(address(this)) - _lpToken1BalanceBefore;

        // console.log(lpToken0);
        // console.log(lpToken1);
        // console.log("_lp0Balance", _lp0Balance);
        // console.log("_lp1Balance", _lp1Balance);
        //console.log("_lp0Balance new", _lp0Balance);
        //console.log("_lp1Balance new", _lp1Balance);

        ICamelotRouter(unirouter).addLiquidity(lpToken0, lpToken1, _lp0Balance, _lp1Balance, 1, 1, address(this), block.timestamp);
        return IERC20(want).balanceOf(address(this)) - _wantBalanceBefore;
    }
}

