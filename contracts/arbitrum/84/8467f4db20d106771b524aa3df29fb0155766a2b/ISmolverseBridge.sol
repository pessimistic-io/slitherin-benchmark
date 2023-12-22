// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Smolverse Bridge Interface
/// @author Gearhart
/// @notice Interface containing all events, public/external functions, and custom errors for the Smolverse Bridge.

interface ISmolverseBridge {
        
    // -------------------------------------------------------------
    //                          EVENTS
    // -------------------------------------------------------------

    /// @notice Emitted when stats are deposited.
    /// @param _collectionAddress The address of the NFT collection that the stats were deposited from.
    /// @param _tokenId The token ID that the stats were deposited from.
    /// @param _statId The stat ID that was deposited.
    /// @param _amount The amount of the stat that was deposited.
    event StatsDeposited(
        address indexed _collectionAddress,
        uint256 indexed _tokenId,
        uint256 indexed _statId,
        uint256 _amount
    );

    /// @notice Emitted when ERC20 tokens are deposited.
    /// @param _userAddress The address of the wallet that deposited the tokens.
    /// @param _tokenAddress The address of the ERC20 contract that the tokens were deposited from.
    /// @param _amount The amount of tokens that were deposited.
    event ERC20sDeposited(
        address indexed _userAddress,
        address indexed _tokenAddress,
        uint256 _amount
    );

    /// @notice Emitted when ERC 1155 NFTs are deposited.
    /// @param _userAddress The address of the wallet that deposited the NFTs.
    /// @param _collectionAddress The address of the NFT collection that the NFTs were deposited from.
    /// @param _tokenId The ID of the tokens that were deposited.
    /// @param _amount The amount of the tokens that were deposited.
    event ERC1155sDeposited(
        address indexed _userAddress,
        address indexed _collectionAddress,
        uint256 indexed _tokenId,
        uint256 _amount
    );

    /// @notice Emitted when a ERC 721 NFT is deposited.
    /// @param _userAddress The address of the wallet that deposited the NFT.
    /// @param _collectionAddress The address of the NFT collection that the NFT was deposited from.
    /// @param _tokenId The ID of the token that was deposited.
    event ERC721Deposited(
        address indexed _userAddress,
        address indexed _collectionAddress,
        uint256 indexed _tokenId
    );

    /// @notice Emitted when stats are withdrawn.
    /// @param _collectionAddress The address of the NFT collection that the stats were withdrawn back to.
    /// @param _tokenId The token ID that the stats were withdrawn to.
    /// @param _statId The stat ID that was withdrawn.
    /// @param _amount The amount of the stat that was withdrawn.
    event StatsWithdrawn(
        address indexed _collectionAddress,
        uint256 indexed _tokenId,
        uint256 indexed _statId,
        uint256 _amount
    );

    /// @notice Emitted when ERC20 tokens are withdrawn.
    /// @param _userAddress The address of the wallet that withdrew the tokens.
    /// @param _tokenAddress The address of the ERC20 contract that the tokens were from.
    /// @param _amount The amount of tokens that were withdrawn.
    event ERC20sWithdrawn(
        address indexed _userAddress,
        address indexed _tokenAddress,
        uint256 _amount
    );

    /// @notice Emitted when ERC 1155 NFTs are withdrawn.
    /// @param _userAddress The address of the wallet that withdrew the NFTs.
    /// @param _collectionAddress The address of the NFT collection that the NFTs were from.
    /// @param _tokenId The ID of the tokens that were withdrawn.
    /// @param _amount The amount of the tokens that were withdrawn.
    event ERC1155sWithdrawn(
        address indexed _userAddress,
        address indexed _collectionAddress,
        uint256 indexed _tokenId,
        uint256 _amount
    );

    /// @notice Emitted when a ERC 721 NFT is withdrawn.
    /// @param _userAddress The address of the wallet that withdrew the NFT.
    /// @param _collectionAddress The address of the NFT collection that the NFT was from.
    /// @param _tokenId The ID of the token that was withdrawn.
    event ERC721Withdrawn(
        address indexed _userAddress,
        address indexed _collectionAddress,
        uint256 indexed _tokenId
    );

    /// @notice Emitted when stats are spent.
    /// @param _landId The land ID that the stats were spent on.
    /// @param _userAddress The address of the wallet that spent the stats.
    /// @param _collectionAddress The address of the NFT collection that the spent stats were from.
    /// @param _tokenId The token ID that the spent stats were deposited by.
    /// @param _statId The stat ID that was spent.
    /// @param _amount The amount of statId that was spent.
    /// @param _message The description of what the stats were spent on. 
    event StatsSpent(
        uint256 indexed _landId,
        address indexed _userAddress,
        address indexed _collectionAddress,
        uint256 _tokenId,
        uint256 _statId,
        uint256 _amount,
        string _message
    );

    /// @notice Emitted when ERC20 tokens are spent.
    /// @param _landId The land ID that the ERC20s were spent on.
    /// @param _userAddress The address of the wallet that spent the tokens.
    /// @param _tokenAddress The address of the ERC20 contract that the spent tokens were from.
    /// @param _amount The amount of tokens that were spent.
    /// @param _message The description of what the tokens were spent on.
    event ERC20sSpent(
        uint256 indexed _landId,
        address indexed _userAddress,
        address indexed _tokenAddress,
        uint256 _amount,
        string _message
    );

    /// @notice Emitted when ERC 1155 NFT tokens are spent.
    /// @param _landId The land ID that the ERC 1155 NFTs were spent on.
    /// @param _userAddress The address of the wallet that spent the NFTs.
    /// @param _collectionAddress The address of the NFT collection that the spent ERC 1155s were from.
    /// @param _tokenId The token IDs that were spent.
    /// @param _amount The amount of each 1155 token that was spent.
    /// @param _message The description of what the ERC 1155 NFTs were spent on. 
    event ERC1155sSpent(
        uint256 indexed _landId,
        address indexed _userAddress,
        address indexed _collectionAddress,
        uint256 _tokenId,
        uint256 _amount,
        string _message
    );

    /// @notice Emitted when ERC 721 NFT tokens are spent.
    /// @param _landId The land ID that the ERC 721 NFT was spent on.
    /// @param _userAddress The address of the wallet that spent the NFT.
    /// @param _collectionAddress The address of the NFT collection that the spent ERC 721 was from.
    /// @param _tokenId The token ID that was spent.
    /// @param _message The description of what the ERC 721 NFT was spent on.
    event ERC721Spent(
        uint256 indexed _landId,
        address indexed _userAddress,
        address indexed _collectionAddress,
        uint256 _tokenId,
        string _message
    );

    /// @notice Emitted when a collection has it's stat deposit approval changed.
    /// @param _collectionAddress The address of the NFT collection that was approved for stat deposit.
    /// @param _approved True if the collection was approved.
    event CollectionStatDepositApprovalChanged(
        address indexed _collectionAddress,
        bool indexed _approved
    );

    /// @notice Emitted when a collection has it's ERC1155 deposit approval changed.
    /// @param _collectionAddress The address of the NFT collection that was approved for ERC1155 deposit.
    /// @param _approved True if the collection was approved.
    event CollectionERC1155DepositApprovalChanged(
        address indexed _collectionAddress,
        bool indexed _approved
    );

    /// @notice Emitted when a collection has it's ERC721 deposit approval changed.
    /// @param _collectionAddress The address of the NFT collection that was approved for ERC721 deposit.
    /// @param _approved True if the collection was approved.
    event CollectionERC721DepositApprovalChanged(
        address indexed _collectionAddress,
        bool indexed _approved
    );

    /// @notice Emitted when an ERC20 token has it's deposit approval changed.
    /// @param _tokenAddress The address of the ERC20 token that was approved for deposit.
    /// @param _approved True if the token was approved.
    event ERC20DepositApprovalChanged(
        address indexed _tokenAddress,
        bool indexed _approved
    );

    /// @notice Emitted when a Stat ID has it's deposit approval changed.
    /// @param _collectionAddress The address of the NFT collection that the stat is from.
    /// @param _statId The stat ID that was approved or revoked.
    /// @param _approved True if the stat was approved for deposit.
    event StatIdDepositApprovalChanged(
        address indexed _collectionAddress,
        uint256 indexed _statId,
        bool indexed _approved
    );

    /// @notice Emitted when a ERC1155 NFT ID has it's deposit approval changed.
    /// @param _collectionAddress The address of the NFT collection that the ERC1155 NFT is from.
    /// @param _tokenId The ERC1155 NFT ID that was approved or revoked.
    /// @param _approved True if the ERC1155 NFT was approved for deposit.
    event TokenIdDepositApprovalChanged(
        address indexed _collectionAddress,
        uint256 indexed _tokenId,
        bool indexed _approved
    );

    /// @notice Emitted when the contracts are set.
    /// @param _smolLandAddress The address of the SmolLand contract.
    /// @param _smolSchoolAddress The address of the SmolSchool contract.
    /// @param _smolBrainsAddress The address of the SmolBrains contract.
    /// @param _deFragAssetManagerAddress The address of the DeFrag Finance Asset Manager contract.
    /// @param _deFragBalanceSheetAddress The address of the DeFrag Finance Balance Sheet contract.
    event ContractsSet(
        address _smolLandAddress,
        address _smolSchoolAddress,
        address _smolBrainsAddress,
        address _deFragAssetManagerAddress,
        address _deFragBalanceSheetAddress
    );

    //-------------------------------------------------------------
    //                      VIEW FUNCTIONS
    //-------------------------------------------------------------

    /// @notice Gets array of stat IDs that are available for deposit from the given collection.
    /// @param _collectionAddress The address of the NFT collection to get available stat/token IDs for.
    /// @return Array of stat/token IDs that are available for deposit.
    function getIdsAvailableForDepositByCollection(
        address _collectionAddress
    ) external view returns(uint256[] memory);

    /// @notice Checks if the contracts are set.
    /// @return True if the contracts are set.
    function areContractsSet() external view returns (bool);

    // -------------------------------------------------------------
    //                    EXTERNAL FUNCTIONS
    // -------------------------------------------------------------

    /// @notice Deposits stats from an NFT into the bridge.
    /// @param _collections The addresses of the NFT collections that the stats are being deposited from.
    /// @param _tokenIds The token IDs that the stats are being deposited from.
    /// @param _statIds The stat IDs that are being deposited.
    /// @param _amounts The amount of each stat being deposited.
    function depositStats(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _statIds, 
        uint256[] calldata _amounts
    ) external;

    /// @notice Deposits ERC20 tokens into the bridge.
    /// @param _tokenAddresses The addresses of the ERC20 tokens being deposited.
    /// @param _amounts The amount of each ERC20 token being deposited.
    function depositERC20s(
        address[] calldata _tokenAddresses, 
        uint256[] calldata _amounts
    ) external;

    /// @notice Deposits ERC1155 NFTs into the bridge.
    /// @param _collections The addresses of the NFT collections that the ERC1155 NFTs are from.
    /// @param _tokenIds The token IDs of the ERC1155 NFTs being deposited.
    /// @param _amounts The amount of each ERC1155 NFT ID being deposited.
    function depositERC1155s(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _amounts
    ) external;

    /// @notice Deposits ERC721 NFTs into the bridge.
    /// @param _collections The addresses of the NFT collections that the ERC721 NFTs are from.
    /// @param _tokenIds The token IDs of the ERC721 NFTs being deposited.
    function depositERC721s(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds
    ) external;

    /// @notice Withdraws stats from the bridge.
    /// @param _collections The addresses of the NFT collections that the stats are being withdrawn to.
    /// @param _tokenIds The token IDs that the stats are being withdrawn to.
    /// @param _statIds The stat IDs that are being withdrawn.
    /// @param _amounts The amount of each stat being withdrawn.
    function withdrawStats(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _statIds, 
        uint256[] calldata _amounts
    ) external;

    /// @notice Withdraws ERC20 tokens from the bridge.
    /// @param _tokenAddresses The addresses of the ERC20 tokens being withdrawn.
    /// @param _amounts The amount of each ERC20 token being withdrawn.
    function withdrawERC20s(
        address[] calldata _tokenAddresses, 
        uint256[] calldata _amounts
    ) external;

    /// @notice Withdraws ERC1155 NFTs from the bridge.
    /// @param _collections The addresses of the NFT collections that the ERC1155 NFTs are from.
    /// @param _tokenIds The token IDs of the ERC1155 NFTs being withdrawn.
    /// @param _amounts The amount of each ERC1155 NFT ID being withdrawn.
    function withdrawERC1155s(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds, 
        uint256[] calldata _amounts
    ) external;

    /// @notice Withdraws ERC721 NFTs from the bridge.
    /// @param _collections The addresses of the NFT collections that the ERC721 NFTs are from.
    /// @param _tokenIds The token IDs of the ERC721 NFTs being withdrawn.
    function withdrawERC721s(
        address[] calldata _collections, 
        uint256[] calldata _tokenIds
    ) external;

    //-------------------------------------------------------------------------
    //                      ADMIN FUNCTIONS
    //-------------------------------------------------------------------------

    /// @notice Spends stats from an NFTs balance.
    /// @dev Can only be called by the AUTHORIZED_BALANCE_ADJUSTER_ROLE.
    /// @param _userAddress The address of the wallet that is spending the stats.
    /// @param _collectionAddress The address of the NFT collection that the stats are being spent from.
    /// @param _tokenId The token ID that the stats are being spent from.
    /// @param _statId The stat ID that is being spent.
    /// @param _amount The amount of the stat being spent.
    /// @param _landId The land ID that the stats are being spent on.
    /// @param _message The description of what the stats are being spent on.
    function spendStats(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _statId,
        uint256 _amount,
        uint256 _landId,
        string calldata _message
    ) external;

    /// @notice Spends ERC20 tokens from an users balance.
    /// @dev Can only be called by the AUTHORIZED_BALANCE_ADJUSTER_ROLE.
    /// @param _userAddress The address of the wallet that is spending the tokens.
    /// @param _tokenAddress The address of the ERC20 contract that the tokens are being spent from.
    /// @param _amount The amount of the ERC20 tokens being spent.
    /// @param _landId The land ID that the tokens are being spent on.
    /// @param _message The description of what the tokens are being spent on.
    function spendERC20s(
        address _userAddress,
        address _tokenAddress,
        uint256 _amount,
        uint256 _landId,
        string calldata _message
    ) external;

    /// @notice Spends ERC1155 NFTs from an users balance.
    /// @dev Can only be called by the AUTHORIZED_BALANCE_ADJUSTER_ROLE.
    /// @param _userAddress The address of the wallet that is spending the NFTs.
    /// @param _collectionAddress The address of the NFT collection that the NFTs are being spent from.
    /// @param _tokenId The token ID of the ERC1155 NFT being spent.
    /// @param _amount The amount of the ERC1155 NFT ID being spent.
    /// @param _landId The land ID that the NFTs are being spent on.
    /// @param _message The description of what the NFTs are being spent on.
    function spendERC1155s(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _landId,
        string calldata _message
    ) external;

    /// @notice Spends ERC721 NFTs from an users balance.
    /// @dev Can only be called by the AUTHORIZED_BALANCE_ADJUSTER_ROLE.
    /// @param _userAddress The address of the wallet that is spending the NFT.
    /// @param _collectionAddress The address of the NFT collection that the NFT is being spent from.
    /// @param _tokenId The token ID of the ERC721 NFT being spent.
    /// @param _landId The land ID that the NFT is being spent on.
    /// @param _message The description of what the NFT is being spent on.
    function spendERC721(
        address _userAddress,
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _landId,
        string calldata _message
    ) external;

    /// @notice Sets the approval for a collection to deposit stats.
    /// @dev Can only be called by the owner or admin.
    /// @param _collectionAddress The address of the NFT collection to set approval for.
    /// @param _approved True if the collection is being approved.
    function setCollectionStatDepositApproval(
        address _collectionAddress,
        bool _approved
    ) external;

    /// @notice Sets the approval for a ERC20 token to be deposited.
    /// @dev Can only be called by the owner or admin.
    /// @param _tokenAddress The address of the ERC20 token to set approval for.
    /// @param _approved True if the token is being approved.
    function setERC20DepositApproval(
        address _tokenAddress,
        bool _approved
    ) external;

    /// @notice Sets the approval for a collection to deposit ERC1155 NFTs.
    /// @dev Can only be called by the owner or admin.
    /// @param _collectionAddress The address of the NFT collection to set approval for.
    /// @param _approved True if the collection is being approved.
    function setCollectionERC1155DepositApproval(
        address _collectionAddress,
        bool _approved
    ) external;

    /// @notice Sets the approval for a collection to deposit ERC721 NFTs.
    /// @dev Can only be called by the owner or admin.
    /// @param _collectionAddress The address of the NFT collection to set approval for.
    /// @param _approved True if the collection is being approved.
    function setCollectionERC721DepositApproval(
        address _collectionAddress,
        bool _approved
    ) external;

    /// @notice Sets the approval for a stat ID to be deposited from a specific collection.
    /// @dev Can only be called by the owner or admin.
    /// @param _collectionAddress The address of the NFT collection that the stat is earned by.
    /// @param _statId The stat ID to set approval for.
    /// @param _approved True if the stat ID is being approved.
    function setStatIdDepositApproval(
        address _collectionAddress,
        uint256 _statId,
        bool _approved
    ) external;

    /// @notice Sets the approval for a ERC1155 NFT ID to be deposited from a specific collection.
    /// @dev Can only be called by the owner or admin.
    /// @param _collectionAddress The address of the NFT collection that the ERC1155 NFT is from.
    /// @param _tokenId The ERC1155 NFT ID to set approval for.
    /// @param _approved True if the ERC1155 NFT ID is being approved.
    function setERC1155TokenIdDepositApproval(
        address _collectionAddress,
        uint256 _tokenId,
        bool _approved
    ) external;

    /// @notice Sets the addresses of the necessary contracts.
    /// @dev Can only be called by the owner or admin.
    /// @param _smolLandAddress The address of the land NFT contract.
    /// @param _smolSchoolAddress The address of the smol school contract.
    /// @param _smolBrainsAddress The address of the smol brains contract.
    /// @param _deFragAssetManagerAddress The address of the DeFrag Finance Asset Manager contract.
    /// @param _deFragBalanceSheetAddress The address of the DeFrag Finance Balance Sheet contract.
    function setContracts(
        address _smolLandAddress,
        address _smolSchoolAddress,
        address _smolBrainsAddress,
        address _deFragAssetManagerAddress,
        address _deFragBalanceSheetAddress
    ) external;
    
    //-------------------------------------------------------------
    //                          ERRORS
    //-------------------------------------------------------------

    error ContractsNotSet();
    error ArrayLengthMismatch();
    error AmountMustBeGreaterThanZero();
    error AddressCanOnlyBeApprovedForOneTypeOfDeposit();

    error MustBeOwnerOfNFT(address _collectionAddress, uint256 _tokenId, address _userAddress, address ownerAddress);
    error StatDoesNotExist(address _collectionAddress, uint256 _statId);
    
    error InsufficientNFTBalance(address _collectionAddress, uint256 _nftId, uint256 _amountNeeded, uint256 _amountAvailable);
    error InsufficientStatBalance(address _collectionAddress, uint256 _tokenId, uint256 _statId, uint256 _amountNeeded, uint256 _amountAvailable);
    error InsufficientERC20Balance(address _tokenAddress, uint256 _amountNeeded, uint256 _amountAvailable);

    error IdNotApprovedForDeposit(address _collectionAddress, uint256 _statOrNftId);
    error AlreadyApprovedForDeposit(address _collectionAddress, uint256 _statOrNftId);
    error AddressNotApprovedForDeposit(address _collectionAddress);
    error AddressApprovalAlreadySet(address _collectionAddress, bool _approved);

    error DeFragOnlySupportedForSmolBrains(address _collectionAddress, address smolBrains);
    error UserHasNoTokensOnDeFrag(address _userAddress);
    error DeFragAssetManagerCannotBeUser();

}
