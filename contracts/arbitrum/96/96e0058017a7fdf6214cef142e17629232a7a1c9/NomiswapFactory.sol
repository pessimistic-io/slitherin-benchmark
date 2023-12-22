pragma solidity =0.5.16;

import "./INomiswapFactory.sol";
import "./NomiswapPair.sol";

contract NomiswapFactory is INomiswapFactory {

    address public feeTo;
    address public feeToSetter;
    bytes32 public INIT_CODE_HASH = keccak256(abi.encodePacked(type(NomiswapPair).creationCode));

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'Nomiswap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Nomiswap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Nomiswap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(NomiswapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        INomiswapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function setDevFee(address _pair, uint8 _devFee) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        require(_devFee > 0, 'Nomiswap: FORBIDDEN_FEE');
        INomiswapPair(_pair).setDevFee(_devFee);
    }

    function setSwapFee(address _pair, uint32 _swapFee) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        INomiswapPair(_pair).setSwapFee(_swapFee);
    }
}

