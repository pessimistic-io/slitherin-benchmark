// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SmolverseBridgeView.sol";

/// @title Smolverse Bridge Internal
/// @author Gearhart
/// @notice Internal helper functions for SmolverseBridge and SmolverseBridgeAdmin.

abstract contract SmolverseBridgeInternal is Initializable, SmolverseBridgeView {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //                  INTERNAL DEPOSIT FUNCTIONS
    // -------------------------------------------------------------

    /// @dev Deposits an NFTs stat balance into that NFTs account to be used on land.
    function _depositStats(
        address _userAddress,
        address _collectionAddress, 
        uint256 _tokenId, 
        uint256 _statId, 
        uint256 _amount
    ) internal {
        // checks
        _checkAmounts(_amount);
        // check if collection and stat ID are approved for stat deposits
        if (!collectionToStatDepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        _depositChecks(_collectionAddress, _statId);
        // check stat existence
        _checkStatExistence(_collectionAddress, _statId);
        // check NFT ownership
        _check721Ownership(_userAddress, _collectionAddress, _tokenId);
        // get stat balance from school
        TokenDetails memory tokenInfo = smolSchool.tokenDetails(
        _collectionAddress,
        uint64(_statId),
        _tokenId
        );
        // check stat balance
        if (uint256(tokenInfo.statAccrued) < _amount){
            revert InsufficientStatBalance(_collectionAddress, _tokenId, _statId, _amount, tokenInfo.statAccrued);
        }
        // call school to remove stats from NFT as allowed adjuster
        smolSchool.removeStatAsAllowedAdjuster(
            _collectionAddress, 
            uint64(_statId), 
            _tokenId, 
            uint128(_amount)
        );
        // add stats to token IDs deposited balance
        collectionToStatBalance[_collectionAddress][_tokenId][_statId] += _amount;
        
        emit StatsDeposited(
            _collectionAddress,
            _tokenId,
            _statId,
            _amount
        );
    }

    /// @dev Deposits ERC20s and updates that users balance.
    function _deposit20s(
        address _userAddress,
        address _tokenAddress, 
        uint256 _amount
    ) internal {
        // checks
        _checkAmounts(_amount);
        // check if token is approved for deposits
        if (!addressToERC20DepositApproval[_tokenAddress]){
            revert AddressNotApprovedForDeposit(_tokenAddress);
        }
        // check user balance
        uint256 bal = IERC20(_tokenAddress).balanceOf(_userAddress);
        if (bal < _amount){
            revert InsufficientERC20Balance(_tokenAddress, _amount, bal);
        }
        // send tokens to this contract from user
        IERC20(_tokenAddress).transferFrom(_userAddress, address(this), _amount);
        // add tokens to user balance
        userToERC20Balance[_userAddress][_tokenAddress] += _amount;

        emit ERC20sDeposited(
            _userAddress, 
            _tokenAddress, 
            _amount
        );
    }

    /// @dev Deposits ERC1155 NFTs and updates that users balance.
    function _deposit1155s(
        address _userAddress,
        address _collectionAddress, 
        uint256 _tokenId, 
        uint256 _amount
    ) internal {
        // checks
        _checkAmounts(_amount);
        _depositChecks(_collectionAddress, _tokenId);
        // check if collection is approved for 1155 deposits
        if (!collectionToERC1155DepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        // get users ERC 1155 token balance 
        uint256 bal = IERC1155(_collectionAddress).balanceOf(
            _userAddress, 
            _tokenId
        );
        //check if user has enough tokens to deposit
        if (bal < _amount){
            revert InsufficientNFTBalance(_collectionAddress, _tokenId, _amount, bal);
        }
        // send tokens to this contract from user
        IERC1155(_collectionAddress).safeTransferFrom(
            _userAddress, 
            address(this), 
            _tokenId, 
            _amount, 
            ""
        );
        // add nft amounts to user balance
        userToERC1155Balance[_userAddress][_collectionAddress][_tokenId] += _amount;
        
        emit ERC1155sDeposited(
            _userAddress, 
            _collectionAddress, 
            _tokenId, 
            _amount
        );
    }

    /// @dev Deposits ERC721 NFT and updates that users balance.
    function _deposit721(
        address _userAddress,
        address _collectionAddress, 
        uint256 _tokenId
    ) internal {
        // check if collection is approved for 721 deposits
        if (!collectionToERC721DepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        // check if user owns nft
        _check721Ownership(_userAddress, _collectionAddress, _tokenId);
        // send NFT to this contract from user
        IERC721(_collectionAddress).safeTransferFrom(
            _userAddress, 
            address(this), 
            _tokenId,
            ""
        );
        // add nft to user balance
        userToDepositedERC721s[_userAddress][_collectionAddress][_tokenId] = true;

        emit ERC721Deposited(
            _userAddress, 
            _collectionAddress, 
            _tokenId
        );
    }

    // -------------------------------------------------------------
    //                INTERNAL WITHDRAW FUNCTIONS
    // -------------------------------------------------------------
        
    /// @dev Withdraws an NFTs stat balance from that NFTs account.
    function _withdrawStats(
        address _userAddress,
        address _collectionAddress, 
        uint256 _tokenId, 
        uint256 _statId, 
        uint256 _amount
    ) internal {
        // checks
        _checkAmounts(_amount);
        // check if collection is approved for stat deposits
        if (!collectionToStatDepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        // check ownership of NFT
        _check721Ownership(_userAddress, _collectionAddress, _tokenId);
        // check if stat exists
        _checkStatExistence(_collectionAddress, _statId);
        // check deposited stat balance
        _checkStatBridgeBalance(_collectionAddress, _tokenId, _statId, _amount);
        // subtract stats from NFTs balance on this contract
        collectionToStatBalance[_collectionAddress][_tokenId][_statId] -= _amount;
        // call school to add stats to NFT as allowed adjuster
        smolSchool.addStatAsAllowedAdjuster(
            _collectionAddress, 
            uint64(_statId), 
            _tokenId, 
            uint128(_amount)
        );
        
        emit StatsWithdrawn(
            _collectionAddress, 
            _tokenId,
            _statId,
            _amount
        );
    }

    /// @dev Withdraws ERC20s from users balance.
    function _withdraw20s(
        address _userAddress,
        address _tokenAddress,
        uint256 _amount
    ) internal {
        // checks
        _checkAmounts(_amount);
        // check if ERC20 address is approved for deposits
        if (!addressToERC20DepositApproval[_tokenAddress]){
            revert AddressNotApprovedForDeposit(_tokenAddress);
        }
        // check deposited ERC20 balance
        _check20BridgeBalance(_userAddress, _tokenAddress, _amount);
        // subtract tokens from user balance
        userToERC20Balance[_userAddress][_tokenAddress] -= _amount;
        // send tokens to user
        IERC20(_tokenAddress).transfer(_userAddress, _amount);

        emit ERC20sWithdrawn(
            _userAddress, 
            _tokenAddress, 
            _amount
        );
    }

    /// @dev Withdraws ERC1155 NFTs from users balance.
    function _withdraw1155s(
        address _userAddress,
        address _collectionAddress, 
        uint256 _tokenId, 
        uint256 _amount
    ) internal {
        // checks
        _checkAmounts(_amount);
        // check if collection is approved for 1155 deposits
        if (!collectionToERC1155DepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        // check deposited 1155 nft balance
        _check1155BridgeBalance(_userAddress, _collectionAddress, _tokenId, _amount);
        // subtract nft amounts from user balance
        userToERC1155Balance[_userAddress][_collectionAddress][_tokenId] -= _amount;
        // send tokens to user
        IERC1155(_collectionAddress).safeTransferFrom(
            address(this), 
            _userAddress, 
            _tokenId, 
            _amount, 
            ""
        );

        emit ERC1155sWithdrawn(
            _userAddress, 
            _collectionAddress, 
            _tokenId, 
            _amount
        );
    }

    /// @dev Withdraws ERC721 NFT from users balance.
    function _withdraw721(
        address _userAddress,
        address _collectionAddress, 
        uint256 _tokenId
    ) internal {
        // checks
        if (!collectionToERC721DepositApproval[_collectionAddress]){
            revert AddressNotApprovedForDeposit(_collectionAddress);
        }
        // check if user deposited NFT
        if (!userToDepositedERC721s[_userAddress][_collectionAddress][_tokenId]){
            revert InsufficientNFTBalance(_collectionAddress, _tokenId, 1, 0);
        }
        // remove nft from user balance
        userToDepositedERC721s[_userAddress][_collectionAddress][_tokenId] = false;
        // send NFT to user
        IERC721(_collectionAddress).safeTransferFrom(
            address(this), 
            _userAddress, 
            _tokenId,
            ""
        );

        emit ERC721Withdrawn(
            _userAddress, 
            _collectionAddress, 
            _tokenId
        );
    }

    // -------------------------------------------------------------
    //                  INTERNAL ADMIN FUNCTIONS
    // -------------------------------------------------------------

    /// @dev Approves a stat/token ID for deposit.
    function _grantIdDepositApproval(
        address _collectionAddress, 
        uint256 _statOrNftId
    ) internal requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        // make sure stat id has not already been approved
        if (collectionToApprovedIds[_collectionAddress].contains(_statOrNftId)) {
            revert AlreadyApprovedForDeposit(_collectionAddress, _statOrNftId);
        }
        // add stat id to array of approved stats for a collection
        collectionToApprovedIds[_collectionAddress].add(_statOrNftId);
    }

    /// @dev Revokes a stat/token IDs deposit approval.
    function _revokeIdDepositApproval(
        address _collectionAddress,
        uint256 _statOrNftId
    ) internal requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        // make sure id has already been approved
        if (!collectionToApprovedIds[_collectionAddress].contains(_statOrNftId)) {
            revert IdNotApprovedForDeposit(_collectionAddress, _statOrNftId);
        }
        // remove stat id from array of approved stats for a collection
        collectionToApprovedIds[_collectionAddress].remove(_statOrNftId);
    }

    // -------------------------------------------------------------
    //                         INITIALIZER 
    // -------------------------------------------------------------

    function __SmolverseBridgeInternal_init() internal initializer {
        SmolverseBridgeView.__SmolverseBridgeView_init();
    }
}
