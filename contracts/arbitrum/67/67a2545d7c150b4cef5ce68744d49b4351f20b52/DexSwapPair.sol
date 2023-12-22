// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./DexSwapERC20.sol";
import "./Constants.sol";

import "./IERC20.sol";
import "./IDexSwapPair.sol";
import "./IDexSwapFactory.sol";
import "./IDexSwapCallee.sol";

import "./Math.sol";
import "./UQ112x112.sol";

contract DexSwapPair is IDexSwapPair, DexSwapERC20, Constants {
    using UQ112x112 for uint224;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 public constant MAX_FEE = 100;
    uint256 public constant MAX_PROTOCOL_SHARE = 100;

    uint256 public fee;
    uint256 public protocolShare;
    address public factory;
    address public token0;
    address public token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint256 internal decimals0;
    uint256 internal decimals1;

    uint256 private blockTimestampLast;
    uint112 private reserve0;
    uint112 private reserve1;
    uint256 private unlocked = 1;

    function getAmountIn(uint256 amountOut, address tokenIn, address caller) public view returns (uint256 amountIn) {
        (uint256 _reserve0, uint256 _reserve1, ) = getReserves();
        require(amountOut > 0, "DexSwapPair: INSUFFICIENT_INPUT_AMOUNT");
        require(_reserve0 > 0 && _reserve1 > 0, "DexSwapPair: INSUFFICIENT_LIQUIDITY");
        if (tokenIn == token1) (_reserve0, _reserve1) = (_reserve1, _reserve0);
        uint256 fee_ = IDexSwapFactory(factory).feeWhitelistContains(caller) ? 0 : fee;
        uint256 numerator = _reserve0 * amountOut * DIVIDER;
        uint256 denominator = (_reserve1 - amountOut) * (DIVIDER - fee_);
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountOut(uint256 amountIn, address tokenIn, address caller) public view returns (uint256 amountOut) {
        (uint256 _reserve0, uint256 _reserve1, ) = getReserves();
        require(amountIn > 0, "DexSwapPair: INSUFFICIENT_INPUT_AMOUNT");
        require(_reserve0 > 0 && _reserve1 > 0, "DexSwapPair: INSUFFICIENT_LIQUIDITY");
        uint256 fee_ = IDexSwapFactory(factory).feeWhitelistContains(caller) ? 0 : fee;
        if (tokenIn == token1) (_reserve0, _reserve1) = (_reserve1, _reserve0);
        uint amountInWithFee = amountIn * (DIVIDER - fee_);
        uint numerator = amountInWithFee * _reserve1;
        uint denominator = (_reserve0 * DIVIDER) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint256 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    constructor() {
        factory = msg.sender;
    }

    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "DexSwapPair: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function initialize(address _token0, address _token1) external onlyFactory {
        token0 = _token0;
        token1 = _token1;
        decimals0 = 10 ** IERC20(_token0).decimals();
        decimals1 = 10 ** IERC20(_token1).decimals();
    }

    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        require(liquidity > 0, "DexSwapPair: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;
        emit Mint(msg.sender, amount0, amount1);
    }

    function skim(address to) external onlyFactory lock {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external {
        _swap(amount0Out, amount1Out, to, address(0), data);
    }

    function swapFromPeriphery(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        address caller,
        bytes calldata data
    ) external {
        require(
            IDexSwapFactory(factory).peripheryWhitelistContains(msg.sender),
            "DexSwapPair: Caller is not periphery"
        );
        _swap(amount0Out, amount1Out, to, caller, data);
    }

    function updateFee(uint256 fee_) external onlyFactory returns (bool) {
        require(fee_ <= MAX_FEE, "DexSwapFactory: Fee gt MAX_FEE");
        fee = fee_;
        emit FeeUpdated(fee_);
        return true;
    }

    function updateProtocolShare(uint256 share) external onlyFactory returns (bool) {
        require(share <= MAX_PROTOCOL_SHARE, "DexSwapFactory: Share gt MAX_PROTOCOL_SHARE");
        protocolShare = share;
        emit ProtocolShareUpdated(share);
        return true;
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IDexSwapFactory(factory).feeTo();
        feeOn = feeTo != address(0) && protocolShare > 0;
        uint256 _kLast = kLast;
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = (totalSupply * (rootK - rootKLast)) * protocolShare;
                    uint256 denominator = (rootK * (MAX_PROTOCOL_SHARE - protocolShare)) + (rootKLast * protocolShare);
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "DexSwapPair: TRANSFER_FAILED");
    }

    function _swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        address caller,
        bytes calldata data
    ) private lock {
        IDexSwapFactory factory_ = IDexSwapFactory(factory);
        require(
            factory_.contractsWhitelistContains(address(0)) ||
                msg.sender == tx.origin ||
                factory_.contractsWhitelistContains(msg.sender),
            "DexSwapPair: Caller is invalid"
        );
        require(amount0Out > 0 || amount1Out > 0, "DexSwapPair: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "DexSwapPair: INSUFFICIENT_LIQUIDITY");
        uint256 balance0;
        uint256 balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "DexSwapPair: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            if (data.length > 0) IDexSwapCallee(to).dexSwapCall(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "DexSwapPair: INSUFFICIENT_INPUT_AMOUNT");
        {
            uint256 fee_ = (caller != address(0) && factory_.feeWhitelistContains(caller)) ? 0 : fee;
            uint256 balance0Adjusted = (balance0 * DIVIDER) - (amount0In * fee_);
            uint256 balance1Adjusted = (balance1 * DIVIDER) - (amount1In * fee_);
            require(
                balance0Adjusted * balance1Adjusted >= (uint256(_reserve0) * _reserve1) * DIVIDER ** 2,
                "DexSwapPair: K"
            );
        }
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "DexSwapPair: OVERFLOW");
        uint256 blockTimestamp = block.timestamp % 2 ** 32;
        uint256 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    modifier lock() {
        require(unlocked == 1, "DexSwapPair: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "DexSwapPair: Caller is not factory");
        _;
    }
}

