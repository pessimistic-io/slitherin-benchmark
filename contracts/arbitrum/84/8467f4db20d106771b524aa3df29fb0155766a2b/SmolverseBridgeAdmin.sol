// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SmolverseBridgeInternal.sol";

/// @title Smolverse Bridge Admin
/// @author Gearhart
/// @notice Admin functions for Smolverse Bridge gated by various roles.

abstract contract SmolverseBridgeAdmin is Initializable, SmolverseBridgeInternal {

    // -------------------------------------------------------------
    //                    EXTERNAL ADMIN FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc ISmolverseBridge
    function spendStats(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _statId,
        uint256 _amount,
        uint256 _landId,
        string calldata _message
    ) external whenNotPaused contractsAreSet requiresRole(AUTHORIZED_BALANCE_ADJUSTER_ROLE){
        // check amount > 0
        _checkAmounts(_amount);
        // check land ownership
        _check721Ownership(_userAddress, smolLand, _landId);
        // check ownership for NFT that has the stats being spent
        if (_userAddress == deFragAssetManager) revert DeFragAssetManagerCannotBeUser();
        _check721Ownership(_userAddress, _collectionAddress, _tokenId);
        // check if NFT has enough deposited stats
        _checkStatBridgeBalance(_collectionAddress, _tokenId, _statId, _amount);
        // remove stats from deposited balance
        collectionToStatBalance[_collectionAddress][_tokenId][_statId] -= _amount;

        emit StatsSpent(
            _landId,
            _userAddress,
            _collectionAddress,
            _tokenId,
            _statId, 
            _amount,
            _message
        );
    }

    /// @inheritdoc ISmolverseBridge
    function spendERC20s(
        address _userAddress,
        address _tokenAddress,
        uint256 _amount,
        uint256 _landId,
        string calldata _message
    ) external whenNotPaused contractsAreSet requiresRole(AUTHORIZED_BALANCE_ADJUSTER_ROLE){
        // check amount > 0
        _checkAmounts(_amount);
        // check land ownership
        _check721Ownership(_userAddress, smolLand, _landId);
        // check user has enough deposited
        _check20BridgeBalance(_userAddress, _tokenAddress, _amount);
        // decrement users deposited balance
        userToERC20Balance[_userAddress][_tokenAddress] -= _amount;
        // increment contracts available balance
        userToERC20Balance[address(this)][_tokenAddress] += _amount;

        emit ERC20sSpent(
            _landId,
            _userAddress,
            _tokenAddress,
            _amount,
            _message
        );
    }

    /// @inheritdoc ISmolverseBridge
    function spendERC1155s(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _landId,
        string calldata _message
    ) external whenNotPaused contractsAreSet requiresRole(AUTHORIZED_BALANCE_ADJUSTER_ROLE){
        // check amount > 0
        _checkAmounts(_amount);
        // check land ownership
        _check721Ownership(_userAddress, smolLand, _landId);
        // check user has enough deposited
        _check1155BridgeBalance(_userAddress, _collectionAddress, _tokenId, _amount);
        // decrement users deposited balance
        userToERC1155Balance[_userAddress][_collectionAddress][_tokenId] -= _amount;
        // increment contracts available balance
        userToERC1155Balance[address(this)][_collectionAddress][_tokenId] += _amount;

        emit ERC1155sSpent(
            _landId,
            _userAddress,
            _collectionAddress,
            _tokenId,
            _amount,
            _message
        );
    }

    /// @inheritdoc ISmolverseBridge
    function spendERC721(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _landId,
        string calldata _message
    ) external whenNotPaused contractsAreSet requiresRole(AUTHORIZED_BALANCE_ADJUSTER_ROLE){
        // check land ownership
        _check721Ownership(_userAddress, smolLand, _landId);
        // double check token has been deposited
        if (!userToDepositedERC721s[_userAddress][_collectionAddress][_tokenId]){
            revert InsufficientNFTBalance(_collectionAddress, _tokenId, 1, 0);
        }
        // remove ERC 721 NFT from users deposited balance
        userToDepositedERC721s[_userAddress][_collectionAddress][_tokenId] = false;
        // add ERC 721 NFT ID to contracts available balance
        userToDepositedERC721s[address(this)][_collectionAddress][_tokenId] = true;

        emit ERC721Spent(
            _landId,
            _userAddress,
            _collectionAddress,
            _tokenId,
            _message
        );
    }

    /// @inheritdoc ISmolverseBridge
    function setCollectionStatDepositApproval(
        address _collectionAddress,
        bool _approved
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        // check if collection approval is actually being changed
        if (collectionToStatDepositApproval[_collectionAddress] == _approved) {
            revert AddressApprovalAlreadySet(_collectionAddress, _approved);
        }
        if (collectionToERC1155DepositApproval[_collectionAddress] || collectionToERC721DepositApproval[_collectionAddress] || addressToERC20DepositApproval[_collectionAddress]) {
            revert AddressCanOnlyBeApprovedForOneTypeOfDeposit();
        }
        // change collection approval
        collectionToStatDepositApproval[_collectionAddress] = _approved;

        emit CollectionStatDepositApprovalChanged(
            _collectionAddress,
            _approved
        );
    }

    function setERC20DepositApproval(
        address _tokenAddress,
        bool _approved
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        // check if token approval is actually being changed
        if (addressToERC20DepositApproval[_tokenAddress] == _approved) {
            revert AddressApprovalAlreadySet(_tokenAddress, _approved);
        }
        if (collectionToERC1155DepositApproval[_tokenAddress] || collectionToERC721DepositApproval[_tokenAddress] || collectionToStatDepositApproval[_tokenAddress]) {
            revert AddressCanOnlyBeApprovedForOneTypeOfDeposit();
        }
        // change token approval
        addressToERC20DepositApproval[_tokenAddress] = _approved;

        emit ERC20DepositApprovalChanged(
            _tokenAddress,
            _approved
        );
    }

    /// @inheritdoc ISmolverseBridge
    function setCollectionERC1155DepositApproval(
        address _collectionAddress,
        bool _approved
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        // check if collection approval is actually being changed
        if (collectionToERC1155DepositApproval[_collectionAddress] == _approved) {
            revert AddressApprovalAlreadySet(_collectionAddress, _approved);
        }
        if (collectionToERC721DepositApproval[_collectionAddress] || collectionToStatDepositApproval[_collectionAddress] || addressToERC20DepositApproval[_collectionAddress]) {
            revert AddressCanOnlyBeApprovedForOneTypeOfDeposit();
        }
        // change collection approval
        collectionToERC1155DepositApproval[_collectionAddress] = _approved;

        emit CollectionERC1155DepositApprovalChanged(
            _collectionAddress,
            _approved
        );
    }
        
    /// @inheritdoc ISmolverseBridge
    function setCollectionERC721DepositApproval(
        address _collectionAddress,
        bool _approved
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {       
        // check if collection approval is actually being changed
        if (collectionToERC721DepositApproval[_collectionAddress] == _approved) {
            revert AddressApprovalAlreadySet(_collectionAddress, _approved);
        }
        if (collectionToStatDepositApproval[_collectionAddress] || collectionToERC1155DepositApproval[_collectionAddress] || addressToERC20DepositApproval[_collectionAddress]) {
            revert AddressCanOnlyBeApprovedForOneTypeOfDeposit();
        }
        // change collection approval
        collectionToERC721DepositApproval[_collectionAddress] = _approved;

        emit CollectionERC721DepositApprovalChanged(
            _collectionAddress,
            _approved
        );
    }

    /// @inheritdoc ISmolverseBridge
    function setStatIdDepositApproval(
        address _collectionAddress,
        uint256 _statId,
        bool _approved
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        // check if collection is approved for stat deposits
        if (!collectionToStatDepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        // if granting approval
        if(_approved) {
            // check if stat ID exists
            _checkStatExistence(_collectionAddress, _statId);
            _grantIdDepositApproval(_collectionAddress, _statId);
        }
        // if revoking approval
        else {
            _revokeIdDepositApproval(_collectionAddress, _statId);
        }

        emit StatIdDepositApprovalChanged(
            _collectionAddress, 
            _statId,
            _approved
        );
    }

    /// @inheritdoc ISmolverseBridge
    function setERC1155TokenIdDepositApproval(
        address _collectionAddress,
        uint256 _tokenId,
        bool _approved
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        // check if collection is approved for ERC1155 token deposits
        if (!collectionToERC1155DepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        // if granting approval
        if(_approved) {
            _grantIdDepositApproval(_collectionAddress, _tokenId);
        }
        // if revoking approval
        else {
            _revokeIdDepositApproval(_collectionAddress, _tokenId);
        }

        emit TokenIdDepositApprovalChanged(
            _collectionAddress, 
            _tokenId,
            _approved
        );
    }

    /// @inheritdoc ISmolverseBridge
    function setContracts(
        address _smolLandAddress,
        address _smolSchoolAddress,
        address _smolBrainsAddress,
        address _deFragAssetManagerAddress,
        address _deFragBalanceSheetAddress
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        smolLand = _smolLandAddress;
        smolSchool = ISchool(_smolSchoolAddress);
        smolBrains = _smolBrainsAddress;
        deFragAssetManager = _deFragAssetManagerAddress;
        deFragBalanceSheet = _deFragBalanceSheetAddress;
        
        emit ContractsSet(
            _smolLandAddress, 
            _smolSchoolAddress,
            _smolBrainsAddress,
            _deFragAssetManagerAddress,
            _deFragBalanceSheetAddress
        );
    }

    // -------------------------------------------------------------
    //                         INITIALIZER 
    // -------------------------------------------------------------

    function __SmolverseBridgeAdmin_init() internal initializer {
        SmolverseBridgeInternal.__SmolverseBridgeInternal_init();
    }
}
