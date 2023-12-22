// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

import "./IOasisSwapFactory.sol";
import "./IRebateEstimator.sol";
import "./IMevController.sol";
import "./OasisSwapPair.sol";
import { Ownable } from "./Ownable.sol";

contract OasisSwapFactory is IOasisSwapFactory, Ownable, IRebateEstimator {
    address public override feeTo;
    address public override migrator;

    // fee customizability
    uint64 public fee = 100;
    uint64 public oasisFeeProportion = 5000;
    uint64 public constant FEE_DIVISOR = 10000;
    mapping(address => bool) public isFeeManager_;
    mapping(address => bool) public rebateApprovedRouters;
    address public override rebateManager;
    address mevController;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    address public rebateEstimator;

    constructor() public {
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external override pure returns (bytes32) {
        return keccak256(type(OasisSwapPair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'OasisSwap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'OasisSwap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'OasisSwap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(OasisSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        OasisSwapPair(pair).initialize(token0, token1, fee, oasisFeeProportion);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function mevControlPre(address sender) public override {
        if (mevController != address(0)) {
            IMevController(mevController).pre(msg.sender, sender);
        }
    }
    function mevControlPost(address sender) public override {
        if (mevController != address(0)) {
            IMevController(mevController).post(msg.sender, sender);
        }
    }

    function setMevController(address _mevController) public onlyOwner {
        mevController = _mevController;
    }

    function setFeeTo(address _feeTo) external override onlyOwner {
        feeTo = _feeTo;
    }

    function setMigrator(address _migrator) external override onlyOwner {
        migrator = _migrator;
    }

    function setFee(uint64 _fee, uint64 _oasisFeeProportion) external override onlyOwner {
        require(_fee <= FEE_DIVISOR, 'OasisSwap: FEE_TOO_HIGH');
        require(_oasisFeeProportion <= FEE_DIVISOR, 'OasisSwap: PROPORTION_TOO_HIGH');
        fee = _fee;
        oasisFeeProportion = _oasisFeeProportion;
    }

    function setFeeManager(address manager, bool _isFeeManager) external override onlyOwner {
        isFeeManager_[manager] = _isFeeManager;
    }

    function setRebateApprovedRouter(address router, bool state) external onlyOwner {
        rebateApprovedRouters[router] = state;
    }

    function setRebateManager(address _rebateManager) external onlyOwner {
        rebateManager = _rebateManager;
    }

    function changeOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "OasisSwap: ZERO_ADDRESS");

        transferOwnership(_newOwner);
    }

    function isFeeManager(address manager) external override view returns (bool) {
        return isFeeManager_[manager];
    }

    function isRebateApprovedRouter(address router) external override view returns (bool) {
        return rebateApprovedRouters[router];
    }

    function setRebateEstimator(address _rebateEstimator) external onlyOwner {
        rebateEstimator = _rebateEstimator;
    }

    function getRebate(address recipient) public override view returns (uint64) {
        if (rebateEstimator == address(0x0)) {
            return 0;
        }
        return IRebateEstimator(rebateEstimator).getRebate(recipient);
    }
}

