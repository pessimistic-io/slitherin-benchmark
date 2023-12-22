// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

import "./CobraDexERC20.sol";
import "./Math.sol";
import "./UQ112x112.sol";
import "./IERC20.sol";
import "./ICobraDexFactory.sol";
import "./ICobraDexCallee.sol";
import "./IRebateEstimator.sol";

interface IMigrator {
    // Return the desired amount of liquidity token that the migrator wants.
    function desiredLiquidity() external view returns (uint256);
}

contract CobraDexPair is CobraDexERC20 {
    using SafeMathUniswap  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    // to set aside fees
    uint public feeCache0 = 0;
    uint public feeCache1 = 0;

    // fee customizability
    uint64 public fee;
    uint64 public cobradexFeeProportion;
    uint64 public constant FEE_DIVISOR = 10000;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'CobraDex: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }
    modifier mevControl() {
        ICobraDexFactory(factory).mevControlPre(msg.sender);
        _;
        ICobraDexFactory(factory).mevControlPost(msg.sender);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'CobraDex: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event SwapWithFee(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        uint feeTaken0,
        uint feeTaken1,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1, uint64 _fee, uint64 _cobradexFeeProportion) external {
        require(msg.sender == factory, 'CobraDex: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;

        setFee(_fee, _cobradexFeeProportion);
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'CobraDex: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = ICobraDexFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this)).sub(feeCache0);
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this)).sub(feeCache1);
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            address migrator = ICobraDexFactory(factory).migrator();
            if (msg.sender == migrator) {
                liquidity = IMigrator(migrator).desiredLiquidity();
                require(liquidity > 0 && liquidity != type(uint256).max, "Bad desired liquidity");
            } else {
                require(migrator == address(0), "Must not have migrator");
                liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            }
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'CobraDex: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20Uniswap(_token0).balanceOf(address(this)).sub(feeCache0);
        uint balance1 = IERC20Uniswap(_token1).balanceOf(address(this)).sub(feeCache1);
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'CobraDex: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20Uniswap(_token0).balanceOf(address(this)).sub(feeCache0);
        balance1 = IERC20Uniswap(_token1).balanceOf(address(this)).sub(feeCache1);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swapCalculatingRebate(uint amount0Out, uint amount1Out, address to, address feeController, bytes calldata data) external lock mevControl {
        require(feeController == msg.sender || feeController == tx.origin || feeController == to, "CobraDex: INVALID_FEE_CONTROLLER");
        uint64 feeRebate = IRebateEstimator(factory).getRebate(feeController);
        (uint amount0In, uint amount1In, uint feeTaken0, uint feeTaken1) = _swap(amount0Out, amount1Out, to, feeRebate, data);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit SwapWithFee(msg.sender, amount0In, amount1In, amount0Out, amount1Out, feeTaken0, feeTaken1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock mevControl {
        (uint amount0In, uint amount1In, uint feeTaken0, uint feeTaken1) = _swap(amount0Out, amount1Out, to, 0, data);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit SwapWithFee(msg.sender, amount0In, amount1In, amount0Out, amount1Out, feeTaken0, feeTaken1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swapWithRebate(uint amount0Out, uint amount1Out, address to, uint64 feeRebate, bytes calldata data) external lock mevControl {
        require(ICobraDexFactory(factory).isRebateApprovedRouter(msg.sender), "CobraDex: INVALID_REBATE_ORIGIN");
        require(feeRebate <= FEE_DIVISOR, "CobraDex: INVALID_REBATE");
        (uint amount0In, uint amount1In, uint feeTaken0, uint feeTaken1) = _swap(amount0Out, amount1Out, to, feeRebate, data);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit SwapWithFee(msg.sender, amount0In, amount1In, amount0Out, amount1Out, feeTaken0, feeTaken1, to);
    }

    function _swap(uint amount0Out, uint amount1Out, address to, uint64 feeRebate, bytes calldata data) internal returns (uint, uint, uint, uint){
        require(amount0Out > 0 || amount1Out > 0, 'CobraDex: INSUFFICIENT_OUTPUT_AMOUNT');
        uint112[] memory _reserve = new uint112[](2);
        (_reserve[0], _reserve[1],) = getReserves(); // gas savings
        require(amount0Out < _reserve[0] && amount1Out < _reserve[1], 'CobraDex: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // avoids stack too deep errors
        require(to != token0 && to != token1, 'CobraDex: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) ICobraDexCallee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20Uniswap(token0).balanceOf(address(this)).sub(feeCache0);
        balance1 = IERC20Uniswap(token1).balanceOf(address(this)).sub(feeCache1);
        }
        uint amount0In = balance0 > _reserve[0] - amount0Out ? balance0 - (_reserve[0] - amount0Out) : 0;
        uint amount1In = balance1 > _reserve[1] - amount1Out ? balance1 - (_reserve[1] - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'CobraDex: INSUFFICIENT_INPUT_AMOUNT');

        uint feeTaken0;
        uint feeTaken1;
        { // stack depth
        // calculate total fee
        { // stack depth
        uint _fee = _calculateFee(feeRebate);
        feeTaken0 = amount0In.mul(_fee);
        feeTaken1 = amount1In.mul(_fee);
        }
        { // stack depth
        // calculate resulting swap balances
        uint balance0Adjusted = balance0.mul(FEE_DIVISOR).sub(feeTaken0);
        uint balance1Adjusted = balance1.mul(FEE_DIVISOR).sub(feeTaken1);
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve[0]).mul(_reserve[1]).mul(FEE_DIVISOR**2), 'CobraDex: K');
        }
        // account for retained fees
        uint cobradexFee0;
        uint cobradexFee1;
        { // stack depth
        uint64 _cobradexFeeProportion = cobradexFeeProportion; // gas savings
        cobradexFee0 = feeTaken0.div(FEE_DIVISOR).mul(_cobradexFeeProportion).div(FEE_DIVISOR);
        cobradexFee1 = feeTaken1.div(FEE_DIVISOR).mul(_cobradexFeeProportion).div(FEE_DIVISOR);
        }
        balance0 = balance0.sub(cobradexFee0);
        balance1 = balance1.sub(cobradexFee1);
        feeCache0 = uint(feeCache0).add(cobradexFee0);
        feeCache1 = uint(feeCache1).add(cobradexFee1);
        }

        _update(balance0, balance1, _reserve[0], _reserve[1]);

        return (amount0In, amount1In, feeTaken0, feeTaken1);
    }

    function _calculateFee(uint64 feeRebate) internal view returns (uint256) {
        if (feeRebate == 0) {
            return fee;
        }
        // calculate fee rebate
        uint rebateFactor = uint(FEE_DIVISOR).sub(feeRebate);
        return uint(fee).mul(rebateFactor).div(FEE_DIVISOR);
    }
    function calculateFee(uint64 feeRebate) external view returns (uint256) {
        return _calculateFee(feeRebate);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20Uniswap(_token0).balanceOf(address(this)).sub(feeCache0).sub(reserve0));
        _safeTransfer(_token1, to, IERC20Uniswap(_token1).balanceOf(address(this)).sub(feeCache1).sub(reserve1));
    }

    function withdrawFee(address _to, bool _send0, bool _send1) external lock {
        uint256 _toSend0 = feeCache0;
        uint256 _toSend1 = feeCache1;
        feeCache0 = 0;
        feeCache1 = 0;
        require(ICobraDexFactory(factory).isFeeManager(msg.sender), 'CobraDex: FORBIDDEN');

        if (_send0) {
            _safeTransfer(token0, _to, _toSend0);
            _toSend0 = 0;
        }
        if (_send1) {
            _safeTransfer(token1, _to, _toSend1);
            _toSend1 = 0;
        }

        feeCache0 = _toSend0;
        feeCache1 = _toSend1;
    }

    function setFee(uint64 _fee, uint64 _cobradexFeeProportion) public {
        require(msg.sender == factory || ICobraDexFactory(factory).isFeeManager(msg.sender), 'CobraDex: FORBIDDEN');
        require(_fee <= FEE_DIVISOR, 'CobraDex: FEE_TOO_HIGH');
        require(_cobradexFeeProportion <= FEE_DIVISOR, 'CobraDex: PROPORTION_TOO_HIGH');
        fee = _fee;
        cobradexFeeProportion = _cobradexFeeProportion;
    }

    function getFeeDivisor() external pure returns (uint64) {
        return FEE_DIVISOR;
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20Uniswap(token0).balanceOf(address(this)).sub(feeCache0), IERC20Uniswap(token1).balanceOf(address(this)).sub(feeCache1), reserve0, reserve1);
    }
}

