// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.15;

import "./access_Ownable.sol";
import "./IProtocolsManager.sol";
import "./Constant.sol";


contract ProtocolsManager is IProtocolsManager, Ownable {

    struct Protocol {
        address contractAddress;
        bool allowed;

        mapping(uint=>Currency) currencyMap; // index is 1-based. 0 is invalid currency.
        mapping(address=>uint) currencyIndexMap;
        uint currencyCount;
    }

    struct Currency {
        address tokenAddress;
        bool enabled;
    }

    mapping (string => Protocol) public protocolsMap;

    event AddProtocol(string protocolName, address contractAddress, bool allowed);
    event PauseTrading(string protocolName, bool pause);
    event AddCurrency(string protocolName, address currency);
    event EnableCurrency(string protocolName, address currency, bool enable);
   

    function add(string memory protocolName, address contractAddress, bool allowTrading) external onlyOwner {
        require(bytes(protocolName).length > 0 && contractAddress != Constant.ZERO_ADDRESS, "Invalid params");
        Protocol storage p = protocolsMap[protocolName];
        require(p.contractAddress == Constant.ZERO_ADDRESS, "Already added");
        p.contractAddress = contractAddress;
        p.allowed = allowTrading;
        emit AddProtocol(protocolName, contractAddress, allowTrading);
    }

    function pause(string memory protocolName, bool setPause) external onlyOwner {
        Protocol storage p =  _get(protocolName, true);
        require(p.allowed == setPause, "Invalid state");
        p.allowed = !setPause;
        emit PauseTrading(protocolName, setPause);
    }

    function addCurrency(string memory protocolName, address[] memory tokens) external onlyOwner{
        Protocol storage p =  _get(protocolName, true);
        address token;
        uint len = tokens.length;
        for (uint n=0; n<len; n++) {
            token = tokens[n];
            require(token != Constant.ZERO_ADDRESS, "Invalid token");
            require(p.currencyIndexMap[token] == 0, "Currency existed"); // Make sure not exist
            p.currencyMap[++p.currencyCount] = Currency(token, true);
            p.currencyIndexMap[token] = p.currencyCount;
            emit AddCurrency(protocolName, token);
        }     
    }

    function enableCurrency(string memory protocolName, address token, bool enable)external {
        Currency storage c = _getCurrency(protocolName, token);
        require(c.tokenAddress != Constant.ZERO_ADDRESS, "Invalid currency");
        require(c.enabled != enable, "Invalid state");
        c.enabled = enable;
        emit EnableCurrency(protocolName, token, enable);
    }

    function query(string memory protocolName) external  override view returns (address contractAddress, bool allowTrading) {
        Protocol storage p =  _get(protocolName, false);
        contractAddress = p.contractAddress;
        allowTrading = p.allowed;
    }

    function isCurrencySupported(string memory protocolName, address token) external override view returns (bool) {
        Currency storage c = _getCurrency(protocolName, token);
        return c.enabled;
    }

    function _get(string memory protocolName, bool ensureValid) private view returns (Protocol storage p) {
        p = protocolsMap[protocolName];
        if (ensureValid) {
            require(p.contractAddress != Constant.ZERO_ADDRESS, "Invalid address");
        }
    }

    function _getCurrency(string memory protocolName, address token) private view returns (Currency storage) {
        Protocol storage p = protocolsMap[protocolName];
        uint index = p.currencyIndexMap[token];
        return p.currencyMap[index];
    }
}

