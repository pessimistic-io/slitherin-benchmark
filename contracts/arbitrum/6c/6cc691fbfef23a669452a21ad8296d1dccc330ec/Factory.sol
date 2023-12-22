// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./IFactory.sol";
// import "../../interfaces/IPair.sol";
import "./ProxyFactory.sol";

contract Factory is Initializable, IFactory {
    //
    bool public override isPaused;
    address public pauser;
    address public pendingPauser;
    address public override treasury;

    // Save pairCodeHash as a value than creating it on the fly
    bytes32 public pairCodeHash;

    address public proxyAdmin;
    address public pairImplementation;

    mapping(address => mapping(address => mapping(bool => address))) public override getPair;
    address[] public allPairs;
    /// @dev Simplified check if its a pair, given that `stable` flag might not be available in peripherals
    mapping(address => bool) public override isPair;

    // address internal _temp0;
    // address internal _temp1;
    // bool internal _temp;

    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint allPairsLength);

    function initialize(address _treasury, address _proxyAdmin, address _pairImplementation) public initializer {
        pauser = msg.sender;
        treasury = _treasury;

        require(_proxyAdmin != address(0), "Factory: _proxyAdmin zero address");
        require(_pairImplementation != address(0), "Factory: _pairImplementation zero address");

        proxyAdmin = _proxyAdmin;

        /// @dev Non-Upgradeable contracts to deploy as upgradeable using Proxy Factory
        pairImplementation = _pairImplementation;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function setPauser(address _pauser) external {
        require(msg.sender == pauser, "Factory: Not pauser");
        pendingPauser = _pauser;
    }

    function acceptPauser() external {
        require(msg.sender == pendingPauser, "Factory: Not pending pauser");
        pauser = pendingPauser;
    }

    function setPause(bool _state) external {
        require(msg.sender == pauser, "Factory: Not pauser");
        isPaused = _state;
    }

    function setPairCodeHash(bytes32 _pairCodeHash) external {
        require(msg.sender == pauser, "Factory: Not pauser");
        pairCodeHash = _pairCodeHash;
    }

    function setProxyAdmin(address newProxyAdmin) external {
        require(msg.sender == proxyAdmin, "Factory: Caller not proxyAdmin");
        proxyAdmin = newProxyAdmin;
    }

    function setImplementation(address _pairImplementation) external {
        require(msg.sender == proxyAdmin, "Factory: Caller not proxyAdmin");
        pairImplementation = _pairImplementation;
    }

    // function getInitializable() external view override returns (address, address, bool) {
    //   return (_temp0, _temp1, _temp);
    // }

    function createPair(address tokenA, address tokenB, bool stable) external override returns (address pair) {
        require((!isPaused) || (msg.sender == pauser), "Factory: PAUSED");
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Factory: ZERO_ADDRESS");
        require(getPair[token0][token1][stable] == address(0), "Factory: PAIR_EXISTS");
        // notice salt includes stable as well, 3 parameters

        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
        bytes memory payload = abi.encodeWithSignature("initialize(address,address,bool)", token0, token1, stable);
        pair = ProxyFactory.createTransparentProxy(pairImplementation, proxyAdmin, payload, salt);
        // IPair(pair).initialize(token0, token1, stable);

        /// @dev No need for extra variables either, since initialization is being handled from factory itself
        // (_temp0, _temp1, _temp) = (token0, token1, stable);
        // pair = address(new Pair{salt: salt}());

        getPair[token0][token1][stable] = pair;
        // populate mapping in the reverse direction
        getPair[token1][token0][stable] = pair;
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }
}

