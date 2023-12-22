// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./AssimilatorV2.sol";
import "./Ownable.sol";
import "./IAssimilatorFactory.sol";
import "./IOracle.sol";

contract AssimilatorFactory is IAssimilatorFactory, Ownable {
    event NewAssimilator(
        address indexed caller,
        bytes32 indexed id,
        address indexed assimilator,
        address oracle,
        address token
    );
    event AssimilatorRevoked(
        address indexed caller,
        bytes32 indexed id,
        address indexed assimilator
    );
    event CurveFactoryUpdated(
        address indexed caller,
        address indexed curveFactory
    );
    mapping(bytes32 => AssimilatorV2) public assimilators;

    address public curveFactory;

    modifier onlyCurveFactoryOrOwner {
        require(msg.sender == curveFactory || msg.sender == owner(), "unauthorized");
        _;
    }

    function setCurveFactory(address _curveFactory) external onlyOwner {
        require(
            _curveFactory != address(0),
            "AssimFactory/curve factory zero address!"
        );
        curveFactory = _curveFactory;
        emit CurveFactoryUpdated(msg.sender, curveFactory);
    }

    function getAssimilator(address _token)
        external
        view
        override
        returns (AssimilatorV2)
    {
        bytes32 assimilatorID = keccak256(abi.encode(_token));
        return assimilators[assimilatorID];
    }

    function newAssimilator(
        IOracle _oracle,
        address _token,
        uint256 _tokenDecimals
    ) external override onlyCurveFactoryOrOwner returns (AssimilatorV2) {
        bytes32 assimilatorID = keccak256(abi.encode(_token));
        if (address(assimilators[assimilatorID]) != address(0))
            revert("AssimilatorFactory/oracle-stablecoin-pair-already-exists");
        AssimilatorV2 assimilator = new AssimilatorV2(
            _oracle,
            _token,
            _tokenDecimals,
            IOracle(_oracle).decimals()
        );
        assimilators[assimilatorID] = assimilator;
        emit NewAssimilator(
            msg.sender,
            assimilatorID,
            address(assimilator),
            address(_oracle),
            _token
        );
        return assimilator;
    }

    function revokeAssimilator(address _token) external onlyOwner {
        bytes32 assimilatorID = keccak256(abi.encode(_token));
        address _assimAddress = address(assimilators[assimilatorID]);
        assimilators[assimilatorID] = AssimilatorV2(address(0));
        emit AssimilatorRevoked(
            msg.sender,
            assimilatorID,
            address(_assimAddress)
        );
    }
}

