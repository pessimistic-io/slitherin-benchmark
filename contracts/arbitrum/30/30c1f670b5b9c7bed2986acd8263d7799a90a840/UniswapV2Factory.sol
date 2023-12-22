// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.6;
import "./Initializable.sol";
import "./Clones.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

contract UniswapV2Factory is Initializable, IUniswapV2Factory {
    address public override feeTo;
    address public override feeToSetter;
    address public override migrator;
    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;
    address public uniswapV2PairImplementation;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _feeToSetter,
        address _uniswapV2PairImplementation
    ) external initializer {
        feeToSetter = _feeToSetter;
        uniswapV2PairImplementation = _uniswapV2PairImplementation;
    }

    function allPairsLength() external view override returns (uint) {
        return allPairs.length;
    }

    function getProxyCode() internal view returns (bytes memory) {
        bytes
            memory _code = hex"3d602d80600a3d3981f3363d3d373d3d3d363d73bebebebebebebebebebebebebebebebebebebebe5af43d82803e903d91602b57fd5bf3";
        bytes20 _targetBytes = bytes20(uniswapV2PairImplementation);
        for (uint8 i = 0; i < 20; i++) {
            _code[20 + i] = _targetBytes[i];
        }
        return _code;
    }

    function pairCodeHash() public view returns (bytes32) {
        return keccak256(getProxyCode());
    }

    function createPair(address tokenA, address tokenB)
        external
        override
        returns (address pair)
    {
        require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");
        require(
            getPair[token0][token1] == address(0),
            "UniswapV2: PAIR_EXISTS"
        ); // single check is sufficient
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = Clones.cloneDeterministic(uniswapV2PairImplementation, salt);
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setMigrator(address _migrator) external override {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}

