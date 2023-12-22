pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./Condition.sol";
import "./ICondition.sol";
import "./NFT1155Upgradeable.sol";
import "./ITransferNFT.sol";
import "./AccessControlUpgradeable.sol";

/**
 * @title Transfer NFT Condition
 * @author Nevermined
 *
 * @dev Implementation of condition allowing to transfer an NFT
 *      between the original owner and a receiver
 *
 */
contract TransferNFTCondition is Condition, ITransferNFT, ReentrancyGuardUpgradeable, AccessControlUpgradeable, ICondition {

    bytes32 private constant CONDITION_TYPE = keccak256('TransferNFTCondition');

    bytes32 private constant MARKET_ROLE = keccak256('MARKETPLACE_ROLE');
    
    NFT1155Upgradeable private erc1155;

    DIDRegistry internal didRegistry;

    bytes32 private constant PROXY_ROLE = keccak256('PROXY_ROLE');

    function grantProxyRole(address _address) public onlyOwner {
        grantRole(PROXY_ROLE, _address);
    }

    function revokeProxyRole(address _address) public onlyOwner {
        revokeRole(PROXY_ROLE, _address);
    }

   /**
    * @notice initialize init the contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address 
    * @param _didRegistryAddress DID Registry address       
    * @param _ercAddress Nevermined ERC-1155 address
    * @param _nftContractAddress Market address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _didRegistryAddress,
        address _ercAddress,
        address _nftContractAddress
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _conditionStoreManagerAddress != address(0) &&
            _ercAddress != address(0),
            'Invalid address'
        );
        
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
        
        didRegistry = DIDRegistry(
            _didRegistryAddress
        );
        
        erc1155 = NFT1155Upgradeable(
            _ercAddress
        );

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        if (_nftContractAddress != address(0))
            grantRole(MARKET_ROLE, _nftContractAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function grantMarketRole(address _nftContractAddress)
        public 
        onlyOwner 
    {
        grantRole(MARKET_ROLE, _nftContractAddress);
    }


    function revokeMarketRole(address _nftContractAddress)
        public
        onlyOwner 
    {
        revokeRole(MARKET_ROLE, _nftContractAddress);
    }

    function getNFTDefaultAddress()
        override
        external
        view
        returns (address)
    {
        return address(erc1155);
    }    
    
   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _nftReceiver is the address of the granted user or the DID provider
    * @param _nftAmount amount of NFTs to transfer
    * @param _lockCondition lock condition identifier
    * @return bytes32 hash of all these values
    */
    function hashValues(
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockCondition
    )
        public
        view
        returns (bytes32)
    {
        return hashValues(_did, _nftHolder, _nftReceiver, _nftAmount, _lockCondition, address(erc1155), true);
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _nftReceiver is the address of the granted user or the DID provider
    * @param _nftAmount amount of NFTs to transfer
    * @param _lockCondition lock condition identifier
    * @param _nftContractAddress NFT contract to use
    * @param _transfer Indicates if the NFT will be transferred (true) or minted (false)
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockCondition,
        address _nftContractAddress,
        bool _transfer
    )
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(_did, _nftHolder, _nftReceiver, _nftAmount, _lockCondition, _nftContractAddress, _transfer));
    }

    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        return fulfill(_agreementId, _did, _nftReceiver, _nftAmount, _lockPaymentCondition, address(erc1155), true);
    }

    /**
     * @notice Encodes/serialize all the parameters received
     *
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftHolder is the address of the account to receive the NFT
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer  
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _nftContractAddress the NFT contract to use     
     * @param _transfer if yes it does a transfer if false it mints the NFT
     * @return the encoded parameters
     */
    function encodeParams(
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _nftContractAddress,
        bool _transfer
    ) external pure returns (bytes memory) {
        return abi.encode(_did, _nftHolder, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress, _transfer);
    }

    /**
     * @notice fulfill the transfer NFT condition by a proxy
     * @dev Fulfill method transfer a certain amount of NFTs 
     *
     * @param _account NFT Holder
     * @param _agreementId agreement identifier
     * @param _params encoded parameters
     */
    function fulfillProxy(
        address _account,
        bytes32 _agreementId,
        bytes memory _params
    )
    external
    payable
    nonReentrant
    {
        bytes32 _did;
        address _nftReceiver;
        address _nftHolder;
        uint256 _nftAmount;
        bytes32 _lockPaymentCondition;
        address _nftContractAddress;
        bool _transfer;
        (_did, _nftHolder, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress, _transfer) = abi.decode(_params, (bytes32, address, address, uint256, bytes32, address, bool));

        require(hasRole(PROXY_ROLE, _msgSender()), 'Proxy role required');
        fulfillInternal(_account, _agreementId, _did, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress, _transfer);
    }
    
    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs 
     *       to the _nftReceiver address. 
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer  
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _nftContractAddress NFT contract to use
     * @param _transfer Indicates if the NFT will be transferred (true) or minted (false)     
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _nftContractAddress,
        bool _transfer
    )
        public
        override
        nonReentrant
        returns (ConditionStoreLibrary.ConditionState)
    {
        return fulfillInternal(_msgSender(), _agreementId, _did, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress, _transfer);
    }

    function fulfillInternal(
        address _account,
        bytes32 _agreementId,
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _nftContractAddress,
        bool _transfer
    )
        internal
        returns (ConditionStoreLibrary.ConditionState)
    {
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _account, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress, _transfer)
        );

        require(
            conditionStoreManager.getConditionState(_lockPaymentCondition) == ConditionStoreLibrary.ConditionState.Fulfilled, 'LockCondition needs to be Fulfilled'
        );

        NFT1155Upgradeable token = NFT1155Upgradeable(_nftContractAddress);

        if (_nftAmount > 0) {
            if (_transfer) // Transfer only works if `_account` (_msgSender()) is holder
                token.safeTransferFrom(_account, _nftReceiver, uint256(_did), _nftAmount, '');
            else  {// Check that `account` (_msgSender()) is DID owner or provider
                require(didRegistry.isDIDProviderOrOwner(_did, _account), 'Only owner or provider');
                token.mint(_nftReceiver, uint256(_did), _nftAmount, '');
            }
        }

        ConditionStoreLibrary.ConditionState state = super.fulfillWithProvenance(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled,
            _did,
            'TransferNFTCondition',
            _msgSender()
        );

        emit Fulfilled(
            _agreementId,
            _did,
            _nftReceiver,
            _nftAmount,
            _id,
            _nftContractAddress
        );

        return state;
    }    
    
    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs 
     *       to the _nftReceiver address in the DIDRegistry contract. 
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer  
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _nftHolder is the address of the account to receive the NFT
     * @param _transfer if yes it does a transfer if false it mints the NFT
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfillForDelegate(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        bool _transfer
    )
        public
    
    returns (ConditionStoreLibrary.ConditionState)
    {
        return fulfillForDelegate(_agreementId, _did, _nftHolder, _nftReceiver, _nftAmount, _lockPaymentCondition, address(erc1155), _transfer);
    }


    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs 
     *       to the _nftReceiver address in the DIDRegistry contract. 
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer  
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _nftHolder is the address of the account to receive the NFT
     * @param _nftContractAddress the address of the ERC-721 NFT contract      
     * @param _transfer if yes it does a transfer if false it mints the NFT
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfillForDelegate(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _nftContractAddress,
        bool _transfer
    )
    public

    returns (ConditionStoreLibrary.ConditionState)
    {
        require(hasRole(MARKET_ROLE, _msgSender())
            || NFT1155Upgradeable(_nftContractAddress).isApprovedForAll(_nftHolder, _msgSender())
            || didRegistry.isDIDProviderOrOwner(_did, _msgSender())
        , 'Only Market role or approvedForAll');
        return fulfillInternal(_nftHolder, _agreementId, _did, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress, _transfer);
    }

    function _msgSender() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }

}


