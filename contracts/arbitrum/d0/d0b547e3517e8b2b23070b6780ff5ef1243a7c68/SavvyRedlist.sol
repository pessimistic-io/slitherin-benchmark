// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC721.sol";
import "./Ownable2StepUpgradeable.sol";
import "./Mutex.sol";
import "./Checker.sol";
import "./IAllowlist.sol";
import "./ISavvyRedlist.sol";
import "./IVeSvy.sol";
import "./ISavvyToken.sol";

/// @title  SavvyRedlist
/// @author Savvy DeFi
contract SavvyRedlist is ISavvyRedlist, Ownable2StepUpgradeable, Mutex {
    /// @notice SVY required flag
    /// @dev true/false = turn on/off
    bool public protocolTokenRequired;

    // @dev The address of the protocol token contract ($SVY).
    address public protocolToken;

    // @dev The address of the protocol token contract ($veSVY).
    address public veProtocolToken;

    // @dev The address of the allowlist contract.
    address public allowlist;

    // @dev Array of all NFT collections that are eligible for redlist
    address[] public nftCollections;

    // @dev Mapping of NFT collections to their index in the nftCollections array
    mapping(address => uint256) public nftCollectionsToIndex;

    // @dev Cache of the last NFT used for each account
    mapping(address => address) public lastNFTUsedCache;

    /// @dev Checks if 'msg.sender' is allowlisted.
    modifier onlyAllowlisted() {
        Checker.checkArgument(
            IAllowlist(allowlist).isAllowed(msg.sender),
            "only allowlisted addresses can call this function"
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @dev Add null entry to index 0 because mapping cannot differentiate between null & index 0
    ///
    /// @dev Include all savvyPositionManagers & in the allowlist
    function initialize(
        bool protocolTokenRequired_,
        address protocolToken_,
        address veProtocolToken_,
        address allowlist_,
        address[] calldata nftCollections_
    ) external initializer {
        Checker.checkArgument(
            address(protocolToken_) != address(0),
            "protocolToken_ must be a valid contract"
        );
        Checker.checkArgument(
            address(veProtocolToken_) != address(0),
            "veProtocolToken_ must be a valid contract"
        );
        Checker.checkArgument(
            address(allowlist_) != address(0),
            "allowlist_ must be a valid contract"
        );

        allowlist = allowlist_;
        protocolTokenRequired = protocolTokenRequired_;
        protocolToken = protocolToken_;
        veProtocolToken = veProtocolToken_;

        // Add null entry to index 0 because mapping cannot differentiate between null & index 0
        nftCollections.push(address(0));
        for (uint256 i = 0; i < nftCollections_.length; i++) {
            address nftCollection = nftCollections_[i];
            Checker.checkArgument(
                address(nftCollection) != address(0),
                "nftCollection must be a valid contract"
            );
            nftCollections.push(nftCollection);
            nftCollectionsToIndex[nftCollection] = nftCollections.length - 1;
        }
        __Ownable_init();
    }

    /// @inheritdoc ISavvyRedlist
    function setProtocolTokenRequired(
        bool protocolTokenRequired_
    ) external override onlyOwner {
        protocolTokenRequired = protocolTokenRequired_;
        emit ProtocolTokenRequired(protocolTokenRequired_);
    }

    /// @inheritdoc ISavvyRedlist
    function setAllowlist(address allowlist_) external override onlyOwner {
        allowlist = allowlist_;
        emit AllowlistUpdated(allowlist_);
    }

    /// @inheritdoc ISavvyRedlist
    function getNFTCollections()
        external
        view
        override
        returns (address[] memory)
    {
        return nftCollections;
    }

    /// @inheritdoc ISavvyRedlist
    function isRedlistNFT(
        address nftCollection_
    ) public view override returns (bool) {
        return nftCollectionsToIndex[nftCollection_] != 0;
    }

    /// @inheritdoc ISavvyRedlist
    function addNFTCollection(address nftCollection_) external onlyOwner lock {
        Checker.checkArgument(
            address(nftCollection_) != address(0),
            "nftCollection_ must be a valid contract"
        );
        Checker.checkArgument(
            !isRedlistNFT(nftCollection_),
            "NFT collection is already added to the redlist"
        );
        uint256 index = nftCollections.length;
        nftCollections.push(nftCollection_);
        nftCollectionsToIndex[nftCollection_] = index;

        emit NFTCollectionAdded(nftCollection_);
    }

    /// @inheritdoc ISavvyRedlist
    function removeNFTCollection(
        address nftCollection_
    ) external override onlyOwner lock {
        Checker.checkArgument(
            isRedlistNFT(nftCollection_),
            "nftCollection_ is already removed from the redlist"
        );
        uint256 index = nftCollectionsToIndex[nftCollection_];
        Checker.checkArgument(
            nftCollection_ == nftCollections[index],
            "NFT collection mapping and array state is corrupted"
        );
        delete nftCollections[index];
        nftCollectionsToIndex[nftCollection_] = 0;

        emit NFTCollectionRemoved(nftCollection_);
    }

    /// @inheritdoc ISavvyRedlist
    function isRedlisted(
        address account_,
        bool eligibleNFTRequire_,
        bool isProtocolTokenRequire_
    ) external override onlyAllowlisted returns (bool) {
        Checker.checkArgument(
            address(account_) != address(0),
            "account_ must be a valid contract"
        );
        if (isProtocolTokenRequire_ && !_hasRequiredProtocolTokens(account_)) {
            return false;
        }

        if (!eligibleNFTRequire_) return true;

        address nftCollection = address(lastNFTUsedCache[account_]);
        if (_isNFTOwner(account_, nftCollection)) {
            if (isRedlistNFT(nftCollection)) {
                return true;
            }
        } else {
            //clear outdated cache
            delete lastNFTUsedCache[account_];
        }
        for (uint256 i = 1; i < nftCollections.length; i++) {
            nftCollection = address(nftCollections[i]);
            if (
                _isNFTOwner(account_, nftCollection) &&
                isRedlistNFT(nftCollection)
            ) {
                lastNFTUsedCache[account_] = nftCollection;
                return true;
            }
        }
        return false;
    }

    /// @notice Check that 'account_' owns at least one NFT from 'nftCollection_'.
    /// @param account_ The address of the account.
    /// @param nftCollection_ The NFT collection to check.
    /// @return True if 'account_' owns at least one NFT from 'nftCollection_'.
    function _isNFTOwner(
        address account_,
        address nftCollection_
    ) internal view returns (bool) {
        if (nftCollection_ == address(0)) return false;
        return IERC721(nftCollection_).balanceOf(account_) > 0;
    }

    /// @notice Check that 'account_' has the required amount of SVY.
    /// @dev If the 'protocolTokenRequired' is disabled, return true.
    /// @dev If the 'account_' has SVY in their wallet or staked in veSVY, return true.
    /// @param account_ The address of the account.
    /// @return True if 'account_' has the required amount of protocol tokens.
    function _hasRequiredProtocolTokens(
        address account_
    ) internal view returns (bool) {
        if (!protocolTokenRequired) {
            return true;
        }
        uint256 protocolTokenInWallet = ISavvyToken(protocolToken).balanceOf(
            account_
        );
        uint256 protocolTokenStaked = IVeSvy(veProtocolToken).getStakedSvy(
            account_
        );
        if (protocolTokenInWallet > 0 || protocolTokenStaked > 0) {
            return true;
        }
        return false;
    }

    uint256[100] private __gap;
}

