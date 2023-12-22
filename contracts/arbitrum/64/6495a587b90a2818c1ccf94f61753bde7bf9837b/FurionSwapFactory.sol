// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./IFurionSwapFactory.sol";
import "./FurionSwapPair.sol";
import {IERC20} from "./IERC20.sol";

// import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/*
//===================================//
 ______ _   _______ _____ _____ _   _ 
 |  ___| | | | ___ \_   _|  _  | \ | |
 | |_  | | | | |_/ / | | | | | |  \| |
 |  _| | | | |    /  | | | | | | . ` |
 | |   | |_| | |\ \ _| |_\ \_/ / |\  |
 \_|    \___/\_| \_|\___/ \___/\_| \_/
//===================================//
* /

/**
 * @title Furion Swap Factory
 * @dev Factory contract to deploy new trading pair
 *      All token pairs are supported but with an indicator to show if one of them is Furion Tokens
 *      Furion Tokens refer to F-* token, FFT, and FUR
 */

contract FurionSwapFactory is IFurionSwapFactory {
    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    address private _owner;

    // token0 Address => token1 Address => Pool Address
    mapping(address => mapping(address => address)) public override getPair;
    mapping(address => mapping(address => bool)) public override isFurionPairs;

    // Store all the pairs' addresses
    address[] public allPairs;

    // Address of income maker, part of the transaction fee will be distributed to this address
    address public incomeMaker;

    // Swap fee proportion to income maker
    uint256 public incomeMakerProportion;

    address public furionLeverage;

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256 allPairsLength
    );
    event IncomeMakerProportionChanged(
        uint256 oldProportion,
        uint256 newProportion
    );
    event IncomeMakerAddressChanged(
        address oldIncomeMaker,
        address newIncomeMaker
    );

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    constructor(address _incomeMaker) {
        _owner = msg.sender;
        incomeMaker = _incomeMaker;
        // 1% of swap fee is distributed to income maker contract
        // Can be set later
        incomeMakerProportion = 1;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Modifiers *************************************** //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Set Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Set income maker proportion
     * @dev    Only callable by the owner
     * @param _proportion New proportion to income maker contract
     */
    function setIncomeMakerProportion(uint256 _proportion) external onlyOwner {
        emit IncomeMakerProportionChanged(incomeMakerProportion, _proportion);
        incomeMakerProportion = _proportion;
    }

    /**
     * @notice Set income maker address
     * @dev Only callable by the owner
     * @param _incomeMaker New income maker address
     */
    function setIncomeMakerAddress(address _incomeMaker) external onlyOwner {
        emit IncomeMakerAddressChanged(incomeMaker, _incomeMaker);
        incomeMaker = _incomeMaker;
    }

    function setLeverage(address _leverage) external onlyOwner {
        furionLeverage = _leverage;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Main Functions *********************************** //
    // ---------------------------------------------------------------------------------------- //

    function createPair(
        address _tokenA,
        address _tokenB
    ) external override returns (address _pair) {
        require(_tokenA != _tokenB, "FurionSwap: IDENTICAL_ADDRESSES");

        (address token0, address token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);

        require(token0 != address(0), "FurionSwap: ZERO_ADDRESS");
        require(
            getPair[token0][token1] == address(0),
            "FurionSwap: PAIR_EXISTS"
        ); // single check is sufficient

        bytes memory bytecode = type(FurionSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            _pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        FurionSwapPair(_pair).initialize(token0, token1);

        // populate mapping in the reverse direction
        getPair[token0][token1] = _pair;
        getPair[token1][token0] = _pair;

        allPairs.push(_pair);

        emit PairCreated(token0, token1, _pair, allPairs.length);
    }

    function transferWhenLeverage(
        address _pair,
        address _token,
        address _receiver,
        uint256 _amount
    ) external {
        require(msg.sender == furionLeverage, "FurionSwap: ONLY_LEVERAGE");
        FurionSwapPair(_pair).transferWhenLeverage(_token, _amount, _receiver);
    }
}

