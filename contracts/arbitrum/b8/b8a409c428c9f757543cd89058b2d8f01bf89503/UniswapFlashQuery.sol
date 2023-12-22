//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

pragma experimental ABIEncoderV2;

import "./ERC20.sol";

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

abstract contract UniswapV2Factory  {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    function getPool(address tokenA, address tokenB, uint24 num) external view virtual returns (address);
    function allPairsLength() external view virtual returns (uint);
}

// In order to quickly load up data from Uniswap-like market, this contract allows easy iteration with a single eth_call
contract UniswapFlashQuery {
    function getReservesByPairs(IUniswapV2Pair[] calldata _pairs) external view returns (uint256[2][] memory) {
        uint256[2][] memory result = new uint256[2][](_pairs.length);
        for (uint i = 0; i < _pairs.length; i++) {
            address _token1 = _pairs[i].token0();
            address _token2 = _pairs[i].token1();
            result[i][0] = IERC20(_token1).balanceOf(address(_pairs[i]));
            result[i][1] = IERC20(_token2).balanceOf(address(_pairs[i]));
        }
        return result;
    }

    function getPairsByIndexRange(UniswapV2Factory _uniswapFactory, uint256 _start, uint256 _stop) external view returns (address[3][] memory)  {
        uint256 _allPairsLength = _uniswapFactory.allPairsLength();
        if (_stop > _allPairsLength) {
            _stop = _allPairsLength;
        }
        require(_stop >= _start, "start cannot be higher than stop");
        uint256 _qty = _stop - _start;
        address[3][] memory result = new address[3][](_qty);
        for (uint i = 0; i < _qty; i++) {
            IUniswapV2Pair _uniswapPair = IUniswapV2Pair(_uniswapFactory.allPairs(_start + i));
            result[i][0] = _uniswapPair.token0();
            result[i][1] = _uniswapPair.token1();
            result[i][2] = address(_uniswapPair);
        }
        return result;
    }

    function getPairsByPool(UniswapV2Factory _uniswapFactory, address _token1, address _token2) external view returns (address)  {
        address result;
        IUniswapV2Pair _uniswapPair = IUniswapV2Pair(_uniswapFactory.getPool(_token1, _token2, 500));
        result = address(_uniswapPair);

        return result;
    }
}

