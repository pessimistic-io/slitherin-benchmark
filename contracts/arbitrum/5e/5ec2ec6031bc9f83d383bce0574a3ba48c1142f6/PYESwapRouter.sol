// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {      SupportingSwap,      PYESwapLibrary,      TransferHelper,      FeeStore,      IPYESwapFactory,      IPYESwapPair,      IWETH,      IERC20  } from "./SupportingSwap.sol";

contract PYESwapRouter is SupportingSwap {

    constructor(
        address _factory, 
        uint8 _adminFee, 
        address _adminFeeAddress, 
        address _adminFeeSetter
    ) FeeStore(_factory, _adminFee, _adminFeeAddress, _adminFeeSetter) {
        factory = _factory;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function initialize(address _weth, address[] calldata _stables) external {
        require(msg.sender == adminFeeSetter && WETH == address(0), "Invalid Initialize call");
        require(_weth != address(0), "PYESwap: INVALID_ADDRESS");
        WETH = _weth;
        for (uint i = 0; i < _stables.length; i++) {
            require(_stables[i] != address(0), "PYESwap: INVALID_ADDRESS");
            stables[_stables[i]] = true;
        }
    }

    // **** ADD LIQUIDITY ****
    function addLiquidity(
        address tokenA,
        address tokenB,
        address feeTaker,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (
        uint amountA, 
        uint amountB, 
        uint liquidity
    ) {
        address pair;
        (amountA, amountB, pair) = _addLiquidity(
            tokenA, 
            tokenB, 
            feeTaker, 
            amountADesired, 
            amountBDesired, 
            amountAMin, 
            amountBMin
        );
        TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        TransferHelper.safeTransfer(tokenA, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), amountB);
        TransferHelper.safeTransfer(tokenB, pair, amountB);
        liquidity = IPYESwapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        address feeTaker,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (
        uint amountETH, 
        uint amountToken, 
        uint liquidity
    ) {
        address pair;
        (amountETH, amountToken, pair) = _addLiquidity(
            WETH,
            token,
            feeTaker,
            msg.value,
            amountTokenDesired,
            amountETHMin,
            amountTokenMin
        );

        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amountToken);
        TransferHelper.safeTransfer(token, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IPYESwapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = PYESwapLibrary.pairFor(tokenA, tokenB);
        uint value = approveMax ? type(uint).max - 1 : liquidity;
        IPYESwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = PYESwapLibrary.pairFor(token, WETH);
        uint value = approveMax ? type(uint).max - 1 : liquidity;
        IPYESwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = PYESwapLibrary.pairFor(token, WETH);
        uint value = approveMax ? type(uint).max - 1 : liquidity;
        IPYESwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = PYESwapLibrary.pairFor(tokenA, tokenB);
        TransferHelper.safeTransferFrom(pair, msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IPYESwapPair(pair).burn(to);
        (address token0,) = PYESwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "PYESwapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "PYESwapRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function getPair(address tokenA, address tokenB) public view returns (address) {
        return IPYESwapFactory(factory).getPair(tokenA, tokenB);
    }

    function getAmountsOut(
        uint amountIn, 
        address[] memory path, 
        uint totalFee
    ) public view virtual override returns (
        uint[] memory amounts
    ) {
        return PYESwapLibrary.getAmountsOut(amountIn, path, totalFee, adminFee);
    }

    function getAmountsIn(
        uint amountOut, 
        address[] memory path, 
        uint totalFee
    ) public view virtual override returns (
        uint[] memory amounts
    ) {
        return PYESwapLibrary.getAmountsIn(amountOut, path, totalFee, adminFee);
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        address feeTaker,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB, address pair) {
        // create the pair if it doesn't exist yet
        pair = getPair(tokenA, tokenB);
        if (pair == address(0)) {
            if(tokenA == WETH || stables[tokenA]) {
                pair = IPYESwapFactory(factory).createPair(tokenB, tokenA, feeTaker != address(0), feeTaker);
                pairFeeAddress[pair] = tokenA;
            } else {
                pair = IPYESwapFactory(factory).createPair(tokenA, tokenB, feeTaker != address(0), feeTaker);
                pairFeeAddress[pair] = tokenB;
            }
        }
        (uint reserveA, uint reserveB) = PYESwapLibrary.getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
            if (tokenA == WETH || stables[tokenA]) {
                pairFeeAddress[pair] = tokenA;
            } else {
                pairFeeAddress[pair] = tokenB;
            }
        } else {
            uint amountBOptimal = PYESwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "PYESwapRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = PYESwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "PYESwapRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

}

