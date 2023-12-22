// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./EnumerableSet.sol";

import "./IDexSwapFactory.sol";
import "./DexSwapPair.sol";

contract DexSwapFactory is IDexSwapFactory, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _feeWhitelist;
    EnumerableSet.AddressSet private _peripheryWhitelist;
    EnumerableSet.AddressSet private _contractsWhitelist;

    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(DexSwapPair).creationCode));

    uint256 public fee;
    address public feeTo;
    address public feeToSetter;
    uint256 public protocolShare;

    address[] public allPairs;

    mapping(address => mapping(address => address)) public getPair;

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function contractsWhitelistList(uint256 offset, uint256 limit) external view returns (address[] memory output) {
        uint256 contractsWhitelistLength = _contractsWhitelist.length();
        if (offset >= contractsWhitelistLength) return new address[](0);
        uint256 to = offset + limit;
        if (contractsWhitelistLength < to) to = contractsWhitelistLength;
        output = new address[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = _contractsWhitelist.at(offset + i);
    }

    function contractsWhitelist(uint256 index) external view returns (address) {
        return _contractsWhitelist.at(index);
    }

    function contractsWhitelistContains(address contract_) external view returns (bool) {
        return _contractsWhitelist.contains(contract_);
    }

    function contractsWhitelistCount() external view returns (uint256) {
        return _contractsWhitelist.length();
    }

    function feeWhitelistList(uint256 offset, uint256 limit) external view returns (address[] memory output) {
        uint256 feeWhitelistLength = _feeWhitelist.length();
        if (offset >= feeWhitelistLength) return new address[](0);
        uint256 to = offset + limit;
        if (feeWhitelistLength < to) to = feeWhitelistLength;
        output = new address[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = _feeWhitelist.at(offset + i);
    }

    function feeWhitelist(uint256 index) external view returns (address) {
        return _feeWhitelist.at(index);
    }

    function feeWhitelistContains(address account) external view returns (bool) {
        return _feeWhitelist.contains(account);
    }

    function feeWhitelistCount() external view returns (uint256) {
        return _feeWhitelist.length();
    }

    function peripheryWhitelistList(uint256 offset, uint256 limit) external view returns (address[] memory output) {
        uint256 peripheryWhitelistLength = _peripheryWhitelist.length();
        if (offset >= peripheryWhitelistLength) return new address[](0);
        uint256 to = offset + limit;
        if (peripheryWhitelistLength < to) to = peripheryWhitelistLength;
        output = new address[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = _peripheryWhitelist.at(offset + i);
    }

    function peripheryWhitelist(uint256 index) external view returns (address) {
        return _peripheryWhitelist.at(index);
    }

    function peripheryWhitelistContains(address account) external view returns (bool) {
        return _peripheryWhitelist.contains(account);
    }

    function peripheryWhitelistCount() external view returns (uint256) {
        return _peripheryWhitelist.length();
    }

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        require(tokenA != tokenB, "DexSwapFactory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "DexSwapFactory: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "DexSwapFactory: PAIR_EXISTS");
        bytes memory bytecode = type(DexSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IDexSwapPair pair_ = IDexSwapPair(pair);
        pair_.initialize(token0, token1);
        pair_.updateFee(fee);
        pair_.updateProtocolShare(protocolShare);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function addContractsWhitelist(address[] memory contracts) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < contracts.length; i++) {
            require(contracts[i] != address(0), "DexSwapFactory: Contract is zero address");
            _contractsWhitelist.add(contracts[i]);
        }
        emit ContractsWhitelistAdded(contracts);
        return true;
    }

    function addFeeWhitelist(address[] memory accounts) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "DexSwapFactory: Account is zero address");
            _feeWhitelist.add(accounts[i]);
        }
        emit FeeWhitelistAdded(accounts);
        return true;
    }

    function addPeripheryWhitelist(address[] memory periphery) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < periphery.length; i++) {
            require(periphery[i] != address(0), "DexSwapFactory: Periphery is zero address");
            _peripheryWhitelist.add(periphery[i]);
        }
        emit PeripheryWhitelistAdded(periphery);
        return true;
    }

    function removeContractsWhitelist(address[] memory contracts) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < contracts.length; i++) {
            _contractsWhitelist.remove(contracts[i]);
        }
        emit ContractsWhitelistRemoved(contracts);
        return true;
    }

    function removeFeeWhitelist(address[] memory accounts) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < accounts.length; i++) {
            _feeWhitelist.remove(accounts[i]);
        }
        emit FeeWhitelistRemoved(accounts);
        return true;
    }

    function removePeripheryWhitelist(address[] memory periphery) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < periphery.length; i++) {
            _peripheryWhitelist.remove(periphery[i]);
        }
        emit PeripheryWhitelistRemoved(periphery);
        return true;
    }

    function skim(address token0, address token1, address to) external onlyOwner returns (bool) {
        require(to != address(0), "DexSwapFactory: Recipient is zero address");
        IDexSwapPair(getPair[token0][token1]).skim(to);
        emit Skimmed(token0, token1, to);
        return true;
    }

    function updateFee(uint256 fee_) external onlyOwner returns (bool) {
        fee = fee_;
        emit FeeUpdated(fee_);
        return true;
    }

    function updateProtocolShare(uint256 share) external onlyOwner returns (bool) {
        protocolShare = share;
        emit ProtocolShareUpdated(share);
        return true;
    }

    function updateFeePair(address token0, address token1, uint256 fee_) external onlyOwner returns (bool) {
        IDexSwapPair(getPair[token0][token1]).updateFee(fee_);
        emit FeePairUpdated(token0, token1, fee_);
        return true;
    }

    function updateProtocolSharePair(address token0, address token1, uint256 share) external onlyOwner returns (bool) {
        IDexSwapPair(getPair[token0][token1]).updateProtocolShare(share);
        emit ProtocolSharePairUpdated(token0, token1, share);
        return true;
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "DexSwapFactory: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "DexSwapFactory: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}

