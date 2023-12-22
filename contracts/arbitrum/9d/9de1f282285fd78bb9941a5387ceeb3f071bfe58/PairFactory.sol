// SPDX-License-Identifier: UNLICENSED

// Copyright (c) FloraLoans - All rights reserved
// https://twitter.com/Flora_Loans

pragma solidity 0.8.19;

import "./UpgradeableBeacon.sol";
import "./Ownable2Step.sol";
import "./Address.sol";
import "./IUniswapV3Factory.sol";

import "./LendingPair.sol";
import "./BeaconProxyPayable.sol";

import "./IPairFactory.sol";
import "./ILendingController.sol";
import "./ILendingPair.sol";
import "./IUnifiedOracleAggregator.sol";

/// @title Flora Loans Pair Factory Contract
/// @notice This contract is responsible for creating new LendingPair contracts.
/// @author 0xdev and Flora Loans Team
/// @custom:prerequisites a uniswap pool for the givend pair must be existing
contract PairFactory is IPairFactory, Ownable2Step {
    using Address for address;

    UpgradeableBeacon public immutable lendingPairMaster;
    address public immutable lpTokenMaster;
    address public immutable feeRecipient;
    ILendingController public immutable lendingController;

    mapping(address => mapping(address => address))
        public
        override pairByTokens;

    event PairCreated(
        address indexed pair,
        address indexed tokenA,
        address indexed tokenB
    );

    /// @notice Initializes the PairFactory contract with required parameters
    /// @dev before deployment: update BeaconProxyPayable.sol WETH address
    /// @param _lendingPairMaster The address of the UpgradeableBeacon contract for LendingPair
    /// @param _lpTokenMaster The address of the LP token master contract
    /// @param _feeRecipient The address of the fee recipient contract
    /// @param _lendingController The address of the LendingController contract
    constructor(
        address _lendingPairMaster,
        address _lpTokenMaster,
        address _feeRecipient,
        ILendingController _lendingController
    ) {
        require(
            _lendingPairMaster.isContract(),
            "PairFactory: _lendingPairMaster must be a contract"
        );
        require(
            _lpTokenMaster.isContract(),
            "PairFactory: _lpTokenMaster must be a contract"
        );
        require(
            _feeRecipient.isContract(),
            "PairFactory: _feeRecipient must be a contract"
        );
        require(
            address(_lendingController).isContract(),
            "PairFactory: _lendingController must be a contract"
        );

        lendingPairMaster = UpgradeableBeacon(_lendingPairMaster);
        lpTokenMaster = _lpTokenMaster;
        feeRecipient = _feeRecipient;
        lendingController = _lendingController;
    }

    /// @notice Creates a new Lending Pair without permission restrictions
    /// @dev Increases Cardinality for all pairs
    /// @param _baseToken The base token of the new Lending Pair
    /// @param _userToken The user token of the new Lending Pair
    /// @return Address of the newly created LendingPair
    function createPairPermissionless(
        address _baseToken,
        address _userToken
    ) external returns (address) {
        return _createPair(_baseToken, _userToken, true);
    }

    /// @notice Creates a new Lending Pair
    /// @dev This function will be deprecated (deleted or ownable) in the final release
    /// @param _token0 The first token of the new Lending Pair
    /// @param _token1 The second token of the new Lending Pair
    /// @return Address of the newly created LendingPair
    function createPair(
        address _token0,
        address _token1
    ) external returns (address) {
        return _createPair(_token0, _token1, false);
    }

    /// @notice Internal function to create a new Lending Pair
    /// @param _tokenA The first token of the new Lending Pair
    /// @param _tokenB The second token of the new Lending Pair
    /// @param _isPermissionless Whether the pair is being created permissionlessly or not
    /// @return Address of the newly created LendingPair
    function _createPair(
        address _tokenA,
        address _tokenB,
        bool _isPermissionless
    ) internal returns (address) {
        require(_tokenA != _tokenB, "PairFactory: duplicate tokens");
        require(
            _tokenA != address(0) && _tokenB != address(0),
            "PairFactory: zero address"
        );
        require(
            pairByTokens[_tokenA][_tokenB] == address(0),
            "PairFactory: already exists"
        );

        if (_isPermissionless) {
            require(
                lendingController.isBaseAsset(_tokenA) == true,
                "PairFactory: baseToken not supported by LendingController"
            );
            if (lendingController.hasChainlinkOracle(_tokenB) == false) {
                /// @dev Will revert if there are no pools available for the pair and period combination
                /// @dev Increases Cardinality for all pairs
                lendingController.preparePool(_tokenA, _tokenB);
            }
        } else {
            require(
                lendingController.tokenSupported(_tokenA) &&
                    lendingController.tokenSupported(_tokenB),
                "PairFactory: token not supported by LendingController"
            );
        }

        (address token0, address token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);

        address lendingPair = address(
            new BeaconProxyPayable(address(lendingPairMaster), "")
        );

        ILendingPair(lendingPair).initialize(
            lpTokenMaster,
            address(lendingController),
            feeRecipient,
            token0,
            token1
        );

        pairByTokens[token0][token1] = lendingPair;
        pairByTokens[token1][token0] = lendingPair;

        emit PairCreated(lendingPair, token0, token1);

        return lendingPair;
    }
}

