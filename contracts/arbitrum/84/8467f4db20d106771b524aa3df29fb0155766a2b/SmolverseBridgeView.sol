// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SmolverseBridgeState.sol";

/// @title Land Stat Bank
/// @author Gearhart
/// @notice View functions and checks to be used by Smolverse Bridge.

abstract contract SmolverseBridgeView is Initializable, SmolverseBridgeState {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //                 EXTERNAL VIEW FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc ISmolverseBridge
    function getIdsAvailableForDepositByCollection(
        address _collectionAddress
    ) external view returns(uint256[] memory) {
        return collectionToApprovedIds[_collectionAddress].values();
    }

    /// @inheritdoc ISmolverseBridge
    function areContractsSet() public view returns (bool) {
        return address(smolLand) != address(0) 
        && address(smolSchool) != address(0)
        && smolBrains != address(0)
        && deFragAssetManager != address(0)
        && deFragBalanceSheet != address(0);
    }

    // -------------------------------------------------------------
    //                    INTERNAL VIEW FUNCTIONS
    // -------------------------------------------------------------

    /// @dev Checks for both deposit types
    function _depositChecks(
        address _collectionAddress,
        uint256 _statOrTokenId
    ) internal view {
        // check stat/token ID approval
        if (!collectionToApprovedIds[_collectionAddress].contains(_statOrTokenId)) {
            revert IdNotApprovedForDeposit(_collectionAddress, _statOrTokenId);
        }
    }

    /// @dev Checks if ERC721 NFT is owned by user.
    function _check721Ownership(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId
    ) internal view {
        // verify NFT ownership
        address ownerAddress = IERC721(_collectionAddress).ownerOf(_tokenId);
        if (ownerAddress == _userAddress){
            return;
        }
        // DeFrag is only supported for SmolBrains
        else if (ownerAddress == deFragAssetManager && _collectionAddress == smolBrains) {
            _checkDeFragForSmolOwnership(_userAddress, _tokenId);
            return;
        }
        else {
            revert MustBeOwnerOfNFT(_collectionAddress, _tokenId, _userAddress, ownerAddress);
        }
    }

    /// @dev Checks if user has loaned out NFT with DeFrag.fi
    function _checkDeFragForSmolOwnership(
        address _userAddress,
        uint256 _tokenId
    ) internal view {
        // get full list of tokenIds deposited in DeFrag by user
        uint256[] memory tokenIdsHeldByDeFrag = IBalanceSheet(deFragBalanceSheet).getTokenIds(_userAddress);
        uint256 length = tokenIdsHeldByDeFrag.length;
        if (!IBalanceSheet(deFragBalanceSheet).isExistingUser(_userAddress) || length == 0) revert UserHasNoTokensOnDeFrag(_userAddress);
        // see if any of the tokens match _tokenId
        for (uint256 i = 0; i < length; i++) {
            // if so return
            if (tokenIdsHeldByDeFrag[i] == _tokenId){
                return;
            }
        }
        // if not revert
        revert MustBeOwnerOfNFT(smolBrains, _tokenId, _userAddress, deFragAssetManager);
    }

    /// @dev Checks if tokenId has enough deposited stats.
    function _checkStatBridgeBalance(
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _statId,
        uint256 _amount
    ) internal view {
        uint256 bal = collectionToStatBalance[_collectionAddress][_tokenId][_statId];
        if (bal < _amount) {
            revert InsufficientStatBalance(_collectionAddress, _tokenId, _statId, _amount, bal);
        }
    }

    /// @dev Checks if user has enough deposited ERC20s.
    function _check20BridgeBalance(
        address _userAddress,
        address _tokenAddress,
        uint256 _amount
    ) internal view {
        uint256 bal = userToERC20Balance[_userAddress][_tokenAddress];
        if (bal < _amount) {
            revert InsufficientERC20Balance(_tokenAddress, _amount, bal);
        }
    }

    /// @dev Checks if user has enough deposited ERC1155s.
    function _check1155BridgeBalance(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _amount
    ) internal view {
        uint256 _bal = userToERC1155Balance[_userAddress][_collectionAddress][_tokenId];
        if (_bal < _amount){
            revert InsufficientNFTBalance(_collectionAddress, _tokenId, _amount, _bal);
        }
    }

    ///@dev Checks stat ID.
    function _checkStatExistence(
        address _collectionAddress, 
        uint256 _statId
    ) internal view {
        // check if stat ID exists on smol school contract
        StatDetails memory statInfo = smolSchool.statDetails(
            _collectionAddress,
            _statId
        );
        if (!statInfo.exists){
            revert StatDoesNotExist(_collectionAddress, _statId);
        }
    }

    ///@dev checks amounts
    function _checkAmounts(
        uint256 _amount
    ) internal pure {
        // check amount
        if (_amount <= 0){
            revert AmountMustBeGreaterThanZero();
        }
    }

    /// @dev Check array lengths.
    function _checkLengths(
        uint256 target,
        uint256 length
    ) internal pure {
        if (target != length) {
            revert ArrayLengthMismatch();
        }
    }

    // -------------------------------------------------------------
    //                           MODIFIER
    // -------------------------------------------------------------

    /// @dev Modifier to verify contracts are set.
    modifier contractsAreSet() {
        if(!areContractsSet()){
            revert ContractsNotSet();
        }
        _;
    }

    // -------------------------------------------------------------
    //                         INITIALIZER
    // -------------------------------------------------------------

    function __SmolverseBridgeView_init() internal initializer {
            SmolverseBridgeState.__SmolverseBridgeState_init();
    }

}
