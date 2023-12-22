// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./WhaleswapPair.sol";

contract WhaleswapFactory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => mapping(bool => address))) public getPair;
    address[] public allPairs;
    mapping(address => bool) public isPair; // Simplified check if its a pair, given that `stable` flag might not be available in peripherals

    address internal _temp0;
    address internal _temp1;
    bool internal _temp;

    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint);

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair) {
        require(tokenA != tokenB, 'Whaleswap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Whaleswap: ZERO_ADDRESS');
        require(getPair[token0][token1][stable] == address(0), 'Whaleswap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(WhaleswapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
        (_temp0, _temp1, _temp) = (token0, token1, stable);
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        getPair[token0][token1][stable] = pair;
        getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }

    function getInitializable() external view returns (address, address, bool) {
        return (_temp0, _temp1, _temp);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'Whaleswap: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'Whaleswap: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(WhaleswapPair).creationCode);
    }
}

