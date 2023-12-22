// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SmolverseBridgeAdmin.sol";

/// @title Smolverse Bridge
/// @author Gearhart
/// @notice Stores stats, ERC1155s, and ERC721s deposited from approved collections to be spent in Smolverse.

contract SmolverseBridge is Initializable, SmolverseBridgeAdmin {

    // -------------------------------------------------------------
    //                      EXTERNAL FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc ISmolverseBridge
    function depositStats(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _statIds, 
        uint256[] calldata _amounts
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _collections.length;
        _checkLengths(length, _tokenIds.length);
        _checkLengths(length, _statIds.length);
        _checkLengths(length, _amounts.length);

        // loop through individual deposits
        for (uint256 i = 0; i < length; i++) {
            _depositStats(msg.sender, _collections[i], _tokenIds[i], _statIds[i], _amounts[i]);
        }
    }

    /// @inheritdoc ISmolverseBridge
    function depositERC20s(
        address[] calldata _tokens, 
        uint256[] calldata _amounts
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _tokens.length;
        _checkLengths(length, _amounts.length);

        // loop through individual deposits
        for (uint256 i = 0; i < length; i++) {
            _deposit20s(msg.sender, _tokens[i], _amounts[i]);
        }
    }

    /// @inheritdoc ISmolverseBridge
    function depositERC1155s(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _amounts
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _collections.length;
        _checkLengths(length, _tokenIds.length);
        _checkLengths(length, _amounts.length);

        // loop through individual deposits
        for (uint256 i = 0; i < length; i++) {
            _deposit1155s(msg.sender, _collections[i], _tokenIds[i], _amounts[i]);
        }
    }

    /// @inheritdoc ISmolverseBridge
    function depositERC721s(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _collections.length;
        _checkLengths(length, _tokenIds.length);

        // loop through individual deposits
        for (uint256 i = 0; i < length; i++) {
            _deposit721(msg.sender, _collections[i], _tokenIds[i]);
        }
    }

    /// @inheritdoc ISmolverseBridge
    function withdrawStats(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _statIds, 
        uint256[] calldata _amounts
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _collections.length;
        _checkLengths(length, _tokenIds.length);
        _checkLengths(length, _statIds.length);
        _checkLengths(length, _amounts.length);

        // loop through individual withdrawals
        for (uint256 i = 0; i < length; i++) {
            _withdrawStats(msg.sender, _collections[i], _tokenIds[i], _statIds[i], _amounts[i]);
        }
    }

    /// @inheritdoc ISmolverseBridge
    function withdrawERC20s(
        address[] calldata _tokens, 
        uint256[] calldata _amounts
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _tokens.length;
        _checkLengths(length, _amounts.length);

        // loop through individual withdrawals
        for (uint256 i = 0; i < length; i++) {
            _withdraw20s(msg.sender, _tokens[i], _amounts[i]);
        }
    }

    /// @inheritdoc ISmolverseBridge
    function withdrawERC1155s(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _amounts
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _collections.length;
        _checkLengths(length, _tokenIds.length);
        _checkLengths(length, _amounts.length);

        // loop through individual withdrawals
        for (uint256 i = 0; i < length; i++) {
            _withdraw1155s(msg.sender, _collections[i], _tokenIds[i], _amounts[i]);
        }
    }

    /// @inheritdoc ISmolverseBridge
    function withdrawERC721s(
        address[] calldata _collections,
        uint256[] calldata _tokenIds
    ) external nonReentrant whenNotPaused contractsAreSet{
        // check input lengths
        uint256 length = _collections.length;
        _checkLengths(length, _tokenIds.length);

        // loop through individual withdrawals
        for (uint256 i = 0; i < length; i++) {
            _withdraw721(msg.sender, _collections[i], _tokenIds[i]);
        }
    }

    // -------------------------------------------------------------
    //                         INITIALIZER 
    // -------------------------------------------------------------

    function initialize() external initializer {
        SmolverseBridgeAdmin.__SmolverseBridgeAdmin_init();
    }
}
