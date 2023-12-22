// SPDX-License-Identifier:  WTFPL

pragma solidity ^0.8.9;

import "./ERC20.sol";

contract CandleStick is ERC20 {
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    // This varies across different chains! Specifically, this is for Arbitrum.
    address internal constant V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant WETH_ADDRESS =
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint24 internal constant FEE = 100;

    address public uniswapV3Pool;
    uint256 public bootTime;
    uint256 public maxHoldingAmount;
    string public twitter;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _totalSupply,
        string memory _twitter
    ) ERC20(name, symbol) {
        _mint(msg.sender, _totalSupply);
        maxHoldingAmount = _totalSupply / 200;
        uniswapV3Pool = u3address();
        twitter = _twitter;
        bootTime = block.timestamp + 259200;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(
            !(from == uniswapV3Pool &&
                block.timestamp < bootTime &&
                super.balanceOf(to) + amount > maxHoldingAmount),
            "Anti Whale"
        );
        emit Roar(
            from,
            to,
            "I am playing with candlestick charts for fun! Exciting!! Yaaayaya~"
        );
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    // Event to be emitted when a roar happens
    event Roar(address indexed from, address indexed to, string words);

    // Function to compute Uniswap v3 pool address
    function u3address() internal view returns (address) {
        address token0;
        address token1;
        if (WETH_ADDRESS < address(this)) {
            token0 = WETH_ADDRESS;
            token1 = address(this);
        } else {
            token1 = WETH_ADDRESS;
            token0 = address(this);
        }
        unchecked {
            return
                address(
                    uint160(
                        uint256(
                            keccak256(
                                abi.encodePacked(
                                    hex"ff",
                                    V3_FACTORY,
                                    keccak256(abi.encode(token0, token1, FEE)),
                                    POOL_INIT_CODE_HASH
                                )
                            )
                        )
                    )
                );
        }
    }
}

