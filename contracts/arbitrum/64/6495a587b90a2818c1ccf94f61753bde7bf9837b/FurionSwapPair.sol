// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {Math} from "./Math.sol";
import "./UQ112x112.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IFurionSwapFactory} from "./IFurionSwapFactory.sol";
import {IFurionSwapV2Callee} from "./IFurionSwapV2Callee.sol";

/*
//===================================//
 ______ _   _______ _____ _____ _   _ 
 |  ___| | | | ___ \_   _|  _  | \ | |
 | |_  | | | | |_/ / | | | | | |  \| |
 |  _| | | | |    /  | | | | | | . ` |
 | |   | |_| | |\ \ _| |_\ \_/ / |\  |
 \_|    \___/\_| \_|\___/ \___/\_| \_/
//===================================//
* /

/**
 * @title  FurionSwap Pair
 * @notice This is the contract for the FurionSwap swapping pair.
 *         Every time a new pair of tokens is available on FurionSwap
 *         The contract will be initialized with two tokens and a deadline.
 *         The swaps are only availale before the deadline.
 */

contract FurionSwapPair is
    ERC20("Furion Swap Pool LP", "FSL"),
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Minimum liquidity locked
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    // FurionSwapFactory contract address
    address public factory;

    // Token addresses in the pool, here token0 < token1
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    // Fee Rate, given to LP holders (0 ~ 1000)
    uint256 public feeRate = 3;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    // reserve0 * reserve1
    uint256 public kLast;

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event ReserveUpdated(uint112 reserve0, uint112 reserve1);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );

    constructor() {
        factory = msg.sender; // deployed by factory contract
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Init Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Initialize the contract status after the deployment by factory
     * @param _tokenA TokenA address
     * @param _tokenB TokenB address
     */
    function initialize(address _tokenA, address _tokenB) external {
        require(
            msg.sender == factory,
            "can only be initialized by the factory contract"
        );
        (token0, token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Get reserve0 and reserve1
     * @dev The result will depend on token orders
     * @return _reserve0 Reserve of token0
     * @return _reserve1 Reserve of token1
     */
    function getReserves()
        public
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)
    {
        (_reserve0, _reserve1, _blockTimestampLast) = (reserve0, reserve1, blockTimestampLast);
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Mint LP Token to liquidity providers
     *         Called when adding liquidity.
     * @param _to The user address
     * @return liquidity The LP token amount
     */
    function mint(
        address _to
    ) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings

        uint256 balance0 = IERC20(token0).balanceOf(address(this)); // token0 balance after deposit
        uint256 balance1 = IERC20(token1).balanceOf(address(this)); // token1 balance after deposit

        uint256 amount0 = balance0 - _reserve0; // just deposit
        uint256 amount1 = balance1 - _reserve1;

        // Distribute part of the fee to income maker
        bool feeOn = _mintFee(_reserve0, _reserve1);

        uint256 _totalSupply = totalSupply(); // gas savings

        if (_totalSupply == 0) {
            // No liquidity = First add liquidity
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            // Keep minimum liquidity to this contract
            _mint(factory, MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }

        require(liquidity > 0, "insufficient liquidity minted");
        _mint(_to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) kLast = uint256(reserve0) * reserve1;

        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @notice Burn LP tokens give back the original tokens
     * @param _to User address
     * @return amount0 Amount of token0 to be sent back
     * @return amount1 Amount of token1 to be sent back
     */
    function burn(
        address _to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings

        address _token0 = token0;
        address _token1 = token1;

        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));

        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);

        uint256 _totalSupply = totalSupply(); // gas savings

        // How many tokens to be sent back
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");

        // Currently all the liquidity in the pool was just sent by the user, so burn all
        _burn(address(this), liquidity);

        // Transfer tokens out and update the balance
        IERC20(_token0).safeTransfer(_to, amount0);
        IERC20(_token1).safeTransfer(_to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) kLast = uint256(_reserve0) * _reserve1;

        emit Burn(msg.sender, amount0, amount1, _to);
    }

    /**
     * @notice Finish the swap process
     * @param _amount0Out Amount of token0 to be given out (may be 0)
     * @param _amount1Out Amount of token1 to be given out (may be 0)
     * @param _to Address to receive the swap result
     */
    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        bytes calldata _data
    ) external nonReentrant {
        require(
            _amount0Out > 0 || _amount1Out > 0,
            "Output amount need to be positive"
        );

        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(
            _amount0Out < _reserve0 && _amount1Out < _reserve1,
            "Not enough liquidity"
        );

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(_to != _token0 && _to != _token1, "INVALID_TO");

            if (_amount0Out > 0) IERC20(_token0).safeTransfer(_to, _amount0Out);
            if (_amount1Out > 0) IERC20(_token1).safeTransfer(_to, _amount1Out);
            if (_data.length > 0) IFurionSwapV2Callee(_to).swapV2Call(msg.sender, _amount0Out, _amount1Out, _data);

            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - _amount0Out
            ? balance0 - (_reserve0 - _amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - _amount1Out
            ? balance1 - (_reserve1 - _amount1Out)
            : 0;

        require(amount0In > 0 || amount1In > 0, "INSUFFICIENT_INPUT_AMOUNT");

        {
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * feeRate;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * feeRate;

            require(
                balance0Adjusted * balance1Adjusted >=
                    uint256(_reserve0) * _reserve1 * (1000 ** 2),
                "The remaining x*y is less than K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);

        emit Swap(
            msg.sender,
            amount0In,
            amount1In,
            _amount0Out,
            _amount1Out,
            _to
        );
    }

    /**
     * @notice Syncrinize the status of this pool
     */
    function sync() external nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    // ---------------------------------------------------------------------------------------- //
    // ********************************** Internal Functions ********************************** //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Update the reserves of the pool
     * @param _balance0 Balance of token0
     * @param _balance1 Balance of token1
     */
    function _update(uint256 _balance0, uint256 _balance1, uint112 _reserve0, uint112 _reserve1) private {
        uint256 MAX_NUM = type(uint256).max;
        require(_balance0 <= MAX_NUM && _balance1 <= MAX_NUM, "uint OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }

        reserve0 = uint112(_balance0);
        reserve1 = uint112(_balance1);
        blockTimestampLast = blockTimestamp;

        emit ReserveUpdated(reserve0, reserve1);
    }

    /**
     * @notice Collect the income sharing from trading pair
     * @param _reserve0 Reserve of token0
     * @param _reserve1 Reserve of token1
     */
    function _mintFee(
        uint112 _reserve0,
        uint112 _reserve1
    ) private returns (bool feeOn) {
        address incomeMaker = IFurionSwapFactory(factory).incomeMaker();

        // If incomeMaker is not zero address, fee is on
        feeOn = incomeMaker != address(0);

        uint256 _k = kLast;

        if (feeOn) {
            if (_k != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_k);

                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() *
                        (rootK - rootKLast) *
                        10;

                    // (1 / φ) - 1
                    // Proportion got from factory is based on 100
                    // Use 1000/proportion to make it divided (donominator and numerator both * 10)
                    // p = 40 (2/5) => 1000/40 = 25
                    uint256 incomeMakerProportion = IFurionSwapFactory(factory)
                        .incomeMakerProportion();
                    uint256 denominator = rootK *
                        (1000 / incomeMakerProportion - 100) +
                        rootKLast *
                        100;

                    uint256 liquidity = numerator / denominator;

                    // Mint the liquidity to income maker contract
                    if (liquidity > 0) _mint(incomeMaker, liquidity);
                }
            }
        } else if (_k != 0) {
            kLast = 0;
        }
    }

    /**
     * @notice Get the smaller one of two numbers
     * @param x The first number
     * @param y The second number
     * @return z The smaller one
     */
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function transferWhenLeverage(
        address _token,
        uint256 _amount,
        address _receiver
    ) external {
        require(msg.sender == factory, "ONLY_FACTORY");
        require(_token == token0 || _token == token1, "INVALID_TOKEN");

        IERC20(_token).safeTransfer(_receiver, _amount);
    }
}

