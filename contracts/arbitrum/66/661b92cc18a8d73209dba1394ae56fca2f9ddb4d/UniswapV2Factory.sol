pragma solidity =0.6.12;

import "./UniswapV2Pair.sol";
import "./Clones.sol";
import "./ICErc20.sol";
import "./ComptrollerInterface.sol";

contract UniswapV2Factory {
    address public feeTo;
    address public feeToSetter;
    address public implementation;
    address public comptroller;
    address public rateMoudel;

    mapping(address => mapping(address => address)) public getPair;
    mapping(address => address) public getCErc20;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter, address _implementation, address _comptroller, address _rateMoudel) public {
        feeToSetter = _feeToSetter;
        implementation = _implementation;
        comptroller = _comptroller;
        rateMoudel = _rateMoudel;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(UniswapV2Pair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        UniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);

        address cerc20 = Clones.cloneDeterministic(implementation, salt);
        ICErc20(cerc20).initialize(pair, comptroller, rateMoudel, 100e16, "C uniswapV2 LP", "CULP", 8);
        ComptrollerInterface(comptroller)._supportMarket(cerc20);
        ComptrollerInterface(comptroller)._setCollateralFactor(cerc20, 0.5e18);
        ComptrollerInterface(comptroller)._setBorrowPaused(cerc20, true);
        getCErc20[pair] = cerc20;
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}

