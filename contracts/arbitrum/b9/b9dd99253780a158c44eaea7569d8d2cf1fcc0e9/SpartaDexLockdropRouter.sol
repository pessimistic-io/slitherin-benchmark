// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.18;

import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "./interfaces_IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "./interfaces_IUniswapV2Factory.sol";
import {IWNative} from "./IWNative.sol";
import {UniswapV2Library} from "./UniswapV2Library.sol";
import {TransferHelper} from "./TransferHelper.sol";
import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";

contract SpartaDexLockdropRouter is IUniswapV2Router02, IAccessControlHolder {
    error NotSupported();
    error OnlyLiquidityProviderRole();

    bytes32 public constant LIQUIDITY_PROVIDER =
        keccak256("LIQUIDITY_PROVIDER");

    address public immutable override factory;
    IAccessControl public immutable override acl;
    IWNative public immutable wNative;

    modifier ensure(uint deadline) {
        if (deadline < block.timestamp) {
            revert Expired();
        }
        _;
    }

    modifier onlyLiquidityProvider() {
        if (!acl.hasRole(LIQUIDITY_PROVIDER, msg.sender)) {
            revert OnlyLiquidityProviderRole();
        }
        _;
    }

    constructor(IAccessControl acl_, address factory_, IWNative wNative_) {
        acl = acl_;
        factory = factory_;
        wNative = wNative_;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
        external
        virtual
        override
        onlyLiquidityProvider
        ensure(deadline)
        returns (uint amountA, uint amountB, uint liquidity)
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address,
        uint,
        uint,
        uint,
        address,
        uint
    ) external payable virtual override returns (uint, uint, uint) {
        revert NotSupported();
    }

    function removeLiquidityETH(
        address,
        uint,
        uint,
        uint,
        address,
        uint
    ) public virtual override returns (uint, uint) {
        revert NotSupported();
    }

    function removeLiquidity(
        address,
        address,
        uint,
        uint,
        uint,
        address,
        uint
    ) public virtual override returns (uint, uint) {
        revert NotSupported();
    }

    function removeLiquidityWithPermit(
        address,
        address,
        uint,
        uint,
        uint,
        address,
        uint,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external virtual override returns (uint, uint) {
        revert NotSupported();
    }

    function removeLiquidityETHWithPermit(
        address,
        uint,
        uint,
        uint,
        address,
        uint,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external virtual override returns (uint, uint) {
        revert NotSupported();
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address,
        uint,
        uint,
        uint,
        address,
        uint,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external virtual override returns (uint) {
        revert NotSupported();
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address,
        uint,
        uint,
        uint,
        address,
        uint
    ) public virtual override returns (uint) {
        revert NotSupported();
    }

    function swapExactTokensForETH(
        uint,
        uint,
        address[] calldata,
        address,
        uint
    ) external virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function swapETHForExactTokens(
        uint,
        address[] calldata,
        address,
        uint
    ) external payable virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function swapExactETHForTokens(
        uint,
        address[] calldata,
        address,
        uint
    ) external payable virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function swapTokensForExactETH(
        uint,
        uint,
        address[] calldata,
        address,
        uint
    ) external virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function swapExactTokensForTokens(
        uint,
        uint,
        address[] calldata,
        address,
        uint
    ) external virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function swapTokensForExactTokens(
        uint,
        uint,
        address[] calldata,
        address,
        uint
    ) external virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint,
        uint,
        address[] calldata,
        address,
        uint
    ) external virtual override {
        revert NotSupported();
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint,
        address[] calldata,
        address,
        uint
    ) external payable virtual override {
        revert NotSupported();
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint,
        uint,
        address[] calldata,
        address,
        uint
    ) external virtual override {
        revert NotSupported();
    }

    function quote(
        uint,
        uint,
        uint
    ) public pure virtual override returns (uint) {
        revert NotSupported();
    }

    function getAmountOut(
        uint,
        uint,
        uint
    ) public pure virtual override returns (uint) {
        revert NotSupported();
    }

    function getAmountIn(
        uint,
        uint,
        uint
    ) public pure virtual override returns (uint) {
        revert NotSupported();
    }

    function getAmountsOut(
        uint,
        address[] memory
    ) public view virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function getAmountsIn(
        uint,
        address[] memory
    ) public view virtual override returns (uint[] memory) {
        revert NotSupported();
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert InsufficientBAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) {
                    revert InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
}

