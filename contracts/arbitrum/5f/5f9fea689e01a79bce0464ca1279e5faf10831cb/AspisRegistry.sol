/*
 * SPDX-License-Identifier:    MIT
 */

pragma solidity 0.8.10;

import "./EnumerableSet.sol";
import "./IAspisRegistry.sol";

contract AspisRegistry is IAspisRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable aspisGuardian;
    address public aspisPoolFactory;

    error RegistryNameAlreadyUsed(string name);

    event NewDAORegistered(address indexed dao, address indexed creator, address indexed token, string name);
    event ExchangeDecoderAdded(address indexed exchange, address decoder);

    mapping(string => bool) public daos;

    mapping(address => address) public exchangeToDecoder;

    EnumerableSet.AddressSet private aspisSupportedTradingProtocols;
    EnumerableSet.AddressSet private aspisSupportedTradingTokens;

    modifier isAspisGuardian() {
        require(msg.sender == aspisGuardian, "Unauthorized access");
        _;
    }

    constructor(address _aspisGuardian) {
        require(_aspisGuardian != address(0), "Zero address error");
        aspisGuardian = _aspisGuardian;
    }

    function updateAspisPoolFactory(address _factory) external isAspisGuardian {
        aspisPoolFactory = _factory;
    }

    function register(string calldata name, address dao, address creator, address token) external {
        require(msg.sender == aspisPoolFactory, "Caller must be pool factory");

        if (daos[name] != false) revert RegistryNameAlreadyUsed({name: name});

        daos[name] = true;

        emit NewDAORegistered(dao, creator, token, name);
    }

    function addDecoder(address _exchange, address _decoder) external isAspisGuardian {
        require(_exchange != address(0), "Zero addresses not allowed");

        exchangeToDecoder[_exchange] = _decoder;

        emit ExchangeDecoderAdded(_exchange, _decoder);
    }

    function addSupportedTradingProtocols(address[] memory _protocols) external isAspisGuardian {
        for (uint64 i = 0; i < _protocols.length; i++) {
            if (aspisSupportedTradingProtocols.contains(_protocols[i])) {
                revert("Duplicate protocol");
            } else {
                aspisSupportedTradingProtocols.add(_protocols[i]);
            }
        }
    }

    function removeSupportedTradingProtocols(address[] memory _protocols) external isAspisGuardian {
        for (uint64 i = 0; i < _protocols.length; i++) {
            aspisSupportedTradingProtocols.remove(_protocols[i]);
        }
    }

    function addSupportedTradingTokens(address[] memory _tokens) external isAspisGuardian {
        for (uint64 i = 0; i < _tokens.length; i++) {
            if (aspisSupportedTradingTokens.contains(_tokens[i])) {
                revert("Duplicate token");
            } else {
                aspisSupportedTradingTokens.add(_tokens[i]);
            }
        }
    }

    function removeSupportedTradingTokens(address[] memory _tokens) external isAspisGuardian {
        for (uint64 i = 0; i < _tokens.length; i++) {
            aspisSupportedTradingTokens.remove(_tokens[i]);
        }
    }

    function getDecoder(address _exchange) public view override returns (address) {
        return exchangeToDecoder[_exchange];
    }

    function isAspisSupportedTradingToken(address _token) public view override returns (bool) {
        return aspisSupportedTradingTokens.contains(_token);
    }

    function isAspisSupportedTradingProtocol(address _protocol) public view override returns (bool) {
        return aspisSupportedTradingProtocols.contains(_protocol);
    }

    function getAspisSupportedTradingProtocols() public view override returns (address[] memory) {
        return aspisSupportedTradingProtocols.values();
    }

    function getAspisSupportedTradingTokens() public view override returns (address[] memory) {
        return aspisSupportedTradingTokens.values();
    }
}

