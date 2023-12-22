// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.6.12;

import "./ISicleFactory.sol";
import "./SiclePair.sol";

//UniswapV2Factory
contract SicleFactory is ISicleFactory {
    address public override feeTo;
    address public override feeToStake;
    address public override feeToSetter;
    address public override migrator;

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
        return keccak256(type(SiclePair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'Sicle: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Sicle: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Sicle: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(SiclePair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        SiclePair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, 'Sicle: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToStake(address _feeToStake) external override {
        require(msg.sender == feeToSetter, 'Sicle: FORBIDDEN');
        feeToStake = _feeToStake;
    }

    function setMigrator(address _migrator) external override {
        require(msg.sender == feeToSetter, 'Sicle: FORBIDDEN');
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, 'Sicle: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

}
