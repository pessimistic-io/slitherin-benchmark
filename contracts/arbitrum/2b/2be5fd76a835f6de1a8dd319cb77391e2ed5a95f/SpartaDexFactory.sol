//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {SpartaDexPair, IUniswapV2Pair} from "./SpartaDexPair.sol";
import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";

contract SpartaDexFactory is IUniswapV2Factory, IAccessControlHolder {
    error OnlyPairCreatorAccess();
    error OnlyLiquidityProviderAccess();

    bytes32 public constant INIT_CODE_PAIR_HASH =
        keccak256(abi.encodePacked(type(SpartaDexPair).creationCode));

    bytes32 internal constant PAIR_CREATOR = keccak256("PAIR_CREATOR");
    bytes32 internal constant LIQUIDITY_CONTROLLER =
        keccak256("LIQUIDITY_CONTROLLER");

    bool public restricted;
    address public override feeTo;
    address public override feeToSetter;
    IAccessControl public immutable override acl;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    modifier canCreatePair() {
        if (restricted && !acl.hasRole(PAIR_CREATOR, msg.sender)) {
            revert OnlyPairCreatorAccess();
        }
        _;
    }

    modifier onlyLiquidityController() {
        if (!acl.hasRole(LIQUIDITY_CONTROLLER, msg.sender)) {
            revert OnlyLiquidityProviderAccess();
        }
        _;
    }

    modifier onlyFeeToSetter() {
        if (feeToSetter != msg.sender) {
            revert OnlyFeeToSetter();
        }
        _;
    }

    constructor(address _feeToSetter, IAccessControl acl_) {
        feeToSetter = _feeToSetter;
        acl = acl_;
        restricted = true;
    }

    function allPairsLength() external view override returns (uint) {
        return allPairs.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external override canCreatePair returns (address pair) {
        if (tokenA == tokenB) {
            revert IdenticalAddress();
        }
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        if (token0 == address(0)) {
            revert ZeroAddress();
        }
        if (getPair[token0][token1] != address(0)) {
            revert PairAlreadyExists();
        }

        bytes memory bytecode = type(SpartaDexPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        pair = address(pairContract);
        pairContract.initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override onlyFeeToSetter {
        feeTo = _feeTo;
    }

    function setFeeToSetter(
        address _feeToSetter
    ) external override onlyFeeToSetter {
        feeToSetter = _feeToSetter;
    }

    function deactivate() external onlyLiquidityController {
        restricted = false;
    }
}

