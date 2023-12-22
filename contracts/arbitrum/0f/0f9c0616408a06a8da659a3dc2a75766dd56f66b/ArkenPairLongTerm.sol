// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.16;

import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

import "./IUniswapV2Callee.sol";
import "./IArkenPairLongTermFactory.sol";
import "./IArkenPairLongTerm.sol";
import "./IERC721URIProvider.sol";
import "./UQ112x112.sol";
import "./Math.sol";

import "./UniswapV2ERC721.sol";

// import 'hardhat/console.sol';

contract ArkenPairLongTerm is
    UniswapV2ERC721,
    ReentrancyGuard,
    Pausable,
    IArkenPairLongTerm
{
    using UQ112x112 for uint224;

    string private constant _name = 'Arken Long-Term LP';
    string private constant _symbol = 'ARKENLTLP';
    uint8 private _decimals;

    uint256 public constant override MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 public constant override MINIMUM_LOCK_TIME = 24 * 60 * 60; // 1 day

    address public override factory;
    address public override pauser;
    address public override token0;
    address public override token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;
    uint256 public override kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    mapping(uint256 => uint256) public mintedAt;
    mapping(uint256 => uint256) public unlockedAt;

    function pause() external override {
        require(msg.sender == pauser, 'ArkenPairLongTerm: FORBIDDEN');
        _pause();
    }

    function unpause() external override {
        require(msg.sender == pauser, 'ArkenPairLongTerm: FORBIDDEN');
        _unpause();
    }

    function setPauser(address _pauser) external override {
        require(msg.sender == pauser, 'ArkenPairLongTerm: FORBIDDEN');
        pauser = _pauser;
    }

    function getReserves()
        public
        view
        override
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getLiquidity(
        uint256 tokenId
    )
        public
        view
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        liquidity = liquidityOf(tokenId);
        amount0 = (reserve0 * liquidity) / totalSupply;
        amount1 = (reserve1 * liquidity) / totalSupply;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'ArkenPairLongTerm: TRANSFER_FAILED'
        );
    }

    constructor() {
        factory = msg.sender;
        pauser = msg.sender;
    }

    function name()
        public
        pure
        override(UniswapV2ERC721, IERC721Metadata)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        pure
        override(UniswapV2ERC721, IERC721Metadata)
        returns (string memory)
    {
        return _symbol;
    }

    function decimals()
        public
        view
        override(UniswapV2ERC721, IUniswapV2ERC721)
        returns (uint8)
    {
        return _decimals;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, 'ArkenPairLongTerm: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
        uint8 decimals0 = IERC20Metadata(_token0).decimals();
        uint8 decimals1 = IERC20Metadata(_token1).decimals();
        if (decimals0 == 0 || decimals1 == 0) _decimals = 18;
        else _decimals = (decimals0 + decimals1) / 2;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            'ArkenPairLongTerm: OVERFLOW'
        );
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                // * never overflows, and + overflow is desired
                price0CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                    timeElapsed;
                price1CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                    timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(
        address to,
        uint256 lockTime
    )
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 liquidity, uint256 tokenId)
    {
        require(to != address(0), 'ArkenPairLongTerm: ZERO_ADDRESS');
        require(
            lockTime >= MINIMUM_LOCK_TIME,
            'ArkenPairLongTerm: MINIMUM_LOCK_TIME'
        );
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently nonReentrant the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }
        require(
            liquidity > 0,
            'ArkenPairLongTerm: INSUFFICIENT_LIQUIDITY_MINTED'
        );
        tokenId = UniswapV2ERC721._mint(to, liquidity);
        mintedAt[tokenId] = block.timestamp;
        unlockedAt[tokenId] = block.timestamp + lockTime;

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(
        address to,
        uint256 tokenId
    )
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(to != address(0), 'ArkenPairLongTerm: ZERO_ADDRESS');
        require(
            ownerOf(tokenId) == address(this),
            'ArkenPairLongTerm: TOKEN_NOT_TRANSFERRED'
        );
        require(
            unlockedAt[tokenId] <= block.timestamp,
            'ArkenPairLongTerm: TOKEN_NOT_UNLOCKED'
        );
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = liquidityOf(tokenId);

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(
            amount0 > 0 && amount1 > 0,
            'ArkenPairLongTerm: INSUFFICIENT_LIQUIDITY_BURNED'
        );
        _burn(tokenId);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override nonReentrant whenNotPaused {
        require(
            amount0Out > 0 || amount1Out > 0,
            'ArkenPairLongTerm: INSUFFICIENT_OUTPUT_AMOUNT'
        );
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            'ArkenPairLongTerm: INSUFFICIENT_LIQUIDITY'
        );

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(
                to != _token0 && to != _token1,
                'ArkenPairLongTerm: INVALID_TO'
            );
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0)
                IUniswapV2Callee(to).uniswapV2Call(
                    msg.sender,
                    amount0Out,
                    amount1Out,
                    data
                );
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            'ArkenPairLongTerm: INSUFFICIENT_INPUT_AMOUNT'
        );
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
            require(
                balance0Adjusted * balance1Adjusted >=
                    uint256(_reserve0) * _reserve1 * 1e6,
                'ArkenPairLongTerm: K'
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external override nonReentrant {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(
            _token0,
            to,
            IERC20(_token0).balanceOf(address(this)) - reserve0
        );
        _safeTransfer(
            _token1,
            to,
            IERC20(_token1).balanceOf(address(this)) - reserve1
        );
    }

    // force reserves to match balances
    function sync() external override nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        UniswapV2ERC721._beforeTokenTransfer(from, to, tokenId);
        if (to == address(this)) {
            require(
                unlockedAt[tokenId] <= block.timestamp,
                'ArkenPairLongTerm: TOKEN_NOT_UNLOCKED'
            );
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return IERC721URIProvider(factory).baseURI();
    }
}

