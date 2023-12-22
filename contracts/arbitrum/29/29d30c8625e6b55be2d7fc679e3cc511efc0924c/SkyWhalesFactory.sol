// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.6.12;

import "./ISkyWhalesFactory.sol";
import "./SkyWhalesPair.sol";

contract SkyWhalesFactory is ISkyWhalesFactory {
    address public override feeTo;
    address public override feeToSetter;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(SkyWhalesPair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'SkyWhales: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SkyWhales: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'SkyWhales: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(SkyWhalesPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        SkyWhalesPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(_feeTo != address(0), 'Null address not allowed!');
        require(msg.sender == feeToSetter, 'SkyWhales: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(_feeToSetter != address(0), 'Null address not allowed!');
        require(msg.sender == feeToSetter, 'SkyWhales: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

}

