pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./Common.sol";
import "./DIDFactory.sol";
import "./NFT1155Upgradeable.sol";
import "./NFT721Upgradeable.sol";
import "./StandardRoyalties.sol";

/**
 * @title DID Registry
 * @author Nevermined
 *
 * @dev Implementation of an on-chain registry of assets. It allows users to register their digital assets
 * and the on-chain resolution of them via a Decentralized Identifier (DID) into their Metadata (DDO).  
 *
 * The permissions are organized in different levels:
 *
 * 1. Contract Ownership Level. At the top level the DID Registry contract is 'Ownable' so the owner (typically the deployer) of the contract
 *    can manage everything in the registry.
 * 2. Contract Operator Level. At the second level we have the Registry contract operator `REGISTRY_OPERATOR_ROLE`. Typically this role is 
 *    granted to some Nevermined contracts to automate the execution of common functions.
 *    This role is managed using the  `grantRegistryOperatorRole` and `revokeRegistryOperatorRole` function
 * 3. Asset Access Level. Asset owners can provide individual asset permissions to external providers via the `addProvider` function.
 *    Providers typically (Nevermined Nodes) can manage asset access. 
 * 4. Asset Provenance Level. Provenance delegates can register provenance events at asset level.
 */
contract DIDRegistry is DIDFactory {

    using DIDRegistryLibrary for DIDRegistryLibrary.DIDRegisterList;

    NFT1155Upgradeable public erc1155;
    NFT721Upgradeable public erc721;

    mapping (address => bool) public royaltiesCheckers;
    StandardRoyalties public defaultRoyalties;

    INVMConfig public nvmConfig;

    // Role to operate the NFT contract
    bytes32 public constant REGISTRY_OPERATOR_ROLE = keccak256('REGISTRY_OPERATOR_ROLE');
    
    modifier onlyRegistryOperator
    {
        require(
            isRegistryOperator(_msgSender()),
            'Only registry operator'
        );
        _;
    }    
    
    //////////////////////////////////////////////////////////////
    ////////  EVENTS  ////////////////////////////////////////////
    //////////////////////////////////////////////////////////////
    
    /**
     * @dev DIDRegistry Initializer
     *      Initialize Ownable. Only on contract creation.
     * @param _owner refers to the owner of the contract.
     */
    function initialize(
        address _owner,
        address _erc1155,
        address _erc721,
        address _config,
        address _royalties
    )
    public
    initializer
    {
        OwnableUpgradeable.__Ownable_init();
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(REGISTRY_OPERATOR_ROLE, _owner);
        
        erc1155 = NFT1155Upgradeable(_erc1155);
        erc721 = NFT721Upgradeable(_erc721);
        transferOwnership(_owner);
        manager = _owner;
        defaultRoyalties = StandardRoyalties(_royalties);
        nvmConfig = INVMConfig(_config);
    }

    function setDefaultRoyalties(address _royalties) public onlyOwner {
        defaultRoyalties = StandardRoyalties(_royalties);
    }

    function registerRoyaltiesChecker(address _addr) public onlyOwner {
        royaltiesCheckers[_addr] = true;
    }

    function setNFT1155(address _erc1155) public onlyOwner {
        erc1155 = NFT1155Upgradeable(_erc1155);
    }

    ///// PERMISSIONS
    function grantRegistryOperatorRole(
        address account
    )
    public
    virtual
    onlyOwner
    {
        AccessControlUpgradeable._setupRole(REGISTRY_OPERATOR_ROLE, account);
    }

    function revokeRegistryOperatorRole(
        address account
    )
    public
    virtual
    onlyOwner
    {
        AccessControlUpgradeable._revokeRole(REGISTRY_OPERATOR_ROLE, account);
    }

    function isRegistryOperator(
        address operator
    )
    public
    view
    virtual
    returns (bool)
    {
        return AccessControlUpgradeable.hasRole(REGISTRY_OPERATOR_ROLE, operator);
    }

    event DIDRoyaltiesAdded(bytes32 indexed did, address indexed addr);
    event DIDRoyaltyRecipientChanged(bytes32 indexed did, address indexed addr);

    function setDIDRoyalties(
        bytes32 _did,
        address _royalties
    )
    public
    {
        require(didRegisterList.didRegisters[_did].creator == _msgSender(), 'Only creator can set royalties');
        require(address(didRegisterList.didRegisters[_did].royaltyScheme) == address(0), 'Cannot change royalties');
        didRegisterList.didRegisters[_did].royaltyScheme = IRoyaltyScheme(_royalties);

        emit DIDRoyaltiesAdded(
            _did,
            _royalties
        );
    }

    function setDIDRoyaltyRecipient(
        bytes32 _did,
        address _recipient
    )
    public
    {
        require(didRegisterList.didRegisters[_did].creator == _msgSender(), 'Only creator can set royalties');
        didRegisterList.didRegisters[_did].royaltyRecipient = _recipient;

        emit DIDRoyaltyRecipientChanged(
            _did,
            _recipient
        );
    }

    /**
     * @notice transferDIDOwnershipManaged transfer DID ownership
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _newOwner new owner address
     */
    function transferDIDOwnershipManaged(address _sender, bytes32 _did, address _newOwner)
    external
    onlyRegistryOperator
    {
        _transferDIDOwnership(_sender, _did, _newOwner);
    }

    /**
     * @notice Register a Mintable DID using NFTs based in the ERC-1155 standard.
     *
     * @dev The first attribute of a DID registered sets the DID owner.
     *      Subsequent updates record _checksum and update info.
     *
     * @param _didSeed refers to decentralized identifier seed (a bytes32 length ID).
     * @param _nftContractAddress is the address of the NFT contract associated to the asset
     * @param _checksum includes a one-way HASH calculated using the DDO content.
     * @param _providers list of addresses that can act as an asset provider     
     * @param _url refers to the url resolving the DID into a DID Document (DDO), limited to 2048 bytes.
     * @param _cap refers to the mint cap
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _mint if true it mints the ERC-1155 NFTs attached to the asset
     * @param _activityId refers to activity
     * @param _nftMetadata refers to the url providing the NFT Metadata 
     * @param _immutableUrl includes the url to the DDO in immutable storage              
     */
    function registerMintableDID(
        bytes32 _didSeed,
        address _nftContractAddress,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        uint256 _cap,
        uint256 _royalties,
        bool _mint,
        bytes32 _activityId,
        string memory _nftMetadata,
        string memory _immutableUrl
    )
    public
    onlyValidAttributes(_nftMetadata)
    {
        registerDID(_didSeed, _checksum, _providers, _url, _activityId, _immutableUrl);
        enableAndMintDidNft(
            hashDID(_didSeed, _msgSender()),
            _nftContractAddress,
            _cap,
            _royalties,
            _mint,
            _nftMetadata
        );
    }

    /**
     * @notice Register a Mintable DID using NFTs based in the ERC-721 standard.
     *
     * @dev The first attribute of a DID registered sets the DID owner.
     *      Subsequent updates record _checksum and update info.
     *
     * @param _didSeed refers to decentralized identifier seed (a bytes32 length ID).
     * @param _nftContractAddress address of the NFT contract associated to the asset
     * @param _checksum includes a one-way HASH calculated using the DDO content.
     * @param _providers list of addresses that can act as an asset provider     
     * @param _url refers to the url resolving the DID into a DID Document (DDO), limited to 2048 bytes.
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _mint if true it mints the ERC-1155 NFTs attached to the asset
     * @param _activityId refers to activity
     * @param _immutableUrl includes the url to the DDO in immutable storage       
     */
    function registerMintableDID721(
        bytes32 _didSeed,
        address _nftContractAddress,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        uint256 _royalties,
        bool _mint,
        bytes32 _activityId,
        string memory _immutableUrl
    )
    public
    {
        registerDID(_didSeed, _checksum, _providers, _url, _activityId, _immutableUrl);
        enableAndMintDidNft721(
            hashDID(_didSeed, _msgSender()),
            _nftContractAddress,
            _royalties,
            _mint
        );
    }



    /**
     * @notice Register a Mintable DID.
     *
     * @dev The first attribute of a DID registered sets the DID owner.
     *      Subsequent updates record _checksum and update info.
     *
     * @param _didSeed refers to decentralized identifier seed (a bytes32 length ID).
     * @param _nftContractAddress address of the NFT contract associated to the asset     
     * @param _checksum includes a one-way HASH calculated using the DDO content.
     * @param _providers list of addresses that can act as an asset provider     
     * @param _url refers to the url resolving the DID into a DID Document (DDO), limited to 2048 bytes.
     * @param _cap refers to the mint cap
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _activityId refers to activity
     * @param _nftMetadata refers to the url providing the NFT Metadata
     * @param _immutableUrl includes the url to the DDO in immutable storage               
     */
    function registerMintableDID(
        bytes32 _didSeed,
        address _nftContractAddress,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        uint256 _cap,
        uint256 _royalties,
        bytes32 _activityId,
        string memory _nftMetadata,
        string memory _immutableUrl
    )
    public
    onlyValidAttributes(_nftMetadata)
    {
        registerMintableDID(
            _didSeed, _nftContractAddress, _checksum, _providers, _url, _cap, _royalties, false, _activityId, _nftMetadata, _immutableUrl);
    }

    
    /**
     * @notice enableDidNft creates the initial setup of NFTs minting and royalties distribution for ERC-1155 NFTs.
     * After this initial setup, this data can't be changed anymore for the DID given, even for the owner of the DID.
     * The reason of this is to avoid minting additional NFTs after the initial agreement, what could affect the 
     * valuation of NFTs of a DID already created.
      
     * @dev update the DID registry providers list by adding the mintCap and royalties configuration
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _cap refers to the mint cap
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _mint if is true mint directly the amount capped tokens and lock in the _lockAddress
     * @param _nftMetadata refers to the url providing the NFT Metadata          
     */
    function enableAndMintDidNft(
        bytes32 _did,
        address _nftAddress,
        uint256 _cap,
        uint256 _royalties,
        bool _mint,
        string memory _nftMetadata
    )
    public
    onlyDIDOwner(_did)
    returns (bool success)
    {
        didRegisterList.initializeNftConfig(_did, _nftAddress, _royalties > 0 ? defaultRoyalties : IRoyaltyScheme(address(0)));
        NFT1155Upgradeable _nftInstance;
        if (_nftAddress == address(0))
            _nftInstance = erc1155;
        else
            _nftInstance = NFT1155Upgradeable(_nftAddress);
        
        _nftInstance.setNFTAttributes(uint256(_did), 0, _cap, _nftMetadata);
        
        if (_royalties > 0) {
            _nftInstance.setTokenRoyalty(uint256(_did), _msgSender(), _royalties);
            if (address(defaultRoyalties) != address(0)) defaultRoyalties.setRoyalty(_did, _royalties);
        }
        
        if (_mint)
            _nftInstance.mint(_msgSender() ,uint256(_did), _cap, '');
        
        return super.used(
            keccak256(abi.encode(_did, _cap, _royalties, _msgSender())),
            _did, _msgSender(), keccak256('enableNft'), '', 'nft initialization');
    }

    /**
     * @notice enableAndMintDidNft721 creates the initial setup of NFTs minting and royalties distribution for ERC-721 NFTs.
     * After this initial setup, this data can't be changed anymore for the DID given, even for the owner of the DID.
     * The reason of this is to avoid minting additional NFTs after the initial agreement, what could affect the 
     * valuation of NFTs of a DID already created.
      
     * @dev update the DID registry providers list by adding the mintCap and royalties configuration
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _nftContractAddress address of the NFT contract associated to the asset     
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _mint if is true mint directly the amount capped tokens and lock in the _lockAddress          
     */    
    function enableAndMintDidNft721(
        bytes32 _did,
        address _nftContractAddress,
        uint256 _royalties,
        bool _mint
    )
    public
    onlyDIDOwner(_did)
    returns (bool success)
    {
        didRegisterList.initializeNft721Config(_did, _nftContractAddress, _royalties > 0 ? defaultRoyalties : IRoyaltyScheme(address(0)));

        NFT721Upgradeable _nftInstance;
        if (_nftContractAddress == address(0))
            _nftInstance = erc721;
        else
            _nftInstance = NFT721Upgradeable(_nftContractAddress);
        
        if (_royalties > 0) {
            if (address(defaultRoyalties) != address(0)) defaultRoyalties.setRoyalty(_did, _royalties);
            _nftInstance.setTokenRoyalty(uint256(_did), _msgSender(), _royalties);
        }
        
        if (_mint)
            _nftInstance.mint(_msgSender() ,uint256(_did));
        
        return super.used(
            keccak256(abi.encode(_did, 1, _royalties, _msgSender())),
            _did, _msgSender(), keccak256('enableNft721'), '', 'nft initialization');
    }

    function _provenanceStorage() override internal view returns (bool) {
        return address(nvmConfig) == address(0) || nvmConfig.getProvenanceStorage();
    }

    function registerUsedProvenance(bytes32 _did, bytes32 _cond, string memory name, address user) public onlyRegistryOperator {
        _used(_cond, _did, user, keccak256(bytes(name)), '', name);
    }

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        return address(nvmConfig);
    }
}

