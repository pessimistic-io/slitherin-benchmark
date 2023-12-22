pragma solidity =0.5.16;

import "./IZapfolioFactory.sol";
import "./ZapfolioPair.sol";

contract ZapfolioFactory is IZapfolioFactory {
    address public feeTo;
    address public feeToSetter;
    uint8 public protocolFeeDenominator = 9; // uses ~10% of each swap fee
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(ZapfolioPair).creationCode));

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
        require(tokenA != tokenB, 'ZapfolioFactory: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZapfolioFactory: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'ZapfolioFactory: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(ZapfolioPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IZapfolioPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'ZapfolioFactory: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'ZapfolioFactory: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
    
    function setProtocolFee(uint8 _protocolFeeDenominator) external {
        require(msg.sender == feeToSetter, 'ZapfolioFactory: FORBIDDEN');
        require(_protocolFeeDenominator > 0, 'ZapfolioFactory: FORBIDDEN_FEE');
        protocolFeeDenominator = _protocolFeeDenominator;
    }
    
    function setSwapFee(address _pair, uint32 _swapFee) external {
        require(msg.sender == feeToSetter, 'ZapfolioFactory: FORBIDDEN');
        IZapfolioPair(_pair).setSwapFee(_swapFee);
    }
}

