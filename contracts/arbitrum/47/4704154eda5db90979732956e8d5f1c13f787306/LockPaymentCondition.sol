pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./Condition.sol";
import "./ICondition.sol";
import "./DIDRegistry.sol";
import "./Common.sol";
import "./ILockPayment.sol";
import "./IDynamicPricing.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./console.sol";

/**
 * @title Lock Payment Condition
 * @author Nevermined
 *
 * @dev Implementation of the Lock Payment Condition
 * This condition allows to lock payment for multiple receivers taking
 * into account the royalties to be paid to the original creators in a secondary market.  
 */
contract LockPaymentCondition is ILockPayment, ReentrancyGuardUpgradeable, Condition, AccessControlUpgradeable, ICondition {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    uint256 constant public DENOMINATOR = 1000000;
    
    DIDRegistry internal didRegistry;
    INVMConfig internal nvmConfig;
    
    bytes32 constant public CONDITION_TYPE = keccak256('LockPaymentCondition');
    bytes32 constant public KEY_ASSET_RECEIVER = keccak256('_assetReceiverAddress');

    bytes32 private constant PROXY_ROLE = keccak256('PROXY_ROLE');
    bytes32 private constant ALLOWED_EXTERNAL_CONTRACT_ROLE = keccak256('ALLOWED_EXTERNAL_CONTRACT_ROLE');

    function grantProxyRole(address _address) public onlyOwner {
        grantRole(PROXY_ROLE, _address);
    }

    function revokeProxyRole(address _address) public onlyOwner {
        revokeRole(PROXY_ROLE, _address);
    }

    function grantExternalContractRole(address _address) public onlyOwner {
        grantRole(ALLOWED_EXTERNAL_CONTRACT_ROLE, _address);
    }

    function revokeExternalContractRole(address _address) public onlyOwner {
        revokeRole(ALLOWED_EXTERNAL_CONTRACT_ROLE, _address);
    }    
    
   /**
    * @notice initialize init the contract with the following parameters
    * @dev this function is called only once during the contract initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address
    * @param _didRegistryAddress DID Registry address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _didRegistryAddress
    )
        external
        initializer()
    {
        require(
            _didRegistryAddress != address(0) &&
            _conditionStoreManagerAddress != address(0),
            'Invalid address'
        );
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        transferOwnership(_owner);
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
        
        didRegistry = DIDRegistry(
            _didRegistryAddress
        );
        nvmConfig = INVMConfig(
            conditionStoreManager.getNvmConfigAddress()
        );
        
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /**
     * Should be called when the contract has been upgraded.
     */
    function reinitialize() external reinitializer(2) {
        nvmConfig = INVMConfig(
            conditionStoreManager.getNvmConfigAddress()
        );
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did the asset decentralized identifier 
    * @param _rewardAddress the contract address where the reward is locked       
    * @param _tokenAddress the ERC20 contract address to use during the lock payment. 
    *        If the address is 0x0 means we won't use a ERC20 but ETH for payment     
    * @param _amounts token amounts to be locked/released
    * @param _receivers receiver's addresses
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(
            _did,
            _rewardAddress,
            _tokenAddress,
            _amounts,
            _receivers
        ));
    }
    
   /**
    * @notice fulfill requires valid token transfer in order 
    *           to lock the amount of tokens based on the SEA
    * @param _agreementId the agreement identifier
    * @param _did the asset decentralized identifier
    * @param _rewardAddress the contract address where the reward is locked
    * @param _tokenAddress the ERC20 contract address to use during the lock payment.      
    * @param _amounts token amounts to be locked/released
    * @param _receivers receiver's addresses
    * @return condition state
    */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address payable _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
    external
    override
    payable
    nonReentrant
    returns (ConditionStoreLibrary.ConditionState)
    {
        return fulfillInternal(_msgSender(), _agreementId, _did, _rewardAddress, _tokenAddress, _amounts, _receivers);
    }

    /**
     * @notice fulfill lock condition using the funds locked in an external contract 
     *          (auction, bonding curve, lottery, etc) 
    * @param _agreementId the agreement identifier
    * @param _did the asset decentralized identifier
    * @param _rewardAddress the contract address where the reward is locked
    * @param _externalContract the address of the contract with the lock funds are locked
    * @param _remoteId the id used to identify into the external contract 
    * @param _amounts token amounts to be locked/released
    * @param _receivers receiver's addresses
    * @return condition state
    */
    function fulfillExternal(
        bytes32 _agreementId,
        bytes32 _did,
        address payable _rewardAddress,
        address _externalContract,
        bytes32 _remoteId,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
    external
    payable
    allowedExternalContract(_externalContract)
    nonReentrant
    returns (ConditionStoreLibrary.ConditionState)
    {
        address tokenAddress = IDynamicPricing(_externalContract).getTokenAddress(_remoteId);
        require(
            _amounts.length == _receivers.length,
            'Amounts and Receivers arguments have wrong length'
        );
        require(
            didRegistry.areRoyaltiesValid(_did, _amounts, _receivers, tokenAddress),
            'Royalties are not satisfied'
        );

        require(
            areMarketplaceFeesIncluded(_amounts, _receivers),
            'Invalid marketplace fees'
        );        

        {
            (IDynamicPricing.DynamicPricingState externalState, uint256 externalAmount, address whoCanClaim) =
                IDynamicPricing(_externalContract).getStatus(_remoteId);

            require(_msgSender() == whoCanClaim, 'No allowed');
            require(externalState != IDynamicPricing.DynamicPricingState.NotStarted &&
                externalState != IDynamicPricing.DynamicPricingState.Aborted, 'Invalid external state');
            require(calculateTotalAmount(_amounts) == externalAmount, 'Amounts dont match');

            require(IDynamicPricing(_externalContract).withdraw(_remoteId, _rewardAddress), 'Unable to withdraw');
        }
    
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _rewardAddress, tokenAddress, _amounts, _receivers)
        );
        
        ConditionStoreLibrary.ConditionState state = super.fulfillWithProvenance(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled,
            _did,
            'LockPaymentCondition',
            _msgSender()
        );

        emit Fulfilled(
            _agreementId,
            _did,
            _id,
            _rewardAddress,
            _externalContract,
            _receivers,
            _amounts
        );
        return state;
    }

    function encodeParams(
        bytes32 _did,
        address payable _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    ) external pure returns (bytes memory) {
        return abi.encode(_did, _rewardAddress, _tokenAddress, _amounts, _receivers);
    }

    function fulfillInternal(
        address _account,
        bytes32 _agreementId,
        bytes32 _did,
        address payable _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
    internal
    returns (ConditionStoreLibrary.ConditionState)
    {
        require(
            _amounts.length == _receivers.length,
            'Amounts and Receivers arguments have wrong length'
        );

        require(
            didRegistry.areRoyaltiesValid(_did, _amounts, _receivers, _tokenAddress),
            'Royalties are not satisfied'
        );
        
        require(
            areMarketplaceFeesIncluded(_amounts, _receivers), 
            'Invalid marketplace fees'
        );

        if (_tokenAddress != address(0))
            _transferERC20Proxy(_account, _rewardAddress, _tokenAddress, calculateTotalAmount(_amounts));
        else
            _transferETH(_rewardAddress, calculateTotalAmount(_amounts));

        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _rewardAddress, _tokenAddress, _amounts, _receivers)
        );
        
        ConditionStoreLibrary.ConditionState state = super.fulfillWithProvenance(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled,
            _did,
            'LockPaymentCondition',
            _msgSender()
        );

        emit Fulfilled(
            _agreementId, 
            _did,
            _id,
            _rewardAddress,
            _tokenAddress,
            _receivers, 
            _amounts
        );
        return state;
    }

    function fulfillProxy(
        address _account,
        bytes32 _agreementId,
        bytes memory params
    )
    external
    payable
    nonReentrant
    {
        bytes32 _did;
        address payable _rewardAddress;
        address _tokenAddress;
        uint256[] memory _amounts;
        address[] memory _receivers;
        (_did, _rewardAddress, _tokenAddress, _amounts, _receivers) = abi.decode(params, (bytes32, address, address, uint256[], address[]));
        require(hasRole(PROXY_ROLE, _msgSender()), 'Invalid access role');
        fulfillInternal(_account, _agreementId, _did, _rewardAddress, _tokenAddress, _amounts, _receivers);
    }
 
   /**
    * @notice _transferERC20Proxy transfer ERC20 tokens 
    * @param _senderAddress the address to send the tokens from
    * @param _rewardAddress the address to receive the tokens
    * @param _tokenAddress the ERC20 contract address to use during the payment
    * @param _amount token amount to be locked/released
    * @dev Will throw if transfer fails
    */
    function _transferERC20Proxy(
        address _senderAddress,
        address _rewardAddress,
        address _tokenAddress,
        uint256 _amount
    )
    internal
    {
        IERC20Upgradeable token = ERC20Upgradeable(_tokenAddress);
        token.safeTransferFrom(_senderAddress, _rewardAddress, _amount);
    }

   /**
    * @notice _transferETH transfer ETH 
    * @param _rewardAddress the address to receive the ETH
    * @param _amount ETH amount to be locked/released
    */    
    function _transferETH(
        address payable _rewardAddress,
        uint256 _amount
    )
    internal
    {
        require(
            msg.value == _amount, 
            'Transaction value does not match amount'
        );
        // solhint-disable-next-line
        (bool sent,) = _rewardAddress.call{value: _amount}('');
        require(sent, 'Failed to send Ether');
    }

    modifier allowedExternalContract(address _externalContractAddress) {
        require(
            hasRole(ALLOWED_EXTERNAL_CONTRACT_ROLE, _externalContractAddress), 
                'Invalid external contract'
        );
        _;
    }

    function areMarketplaceFeesIncluded(
        uint256[] memory _amounts, 
        address[] memory _receivers
    )
    internal
    view
    returns (bool)
    {
        if (nvmConfig.getMarketplaceFee() == 0 || nvmConfig.getFeeReceiver() == address(0))
            return true; // No fees configured so they are not required
        
        uint256 totalAmount = calculateTotalAmount(_amounts);
        if (totalAmount == 0)
            return true; // It's a free asset so no fees are required
        
        bool marketplaceReceiverIsIncluded = false;
        uint receiverIndex = 0;
        
        for(uint i = 0; i < _receivers.length; i++)    {
            if (_receivers[i] == nvmConfig.getFeeReceiver())    {
                marketplaceReceiverIsIncluded = true;
                receiverIndex = i;
            }
        }
        if (!marketplaceReceiverIsIncluded) // Marketplace receiver not included as part of the fees
            return false;
        
        // Return if fee calculation is correct
        return nvmConfig.getMarketplaceFee().mul(totalAmount).div(DENOMINATOR) == _amounts[receiverIndex];
    }


    function _msgSender() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }
}

