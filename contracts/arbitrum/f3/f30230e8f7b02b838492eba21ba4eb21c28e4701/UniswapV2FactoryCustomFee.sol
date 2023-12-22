/* solhint-disable */
// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.5.16;

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./UniswapV2PairCustomFee.sol";
import "./IUniswapV2PairCustomFee.sol";

// Fork of Uniswap Factory allowing the deployer to set a Fee
// Changes from original denoted with CUSTOM FEE comments

contract UniswapV2FactoryCustomFee is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    // CUSTOM FEE: Add fee, owner, pendingOwner
    uint256 public fee;
    address public owner;
    address public pendingOwner;
    address public router;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
        // CUSTOM FEE: Set owner as sender
        owner = msg.sender;
    }

    // CUSTOM FEE: Add ownership
    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner: sender is not owner");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
    }

    function claimOwnership() external {
        require(msg.sender == pendingOwner, "claimOwnership: sender is not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    // store router address for default whitelist status
    function setRouter(address _router) public onlyOwner {
        router = _router;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        // CUSTOM FEE: use custom fee
        bytes memory bytecode = type(UniswapV2PairCustomFee).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // CUSTOM FEE: whitelist router to provide liquidity
        IUniswapV2Pair(pair).initialize(token0, token1);
        IUniswapV2PairCustomFee(pair).initializeFee(fee);
        if (router != address(0)) {
            IUniswapV2PairCustomFee(pair).setWhitelistStatus(router, true);
        }
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
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

    // CUSTOM FEE: function to set fee
    function setFee(uint256 newFee) public onlyOwner {
        require(newFee <= 1000, "Fee cannot be above 100%");
        fee = newFee;
    }

    // CUSTOM FEE: function to whitelist LP for a specific pair
    function setWhitelistStatus(address tokenA, address tokenB, address account, bool status) public onlyOwner {
        address pair = getPair[tokenA][tokenB];
        require(pair != address(0), "UniswapV2: PAIR_NOT_EXISTS");
        IUniswapV2PairCustomFee(pair).setWhitelistStatus(account, status);
    }
}
  /* solhint-enable */

