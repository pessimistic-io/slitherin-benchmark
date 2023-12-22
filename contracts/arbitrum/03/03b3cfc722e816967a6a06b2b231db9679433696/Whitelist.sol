// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IInscriptionFactory.sol";

contract Whitelist {
    IInscriptionFactory public inscriptionFactory;
    mapping(address => mapping(address => bool)) private whitelist;
    mapping(address => uint256) public count;
    mapping(address => address) public operator;

    event Set(address deployer, address tokenAddress, address participant, bool status);
    event SetOperator(address deployer, address tokenAddress, address operator);

    constructor(IInscriptionFactory _inscriptionFactory) {
        inscriptionFactory = _inscriptionFactory;
    }

    function set(address _tokenAddress, address _participant, bool _status) public {
        (IInscriptionFactory.Token memory token, ,) = IInscriptionFactory(inscriptionFactory).getIncriptionByAddress(_tokenAddress);
        require(token.addr == _tokenAddress, "Token has not deployed");
        require(token.isWhitelist, "condition not whitelist");
        require(msg.sender == token.deployer || msg.sender == operator[_tokenAddress], "Only deployer or operator can set whitelist");

        bool currentStatus = whitelist[_tokenAddress][_participant];
        if(_status && !currentStatus) {
            count[_tokenAddress] = count[_tokenAddress] + 1;
            whitelist[_tokenAddress][_participant] = _status;
        } else if(!_status && currentStatus) {
            count[_tokenAddress] = count[_tokenAddress] - 1;
            whitelist[_tokenAddress][_participant] = _status;
        }
        emit Set(msg.sender, _tokenAddress, _participant, _status);
    }

    function batchSet(address _tokenAddress, address[] calldata _participants, bool _status) public {
        (IInscriptionFactory.Token memory token, ,) = IInscriptionFactory(inscriptionFactory).getIncriptionByAddress(_tokenAddress);
        require(token.addr == _tokenAddress, "Tick has not deployed");
        require(token.isWhitelist, "condition not whitelist");
        require(msg.sender == token.deployer || msg.sender == operator[_tokenAddress], "Only deployer or operator can batch set whitelist");

        for(uint16 i = 0; i < _participants.length; i++) {
            bool currentStatus = whitelist[_tokenAddress][_participants[i]];
            if(_status && !currentStatus) {
                count[_tokenAddress] = count[_tokenAddress] + 1;
                whitelist[_tokenAddress][_participants[i]] = _status;
            } else if(!_status && currentStatus) {
                count[_tokenAddress] = count[_tokenAddress] - 1;
                whitelist[_tokenAddress][_participants[i]] = _status;
            }
            emit Set(msg.sender, _tokenAddress, _participants[i], _status);
        }
    }

    function setOperator(address _tokenAddress, address _operator) public {
        (IInscriptionFactory.Token memory token, ,) = IInscriptionFactory(inscriptionFactory).getIncriptionByAddress(_tokenAddress);
        require(token.addr == _tokenAddress, "Tick has not deployed");
        require(token.isWhitelist, "condition not whitelist");
        require(token.deployer == msg.sender, "Only deployer can add whitelist");
        operator[_tokenAddress] = _operator;
        emit SetOperator(msg.sender, _tokenAddress, _operator);
    }

    function getStatus(address _tokenAddress, address _participant) public view returns(bool) {
        return whitelist[_tokenAddress][_participant];
    }

    function getCount(address _tokenAddress) public view returns(uint256) {
        return count[_tokenAddress];
    }
}
